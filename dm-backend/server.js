require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const admin = require('firebase-admin');

const app = express();
app.use(cors());
app.use(express.json());

// --- Configuration ---
const RC_SECRET_KEY = process.env.REVENUECAT_SECRET_KEY || '';
const RC_ENTITLEMENT_ID = 'Docker Manager Pro';
const RC_API_BASE = 'https://api.revenuecat.com/v1';

// Cache TTL for entitlement checks (5 minutes)
const ENTITLEMENT_CACHE_TTL = 5 * 60 * 1000;

if (!RC_SECRET_KEY) {
  console.warn('⚠️  REVENUECAT_SECRET_KEY not set — entitlement verification DISABLED');
  console.warn('   All requests will be allowed through without Pro verification');
}

// --- Firebase Admin Init ---
// Place your Firebase service account key as firebase-service-account.json
// or set FIREBASE_SERVICE_ACCOUNT env var with the JSON content
let firebaseInitialized = false;
try {
  const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT
    ? JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)
    : require('./firebase-service-account.json');

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  firebaseInitialized = true;
  console.log('✅ Firebase Admin initialized');
} catch (e) {
  console.warn('⚠️  Firebase not initialized — FCM notifications will not work');
  console.warn('   Place firebase-service-account.json in this directory or set FIREBASE_SERVICE_ACCOUNT env var');
}

// --- In-Memory Storage ---
// In production, replace with a proper database (Redis, Postgres, etc.)

// Map: rc_user_id -> Set of FCM tokens
const userTokens = new Map();

// Map: pairing_token -> { rc_user_id, server_id, created_at }
const pairingTokens = new Map();

// Map: server_id -> { rc_user_id, status, last_seen }
const registeredServers = new Map();

// Map: rc_user_id -> { isPro, checked_at }
const entitlementCache = new Map();

// --- RevenueCat Entitlement Verification ---

/**
 * Verify that a RevenueCat user has an active Pro entitlement.
 * Uses the RC REST API with the secret key. Results are cached.
 * 
 * @param {string} rcUserId - The RevenueCat user ID
 * @returns {Promise<boolean>} - true if user has active Pro entitlement
 */
async function verifyProEntitlement(rcUserId) {
  // If no secret key configured, allow all (graceful degradation)
  if (!RC_SECRET_KEY) {
    return true;
  }

  // Check cache first
  const cached = entitlementCache.get(rcUserId);
  if (cached && (Date.now() - cached.checked_at < ENTITLEMENT_CACHE_TTL)) {
    return cached.isPro;
  }

  try {
    const response = await fetch(`${RC_API_BASE}/subscribers/${encodeURIComponent(rcUserId)}`, {
      headers: {
        'Authorization': `Bearer ${RC_SECRET_KEY}`,
        'Content-Type': 'application/json',
      },
    });

    if (!response.ok) {
      console.error(`  ❌ RC API error: ${response.status} for user ${rcUserId.substring(0, 8)}...`);
      // On API error, check cache (even expired) as fallback
      if (cached) return cached.isPro;
      // If no cache at all, deny
      return false;
    }

    const data = await response.json();
    const entitlements = data?.subscriber?.entitlements || {};
    const proEntitlement = entitlements[RC_ENTITLEMENT_ID];

    // Check if entitlement exists and hasn't expired
    const isPro = proEntitlement != null &&
      new Date(proEntitlement.expires_date) > new Date();

    // Update cache
    entitlementCache.set(rcUserId, {
      isPro,
      checked_at: Date.now(),
    });

    return isPro;
  } catch (e) {
    console.error(`  ❌ RC verification failed: ${e.message}`);
    // On network error, check cache (even expired) as fallback
    if (cached) return cached.isPro;
    return false;
  }
}

/**
 * Express middleware that verifies Pro entitlement for the rc_user_id in req.body.
 */
async function requireProEntitlement(req, res, next) {
  const { rc_user_id } = req.body;

  if (!rc_user_id) {
    return res.status(400).json({ error: 'rc_user_id is required' });
  }

  const isPro = await verifyProEntitlement(rc_user_id);

  if (!isPro) {
    console.log(`🚫 Denied: user ${rc_user_id.substring(0, 8)}... does not have Pro entitlement`);
    return res.status(403).json({ error: 'Active Pro subscription required' });
  }

  next();
}

// --- API Routes ---

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    firebase: firebaseInitialized,
    rc_verification: !!RC_SECRET_KEY,
  });
});

// POST /api/register-token
// Register an FCM token for a RevenueCat user
// Protected: requires active Pro entitlement
app.post('/api/register-token', requireProEntitlement, (req, res) => {
  const { fcm_token, rc_user_id } = req.body;

  if (!fcm_token) {
    return res.status(400).json({ error: 'fcm_token is required' });
  }

  if (!userTokens.has(rc_user_id)) {
    userTokens.set(rc_user_id, new Set());
  }
  userTokens.get(rc_user_id).add(fcm_token);

  console.log(`📱 Token registered for user ${rc_user_id.substring(0, 8)}... (${userTokens.get(rc_user_id).size} total)`);
  res.json({ success: true });
});

// POST /api/pairing/generate
// Generate a pairing token for a server
// Protected: requires active Pro entitlement
app.post('/api/pairing/generate', requireProEntitlement, (req, res) => {
  const { rc_user_id, server_id } = req.body;

  if (!server_id) {
    return res.status(400).json({ error: 'server_id is required' });
  }

  // Generate a random token
  const token = crypto.randomBytes(32).toString('hex');

  pairingTokens.set(token, {
    rc_user_id,
    server_id,
    created_at: Date.now(),
  });

  // Clean up expired tokens (older than 1 hour)
  for (const [t, data] of pairingTokens) {
    if (Date.now() - data.created_at > 3600000) {
      pairingTokens.delete(t);
    }
  }

  console.log(`🔑 Pairing token generated for server ${server_id.substring(0, 8)}...`);
  res.json({ token });
});

// GET /api/pairing/status/:serverId
// Check if a dm-notifier is registered for a server
app.get('/api/pairing/status/:serverId', (req, res) => {
  const { serverId } = req.params;
  const server = registeredServers.get(serverId);

  if (!server) {
    return res.json({ status: 'not_paired' });
  }

  // Check if it's been more than 5 minutes since last event
  const isStale = Date.now() - server.last_seen > 300000;

  res.json({
    status: isStale ? 'stale' : 'paired',
    last_seen: server.last_seen,
  });
});

// POST /api/events
// Receive Docker events from dm-notifier and forward as FCM push
app.post('/api/events', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing authorization' });
  }

  const token = authHeader.substring(7);
  const pairingData = pairingTokens.get(token);

  if (!pairingData) {
    return res.status(401).json({ error: 'Invalid token' });
  }

  const { server_id, event_type, action, container_name, image, timestamp } = req.body;

  // Update last_seen
  const serverData = registeredServers.get(server_id || pairingData.server_id);
  if (serverData) {
    serverData.last_seen = Date.now();
  }

  console.log(`🐳 Event: ${container_name} — ${action} (server: ${(server_id || pairingData.server_id).substring(0, 8)}...)`);

  // Get human-readable action
  const actionEmoji = {
    start: '▶️',
    stop: '⏹️',
    die: '💀',
    restart: '🔄',
    oom: '⚠️',
    kill: '🔴',
    pause: '⏸️',
    unpause: '▶️',
  };

  const emoji = actionEmoji[action] || '🐳';
  const title = `${emoji} ${container_name || 'Container'}`;
  const body = `${action.charAt(0).toUpperCase() + action.slice(1)}${image ? ` (${image})` : ''}`;

  // Send FCM notifications to all of this user's devices
  const rcUserId = pairingData.rc_user_id;
  const tokens = userTokens.get(rcUserId);

  if (!tokens || tokens.size === 0) {
    console.log(`  ⚠️  No FCM tokens for user ${rcUserId.substring(0, 8)}...`);
    return res.json({ success: true, notifications_sent: 0 });
  }

  if (!firebaseInitialized) {
    console.log('  ⚠️  Firebase not initialized — skipping FCM');
    return res.json({ success: true, notifications_sent: 0 });
  }

  // Send to all tokens
  const tokenArray = Array.from(tokens);
  let successCount = 0;
  const invalidTokens = [];

  for (const fcmToken of tokenArray) {
    try {
      await admin.messaging().send({
        token: fcmToken,
        notification: { title, body },
        data: {
          server_id: server_id || pairingData.server_id,
          event_type: event_type || 'container',
          action: action || '',
          container_name: container_name || '',
          image: image || '',
          timestamp: String(timestamp || Date.now()),
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'docker_events',
            priority: 'high',
          },
        },
      });
      successCount++;
    } catch (e) {
      if (
        e.code === 'messaging/registration-token-not-registered' ||
        e.code === 'messaging/invalid-registration-token'
      ) {
        invalidTokens.push(fcmToken);
      } else {
        console.error(`  ❌ FCM send error: ${e.message}`);
      }
    }
  }

  // Clean up invalid tokens
  for (const invalid of invalidTokens) {
    tokens.delete(invalid);
    console.log(`  🗑️  Removed invalid FCM token`);
  }

  console.log(`  📤 Sent ${successCount}/${tokenArray.length} notifications`);
  res.json({ success: true, notifications_sent: successCount });
});

// POST /api/webhook/revenuecat
// RevenueCat webhook for subscription status changes
app.post('/api/webhook/revenuecat', (req, res) => {
  // Optional: verify webhook authorization header
  // RevenueCat sends an Authorization header you can configure in their dashboard
  const authHeader = req.headers.authorization;
  const expectedAuth = process.env.REVENUECAT_WEBHOOK_AUTH;
  if (expectedAuth && authHeader !== `Bearer ${expectedAuth}`) {
    console.log('🚫 Rejected webhook: invalid authorization');
    return res.status(401).json({ error: 'Invalid webhook authorization' });
  }

  const event = req.body;

  if (!event || !event.event) {
    return res.status(400).json({ error: 'Invalid webhook payload' });
  }

  const { type } = event.event;
  const appUserId = event.event.app_user_id;

  console.log(`💳 RevenueCat webhook: ${type} for user ${appUserId?.substring(0, 8)}...`);

  // Handle subscription expiry — clean up user data
  if (['EXPIRATION', 'CANCELLATION'].includes(type) && appUserId) {
    // Invalidate entitlement cache so next request re-checks
    entitlementCache.delete(appUserId);

    // Clean up FCM tokens
    if (userTokens.has(appUserId)) {
      const tokenCount = userTokens.get(appUserId).size;
      userTokens.delete(appUserId);
      console.log(`  🗑️  Removed ${tokenCount} FCM token(s) for expired user`);
    }

    // Invalidate pairing tokens for this user
    for (const [token, data] of pairingTokens) {
      if (data.rc_user_id === appUserId) {
        pairingTokens.delete(token);
        console.log(`  🗑️  Revoked pairing token for server ${data.server_id.substring(0, 8)}...`);
      }
    }

    console.log(`  ✅ Cleaned up data for user ${appUserId.substring(0, 8)}... (subscription ${type.toLowerCase()})`);
  }

  // Handle renewal — refresh cache
  if (['RENEWAL', 'INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE'].includes(type) && appUserId) {
    // Clear cache so next request fetches fresh entitlement status
    entitlementCache.delete(appUserId);
    console.log(`  ✅ Cache cleared for user ${appUserId.substring(0, 8)}... (${type.toLowerCase()})`);
  }

  res.json({ success: true });
});

// --- Start Server ---
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log('');
  console.log('=== Docker Manager Backend ===');
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📡 Health check: http://localhost:${PORT}/health`);
  console.log(`🔒 RC entitlement verification: ${RC_SECRET_KEY ? 'ENABLED' : 'DISABLED'}`);
  console.log('');
});

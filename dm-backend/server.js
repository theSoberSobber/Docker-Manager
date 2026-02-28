require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const admin = require('firebase-admin');

const app = express();
app.use(cors());
app.use(express.json());

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

// --- API Routes ---

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', firebase: firebaseInitialized });
});

// POST /api/register-token
// Register an FCM token for a RevenueCat user
app.post('/api/register-token', (req, res) => {
  const { fcm_token, rc_user_id } = req.body;

  if (!fcm_token || !rc_user_id) {
    return res.status(400).json({ error: 'fcm_token and rc_user_id are required' });
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
app.post('/api/pairing/generate', (req, res) => {
  const { rc_user_id, server_id } = req.body;

  if (!rc_user_id || !server_id) {
    return res.status(400).json({ error: 'rc_user_id and server_id are required' });
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

// POST /api/pairing/register
// Called by dm-notifier when it starts up
app.post('/api/pairing/register', (req, res) => {
  const { token, server_id } = req.body;

  if (!token) {
    return res.status(400).json({ error: 'token is required' });
  }

  const pairingData = pairingTokens.get(token);
  if (!pairingData) {
    return res.status(404).json({ error: 'Invalid or expired pairing token' });
  }

  // Register the server
  registeredServers.set(server_id || pairingData.server_id, {
    rc_user_id: pairingData.rc_user_id,
    status: 'paired',
    last_seen: Date.now(),
    pairing_token: token,
  });

  console.log(`✅ Server ${(server_id || pairingData.server_id).substring(0, 8)}... registered`);
  res.json({ success: true });
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
  const event = req.body;

  if (!event || !event.event) {
    return res.status(400).json({ error: 'Invalid webhook payload' });
  }

  const { type } = event.event;
  const appUserId = event.event.app_user_id;

  console.log(`💳 RevenueCat webhook: ${type} for user ${appUserId?.substring(0, 8)}...`);

  // Handle subscription expiry — clean up tokens
  if (['EXPIRATION', 'CANCELLATION'].includes(type)) {
    // Optionally remove FCM tokens and server registrations
    // for now just log it — the app will also check entitlements
    console.log(`  ℹ️  User ${appUserId?.substring(0, 8)}... subscription ${type.toLowerCase()}`);
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
  console.log('');
});

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const admin = require('firebase-admin');
const { Pool } = require('pg');

const app = express();
app.use(cors());
app.use(express.json());

// --- Configuration ---
const RC_SECRET_KEY = process.env.REVENUECAT_SECRET_KEY || '';
const RC_ENTITLEMENT_ID = 'Docker Manager Pro';
const RC_API_BASE = 'https://api.revenuecat.com/v1';

const ENTITLEMENT_CACHE_TTL_SHORT = 5 * 60 * 1000;       // 5 min — /register-token, /pairing/generate
const ENTITLEMENT_CACHE_TTL_LONG = 24 * 60 * 60 * 1000;  // 24h — /events

if (!RC_SECRET_KEY) {
  console.warn('⚠️  REVENUECAT_SECRET_KEY not set — entitlement verification DISABLED');
}

// --- Firebase Admin Init ---
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
}

// --- Postgres ---
const pool = new Pool({
  host: process.env.PGHOST || 'localhost',
  port: parseInt(process.env.PGPORT || '5432'),
  user: process.env.PGUSER || 'dm_backend',
  password: process.env.PGPASSWORD || 'dm_backend',
  database: process.env.PGDATABASE || 'dm_backend',
  max: 10,
});

async function initDB() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS user_tokens (
        rc_user_id TEXT NOT NULL,
        fcm_token TEXT NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        PRIMARY KEY (rc_user_id, fcm_token)
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS pairing_tokens (
        token TEXT PRIMARY KEY,
        rc_user_id TEXT NOT NULL,
        server_id TEXT NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS registered_servers (
        server_id TEXT PRIMARY KEY,
        rc_user_id TEXT NOT NULL,
        last_seen TIMESTAMPTZ DEFAULT NOW()
      );
    `);

    console.log('✅ Postgres tables initialized');
  } finally {
    client.release();
  }
}

// --- In-Memory Caches (OK to lose on restart) ---

// Map: rc_user_id -> { isPro, checked_at }
const entitlementCache = new Map();

// Set: rc_user_id — users who've been sent the "expired" push
const notifiedExpired = new Set();

// --- RevenueCat Entitlement Verification ---

async function verifyProEntitlement(rcUserId, cacheTtl = ENTITLEMENT_CACHE_TTL_SHORT) {
  if (!RC_SECRET_KEY) return true;

  const cached = entitlementCache.get(rcUserId);
  if (cached && (Date.now() - cached.checked_at < cacheTtl)) {
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
      if (cached) return cached.isPro;
      return false;
    }

    const data = await response.json();
    const entitlements = data?.subscriber?.entitlements || {};
    const proEntitlement = entitlements[RC_ENTITLEMENT_ID];

    const isPro = proEntitlement != null &&
      new Date(proEntitlement.expires_date) > new Date();

    entitlementCache.set(rcUserId, { isPro, checked_at: Date.now() });
    return isPro;
  } catch (e) {
    console.error(`  ❌ RC verification failed: ${e.message}`);
    if (cached) return cached.isPro;
    return false;
  }
}

async function requireProEntitlement(req, res, next) {
  const { rc_user_id } = req.body;
  if (!rc_user_id) {
    return res.status(400).json({ error: 'rc_user_id is required' });
  }

  const isPro = await verifyProEntitlement(rc_user_id, ENTITLEMENT_CACHE_TTL_SHORT);
  if (!isPro) {
    console.log(`🚫 Denied: user ${rc_user_id.substring(0, 8)}... — no Pro entitlement`);
    return res.status(403).json({ error: 'Active Pro subscription required' });
  }

  next();
}

// --- API Routes ---

app.get('/health', async (req, res) => {
  let dbOk = false;
  try {
    await pool.query('SELECT 1');
    dbOk = true;
  } catch (e) { /* ignore */ }

  res.json({
    status: 'ok',
    firebase: firebaseInitialized,
    rc_verification: !!RC_SECRET_KEY,
    database: dbOk,
  });
});

// POST /api/register-token
// Protected: requires active Pro entitlement
app.post('/api/register-token', requireProEntitlement, async (req, res) => {
  const { fcm_token, rc_user_id } = req.body;

  if (!fcm_token) {
    return res.status(400).json({ error: 'fcm_token is required' });
  }

  await pool.query(
    `INSERT INTO user_tokens (rc_user_id, fcm_token) VALUES ($1, $2)
     ON CONFLICT (rc_user_id, fcm_token) DO NOTHING`,
    [rc_user_id, fcm_token]
  );

  const { rows } = await pool.query(
    'SELECT COUNT(*) as cnt FROM user_tokens WHERE rc_user_id = $1',
    [rc_user_id]
  );

  console.log(`📱 Token registered for user ${rc_user_id.substring(0, 8)}... (${rows[0].cnt} total)`);
  res.json({ success: true });
});

// POST /api/pairing/generate
// Protected: requires active Pro entitlement
app.post('/api/pairing/generate', requireProEntitlement, async (req, res) => {
  const { rc_user_id, server_id } = req.body;

  if (!server_id) {
    return res.status(400).json({ error: 'server_id is required' });
  }

  const token = crypto.randomBytes(32).toString('hex');

  await pool.query(
    `INSERT INTO pairing_tokens (token, rc_user_id, server_id) VALUES ($1, $2, $3)`,
    [token, rc_user_id, server_id]
  );

  // Register/update server
  await pool.query(
    `INSERT INTO registered_servers (server_id, rc_user_id) VALUES ($1, $2)
     ON CONFLICT (server_id) DO UPDATE SET rc_user_id = $2, last_seen = NOW()`,
    [server_id, rc_user_id]
  );

  // Clean up expired tokens (older than 1 hour)
  await pool.query(
    `DELETE FROM pairing_tokens WHERE created_at < NOW() - INTERVAL '1 hour'`
  );

  console.log(`🔑 Pairing token generated for server ${server_id.substring(0, 8)}...`);
  res.json({ token });
});

// GET /api/pairing/status/:serverId
app.get('/api/pairing/status/:serverId', async (req, res) => {
  const { serverId } = req.params;

  const { rows } = await pool.query(
    'SELECT last_seen FROM registered_servers WHERE server_id = $1',
    [serverId]
  );

  if (rows.length === 0) {
    return res.json({ status: 'not_paired' });
  }

  const lastSeen = new Date(rows[0].last_seen).getTime();
  const isStale = Date.now() - lastSeen > 300000;

  res.json({
    status: isStale ? 'stale' : 'paired',
    last_seen: rows[0].last_seen,
  });
});

// POST /api/events
// Auth: Bearer pairing token + cached RC entitlement re-check (24h)
app.post('/api/events', async (req, res) => {
  // --- Step 1: Verify pairing token ---
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing authorization' });
  }

  const token = authHeader.substring(7);

  const { rows: tokenRows } = await pool.query(
    'SELECT rc_user_id, server_id FROM pairing_tokens WHERE token = $1',
    [token]
  );

  if (tokenRows.length === 0) {
    return res.status(401).json({ error: 'Invalid token' });
  }

  const { rc_user_id: rcUserId, server_id: tokenServerId } = tokenRows[0];

  // --- Step 2: Cached entitlement re-check (24h TTL) ---
  const isPro = await verifyProEntitlement(rcUserId, ENTITLEMENT_CACHE_TTL_LONG);

  if (!isPro) {
    if (!notifiedExpired.has(rcUserId)) {
      notifiedExpired.add(rcUserId);
      console.log(`💳 Subscription expired for user ${rcUserId.substring(0, 8)}... — sending expiry notification`);

      // Send expiry notification
      const { rows: fcmRows } = await pool.query(
        'SELECT fcm_token FROM user_tokens WHERE rc_user_id = $1',
        [rcUserId]
      );

      if (fcmRows.length > 0 && firebaseInitialized) {
        for (const { fcm_token } of fcmRows) {
          try {
            await admin.messaging().send({
              token: fcm_token,
              notification: {
                title: '⚠️ Pro Subscription Expired',
                body: 'Docker notifications have been paused. To stop dm-notifier, run: docker stop dm-notifier-... on your server.',
              },
              data: { type: 'subscription_expired', action: 'subscription_expired' },
              android: {
                priority: 'high',
                notification: { channelId: 'docker_events', priority: 'high' },
              },
            });
          } catch (e) { /* ignore */ }
        }
      }
    }

    return res.status(403).json({ error: 'Pro subscription expired' });
  }

  // User is Pro — auto-recover if previously expired
  if (notifiedExpired.has(rcUserId)) {
    notifiedExpired.delete(rcUserId);
    console.log(`✅ User ${rcUserId.substring(0, 8)}... re-subscribed — notifications resumed`);
  }

  // --- Step 3: Process the event ---
  const { server_id, event_type, action, container_name, image, timestamp,
    current_version, latest_version, changelog_url } = req.body;
  const effectiveServerId = server_id || tokenServerId;

  // Update last_seen
  await pool.query(
    `UPDATE registered_servers SET last_seen = NOW() WHERE server_id = $1`,
    [effectiveServerId]
  );

  let title, body;
  let customCommand;

  if (event_type === 'system') {
    // --- System events: extensible notification map ---
    const systemNotifs = {
      update_available: {
        title: '🆕 dm-notifier Update Available',
        body: `Version ${latest_version || 'new'} is available${current_version ? ` (current: ${current_version})` : ''}. Tap to update.`,
      },
    };

    if (action === 'prompt_command') {
      // Generic arbitrary command prompt from dm-notifier
      title = req.body.title || '⚙️ Action Required';
      body = req.body.body || 'Tap to review and execute this command.';
      customCommand = req.body.command || '';
    } else {
      const notif = systemNotifs[action] || {
        title: `🔔 System: ${action}`,
        body: '',
      };
      title = notif.title;
      body = notif.body;
    }

    console.log(`🔔 System event: ${action} (server: ${effectiveServerId.substring(0, 8)}...)`);
  } else {
    // --- Container events: existing logic ---
    const actionEmoji = {
      start: '▶️', stop: '⏹️', die: '💀', restart: '🔄',
      oom: '⚠️', kill: '🔴', pause: '⏸️', unpause: '▶️',
    };

    const emoji = actionEmoji[action] || '🐳';
    title = `${emoji} ${container_name || 'Container'}`;
    body = `${action.charAt(0).toUpperCase() + action.slice(1)}${image ? ` (${image})` : ''}`;
    console.log(`🐳 Event: ${container_name} — ${action} (server: ${effectiveServerId.substring(0, 8)}...)`);
  }

  // Get FCM tokens from DB
  const { rows: fcmRows } = await pool.query(
    'SELECT fcm_token FROM user_tokens WHERE rc_user_id = $1',
    [rcUserId]
  );

  if (fcmRows.length === 0) {
    console.log(`  ⚠️  No FCM tokens for user ${rcUserId.substring(0, 8)}...`);
    return res.json({ success: true, notifications_sent: 0 });
  }

  if (!firebaseInitialized) {
    console.log('  ⚠️  Firebase not initialized — skipping FCM');
    return res.json({ success: true, notifications_sent: 0 });
  }

  let successCount = 0;
  const invalidTokens = [];

  for (const { fcm_token } of fcmRows) {
    try {
      await admin.messaging().send({
        token: fcm_token,
        notification: { title, body },
        data: {
          server_id: effectiveServerId,
          event_type: event_type || 'container',
          action: action || '',
          container_name: container_name || '',
          image: image || '',
          timestamp: String(timestamp || Date.now()),
          ...(changelog_url && { changelog_url }),
          ...(current_version && { current_version }),
          ...(latest_version && { latest_version }),
          ...(customCommand && { command: customCommand }),
          ...(action === 'prompt_command' && { title: title, body: body }),
        },
        android: {
          priority: 'high',
          notification: { channelId: 'docker_events', priority: 'high' },
        },
      });
      successCount++;
    } catch (e) {
      if (
        e.code === 'messaging/registration-token-not-registered' ||
        e.code === 'messaging/invalid-registration-token'
      ) {
        invalidTokens.push(fcm_token);
      } else {
        console.error(`  ❌ FCM send error: ${e.message}`);
      }
    }
  }

  // Clean up invalid FCM tokens from DB
  for (const invalid of invalidTokens) {
    await pool.query('DELETE FROM user_tokens WHERE fcm_token = $1', [invalid]);
    console.log(`  🗑️  Removed invalid FCM token`);
  }

  console.log(`  📤 Sent ${successCount}/${fcmRows.length} notifications`);
  res.json({ success: true, notifications_sent: successCount });
});

// POST /api/webhook/revenuecat (optional)
app.post('/api/webhook/revenuecat', (req, res) => {
  const authHeader = req.headers.authorization;
  const expectedAuth = process.env.REVENUECAT_WEBHOOK_AUTH;
  if (expectedAuth && authHeader !== `Bearer ${expectedAuth}`) {
    return res.status(401).json({ error: 'Invalid webhook authorization' });
  }

  const event = req.body;
  if (!event || !event.event) {
    return res.status(400).json({ error: 'Invalid webhook payload' });
  }

  const { type } = event.event;
  const appUserId = event.event.app_user_id;

  console.log(`💳 RevenueCat webhook: ${type} for user ${appUserId?.substring(0, 8)}...`);

  if (['EXPIRATION', 'CANCELLATION'].includes(type) && appUserId) {
    entitlementCache.delete(appUserId);
    console.log(`  🗑️  Cache invalidated for user ${appUserId.substring(0, 8)}...`);
  }

  if (['RENEWAL', 'INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE'].includes(type) && appUserId) {
    entitlementCache.delete(appUserId);
    notifiedExpired.delete(appUserId);
    console.log(`  ✅ Cache cleared for user ${appUserId.substring(0, 8)}... (${type.toLowerCase()})`);
  }

  res.json({ success: true });
});

// --- Start Server ---
const PORT = process.env.PORT || 3000;

async function start() {
  try {
    await initDB();
  } catch (e) {
    console.error('❌ Failed to connect to Postgres:', e.message);
    console.error('   Make sure Postgres is running and connection details are correct');
    process.exit(1);
  }

  app.listen(PORT, () => {
    console.log('');
    console.log('=== Docker Manager Backend ===');
    console.log(`🚀 Server running on port ${PORT}`);
    console.log(`📡 Health check: http://localhost:${PORT}/health`);
    console.log(`🔒 RC verification: ${RC_SECRET_KEY ? 'ENABLED' : 'DISABLED'}`);
    console.log('');
  });
}

start();

# dm-backend

Backend for Docker Manager Pro — receives Docker events from dm-notifier containers and forwards them as FCM push notifications to users' devices.

## Quick Start

```bash
cd dm-backend
npm install
# Place your Firebase service account key as firebase-service-account.json
node server.js
```

## API Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/health` | GET | Health check |
| `/api/register-token` | POST | Register FCM token for a user |
| `/api/pairing/generate` | POST | Generate pairing token for a server |
| `/api/pairing/register` | POST | Called by dm-notifier on startup |
| `/api/pairing/status/:serverId` | GET | Check notifier status for a server |
| `/api/events` | POST | Receive Docker events, send FCM pushes |
| `/api/webhook/revenuecat` | POST | RevenueCat subscription webhooks |

## Docker

```bash
docker build -t dm-backend .
docker run -d -p 3000:3000 \
  -v ./firebase-service-account.json:/app/firebase-service-account.json:ro \
  dm-backend
```

## Configuration

| Env Var | Default | Description |
|---|---|---|
| `PORT` | `3000` | Server port |
| `FIREBASE_SERVICE_ACCOUNT` | — | Firebase service account JSON string (alternative to file) |

## Storage

Currently uses **in-memory storage**. For production, replace the `Map` objects in `server.js` with Redis, PostgreSQL, or similar. The code is structured to make this swap straightforward.

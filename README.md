# 🎵 SyncBeat — Real-Time Synchronized Music Listening App

Listen to YouTube videos **together**, in **perfect sync**, from anywhere in the world.

> Multiple users join a room → Host loads a YouTube video → Everyone hears it at the same moment.

---

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [How Synchronization Works](#how-synchronization-works)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Setup Instructions](#setup-instructions)
  - [Backend Setup](#backend-setup)
  - [Flutter Setup](#flutter-setup)
- [How to Run Locally](#how-to-run-locally)
- [Configuration](#configuration)
- [API Reference](#websocket-api-reference)
- [Project Structure](#project-structure)
- [Future Improvements](#future-improvements)

---

## Project Overview

SyncBeat is a mobile app that lets groups of people listen to YouTube audio together in real-time sync. Unlike services that stream audio, SyncBeat uses **event-based synchronization**: the host controls playback (play, pause, seek, load), the server broadcasts timestamped events, and every client adjusts their local YouTube player to stay in sync.

No audio is streamed — YouTube's own player runs inside each device. The server only passes control signals.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENTS (Flutter App)                     │
│                                                                   │
│  ┌─────────────────┐   ┌─────────────────┐   ┌──────────────┐  │
│  │   Home Screen    │   │   Room Screen    │   │ Chat Panel   │  │
│  │  (Create/Join)   │   │  (Player+Chat)   │   │ (Messages)   │  │
│  └────────┬────────┘   └────────┬────────┘   └──────┬───────┘  │
│           │                     │                    │           │
│           └──────────┬──────────┘────────────────────┘          │
│                      │                                            │
│              ┌───────▼──────────┐                                │
│              │   RoomProvider   │  ← State management (Provider) │
│              │  (ChangeNotifier)│                                 │
│              └───────┬──────────┘                                │
│                      │                                            │
│              ┌───────▼──────────┐   ┌──────────────────────┐    │
│              │  SocketService   │   │ YouTubePlayerController│   │
│              │ (WebSocket + sync│   │  (youtube_player_flutter│  │
│              │  clock offset)   │   │  - iframe/webview)    │    │
│              └───────┬──────────┘   └──────────────────────┘    │
└──────────────────────┼─────────────────────────────────────────-─┘
                       │  WebSocket (ws:// or wss://)
                       │
┌──────────────────────▼────────────────────────────────────────┐
│                    NODE.JS BACKEND (server.js)                  │
│                                                                  │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────────┐  │
│   │ Express HTTP  │   │  WebSocket   │   │   TimeManager    │  │
│   │ /health       │   │  Server(ws)  │   │  (serverTime)    │  │
│   │ /rooms/:id    │   │              │   │  (PING/PONG)     │  │
│   └──────────────┘   └──────┬───────┘   └──────────────────┘  │
│                              │                                   │
│                    ┌─────────▼──────────┐                       │
│                    │   MessageHandler    │                       │
│                    │ (routes all events) │                       │
│                    └─────────┬──────────┘                       │
│                              │                                   │
│                    ┌─────────▼──────────┐                       │
│                    │    RoomManager      │                       │
│                    │  (rooms Map,        │                       │
│                    │   members, hosts,   │                       │
│                    │   playback state)   │                       │
│                    └────────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow for a PLAY event:

```
Host presses Play
       │
       ▼
Flutter: sendPlay(currentPosition)
       │
       ▼  WebSocket: { type: "PLAY", position: 42.3 }
       │
       ▼
Server: MessageHandler._handlePlay()
  → roomManager.updatePlayback(...)   sets updatedAt = Date.now()
  → broadcastToRoom: { type: "SYNC_PLAY", position: 42.3, serverTime: 1712345678901 }
       │
       ├──→ Client A receives event:
       │      networkDelay = (clientNow - serverTime) / 1000   // e.g. 0.08s
       │      adjustedPosition = 42.3 + 0.08 = 42.38s
       │      player.seekTo(42.38s) + player.play()
       │
       └──→ Client B receives event (slightly later, higher latency):
              networkDelay = (clientNow - serverTime) / 1000   // e.g. 0.12s
              adjustedPosition = 42.3 + 0.12 = 42.42s
              player.seekTo(42.42s) + player.play()

Result: Both clients start playing from slightly different but network-adjusted
        positions → effectively synchronized within ~50-200ms of each other.
```

---

## How Synchronization Works

### The Core Problem
When a host presses "Play", it takes some milliseconds for that event to reach other clients over the internet. Without correction, a client with 200ms latency would start the video 0.2 seconds behind the host.

### The Solution: Timestamp-Based Adjustment

**Step 1 — Clock Synchronization (PING/PONG)**

On connect and every 10 seconds, the client sends:
```json
{ "type": "PING", "clientTime": 1712345678500 }
```
The server responds immediately:
```json
{ "type": "PONG", "clientTime": 1712345678500, "serverTime": 1712345678550 }
```
The client computes:
```
rtt = now - clientTime  = 100ms
clockOffset = serverTime + rtt/2 - now = serverTime + 50 - now
```
Now the client knows how to convert its local clock to server time.

**Step 2 — Event Broadcasting with Server Timestamp**

When the server processes a PLAY command, it stamps the event with its own clock:
```json
{
  "type": "SYNC_PLAY",
  "position": 42.3,
  "serverTime": 1712345678901
}
```

**Step 3 — Client Adjustment**

When a client receives the event, it computes:
```
networkDelay = (adjustedLocalNow - serverTime) / 1000.0  seconds
adjustedPosition = 42.3 + networkDelay
```
The client seeks to `adjustedPosition` before playing — effectively compensating for the transit time.

**Step 4 — Drift Correction**

Every 5 seconds while playing, the client checks:
```
expectedNow = savedPosition + elapsed seconds since play
actualPlayer = player.currentPosition

if |actualPlayer - expectedNow| > syncTolerance (0.5s):
    silently seek to expectedNow
```
This catches gradual drift without jarring the user.

### Sync Tolerance
A threshold of **0.5 seconds** (configurable via `AppConfig.syncToleranceSeconds`) prevents unnecessary micro-seeks. If drift is within tolerance, no correction is applied.

---

## Features

| Feature | Status |
|---------|--------|
| Create / Join room with 6-char ID | ✅ |
| Room creator becomes host/admin | ✅ |
| Multiple hosts per room | ✅ |
| Admin can add/remove hosts | ✅ |
| Real-time play/pause/seek sync | ✅ |
| Timestamp-based sync with delay correction | ✅ |
| Drift correction every 5 seconds | ✅ |
| YouTube video embed (WebView) | ✅ |
| Video search (requires API key) | ✅ |
| Direct video ID / URL loading | ✅ |
| Real-time chat | ✅ |
| Member list with online/offline status | ✅ |
| Host/Admin badges in UI | ✅ |
| WebSocket reconnect with backoff | ✅ |
| Request sync on reconnect | ✅ |
| Reconnect banner in UI | ✅ |
| Server-side heartbeat (30s ping) | ✅ |
| Late-joiner sync (receives current state) | ✅ |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile Frontend | Flutter 3.x |
| State Management | Provider (ChangeNotifier) |
| YouTube Player | youtube_player_flutter |
| WebSocket Client | web_socket_channel |
| Persistence | shared_preferences |
| Backend | Node.js |
| Real-time Transport | ws (WebSocket) |
| HTTP Server | Express |
| ID Generation | uuid |

---

## Setup Instructions

### Prerequisites

- Node.js >= 18.x
- Flutter SDK >= 3.1.0
- Android Studio or Xcode (for device/emulator)
- A device or emulator to run the Flutter app

### Backend Setup

```bash
# 1. Navigate to backend directory
cd syncbeat/backend

# 2. Install dependencies
npm install

# 3. Copy environment file
cp .env.example .env

# 4. Start the server
npm start
# OR for development with auto-reload:
npm run dev
```

The server starts on **port 3000** by default.

You should see:
```
🎵 SyncBeat Backend running on port 3000
   HTTP: http://localhost:3000
   WS:   ws://localhost:3000
   Health: http://localhost:3000/health
```

To verify: open `http://localhost:3000/health` in a browser. You should see:
```json
{ "status": "ok", "serverTime": 1712345678901, "activeRooms": 0 }
```

### Flutter Setup

```bash
# 1. Navigate to Flutter app directory
cd syncbeat/flutter_app

# 2. Install dependencies
flutter pub get

# 3. Update the backend URL in lib/utils/app_config.dart:
#    - Android Emulator: ws://10.0.2.2:3000
#    - Physical device (same WiFi): ws://YOUR_COMPUTER_IP:3000
#    - Production: wss://your-server.com

# 4. Run the app
flutter run
```

---

## How to Run Locally

### Scenario A: Android Emulator + Local Backend

```bash
# Terminal 1: Start backend
cd backend && npm start

# Terminal 2: Run Flutter on emulator
cd flutter_app
# In lib/utils/app_config.dart, set:
#   backendWsUrl = 'ws://10.0.2.2:3000'
flutter run
```

### Scenario B: Physical Android Devices

```bash
# Terminal 1: Find your computer's local IP
# macOS: ifconfig | grep "inet " | grep -v 127
# Windows: ipconfig | findstr IPv4
# Linux: ip addr show | grep inet

# Terminal 2: Start backend (binds to all interfaces by default)
cd backend && npm start

# In lib/utils/app_config.dart, set:
#   backendWsUrl = 'ws://192.168.1.X:3000'  ← your computer's IP

# Run on device
flutter run
```

### Scenario C: Testing Sync (Multiple Devices)

1. Start backend on your computer
2. Build and install the Flutter app on 2+ devices (both on same WiFi)
3. Device A: Create Room → note the 6-char Room ID
4. Device B: Join Room → enter the Room ID and your name
5. Device A (host): Tap "Change Video" → enter a YouTube video ID
6. Device A: Press Play — Device B should start playing in sync

---

## Configuration

All configuration is in `flutter_app/lib/utils/app_config.dart`:

```dart
class AppConfig {
  // WebSocket server URL
  static const String backendWsUrl = 'ws://10.0.2.2:3000';

  // HTTP server URL (for room existence check)
  static const String backendHttpUrl = 'http://10.0.2.2:3000';

  // YouTube Data API v3 key (optional — enables video search)
  // Get at: https://console.developers.google.com
  // Enable: YouTube Data API v3
  static const String youtubeApiKey = '';

  // Reconnection
  static const int wsReconnectDelayMs = 2000;
  static const int wsMaxReconnectAttempts = 10;

  // Sync tolerance (seconds) — no seek if within this range
  static const double syncToleranceSeconds = 0.5;

  // How often to auto-request sync state
  static const int periodicSyncIntervalSeconds = 30;
}
```

### YouTube API Key (for Search)

1. Go to [Google Cloud Console](https://console.developers.google.com)
2. Create a project → Enable **YouTube Data API v3**
3. Create credentials → API Key
4. Paste in `AppConfig.youtubeApiKey`

Without a key, the search tab shows a notice, but direct video ID / URL loading still works.

---

## WebSocket API Reference

All messages are JSON. Client → Server:

| Type | Payload | Description |
|------|---------|-------------|
| `PING` | `{ clientTime }` | Clock sync |
| `CREATE_ROOM` | `{ displayName }` | Create a new room |
| `JOIN_ROOM` | `{ roomId, displayName }` | Join existing room |
| `PLAY` | `{ position }` | Host: play at position (seconds) |
| `PAUSE` | `{ position }` | Host: pause at position |
| `SEEK` | `{ position }` | Host: seek to position |
| `LOAD_VIDEO` | `{ videoId, videoTitle, videoThumbnail }` | Host: load new video |
| `CHAT_MESSAGE` | `{ text }` | Send chat message |
| `ADD_HOST` | `{ targetUserId }` | Admin: promote to host |
| `REMOVE_HOST` | `{ targetUserId }` | Admin: demote host |
| `REQUEST_SYNC` | `{}` | Request current playback state |

Server → Client:

| Type | Payload | Description |
|------|---------|-------------|
| `CONNECTED` | `{ userId, serverTime }` | Assigned userId |
| `PONG` | `{ clientTime, serverTime }` | Clock sync response |
| `ROOM_CREATED` | `{ room, serverTime }` | Room created |
| `ROOM_JOINED` | `{ room, serverTime }` | Joined + full state |
| `ROOM_ERROR` | `{ message }` | Join/create error |
| `MEMBER_JOINED` | `{ member, serverTime }` | Someone joined |
| `MEMBER_LEFT` | `{ userId, userName, serverTime }` | Someone disconnected |
| `SYNC_PLAY` | `{ position, serverTime }` | Play at position |
| `SYNC_PAUSE` | `{ position, serverTime }` | Pause at position |
| `SYNC_SEEK` | `{ position, isPlaying, serverTime }` | Seek to position |
| `SYNC_LOAD` | `{ videoId, videoTitle, ... serverTime }` | New video loaded |
| `SYNC_STATE` | `{ playback, serverTime }` | Full playback state |
| `CHAT_MESSAGE` | `{ message }` | Chat message |
| `HOST_ADDED` | `{ hostId, serverTime }` | Host promoted |
| `HOST_REMOVED` | `{ hostId, serverTime }` | Host demoted |

---

## Project Structure

```
syncbeat/
├── backend/
│   ├── server.js              ← Entry point, HTTP + WebSocket server
│   ├── package.json
│   ├── .env.example
│   └── src/
│       ├── roomManager.js     ← Rooms, members, hosts, playback state
│       ├── messageHandler.js  ← Routes WS messages, broadcasts events
│       └── timeManager.js     ← Server clock, PING/PONG sync
│
└── flutter_app/
    ├── pubspec.yaml
    ├── android/
    │   └── app/src/main/AndroidManifest.xml
    ├── ios/
    │   └── Runner/Info.plist
    └── lib/
        ├── main.dart                      ← App entry point
        ├── models/
        │   ├── room_model.dart            ← Room state
        │   ├── user_model.dart            ← Member info
        │   ├── message_model.dart         ← Chat message
        │   └── playback_state_model.dart  ← Player state
        ├── providers/
        │   └── room_provider.dart         ← Core state + sync logic ★
        ├── screens/
        │   ├── home_screen.dart           ← Create/Join UI
        │   └── room_screen.dart           ← Main room screen
        ├── services/
        │   ├── socket_service.dart        ← WS connection + clock sync
        │   └── youtube_service.dart       ← YouTube Data API search
        ├── utils/
        │   ├── app_config.dart            ← All configuration
        │   └── app_theme.dart             ← Dark theme tokens
        └── widgets/
            ├── player_widget.dart         ← YouTube player + drift correction ★
            ├── chat_panel.dart            ← Chat messages + input
            ├── members_panel.dart         ← Member list + host management
            └── video_search_sheet.dart    ← Search/load video
```

★ = contains critical sync logic

---

## Future Improvements

### Sync Quality
- [ ] **WebRTC data channels** for lower-latency event delivery
- [ ] **NTP-style multi-sample clock sync** for better clock offset estimation
- [ ] **Adaptive sync tolerance** based on measured network jitter
- [ ] **Buffering-aware sync** — pause sync correction when a client is buffering

### Features
- [ ] **Queue system** — add videos to a playlist
- [ ] **Reactions** — emoji reactions synced in real-time
- [ ] **Video voting** — members can suggest/vote on next video
- [ ] **History** — recently played videos in the room
- [ ] **Google login** — for personalized experience and ad-free YouTube Premium

### Infrastructure
- [ ] **Redis** for room state persistence (survive server restarts)
- [ ] **Horizontal scaling** with Redis pub/sub for multi-server deployments
- [ ] **Rate limiting** on WebSocket messages
- [ ] **Room persistence** — rooms survive server restarts
- [ ] **TURN/STUN servers** for better WebRTC support behind NATs

### Mobile UX
- [ ] **Background audio** — keep playing when app is backgrounded
- [ ] **Share room link** — deep link that opens the app directly into a room
- [ ] **Notification** when host changes video
- [ ] **Landscape player** mode

### Production
- [ ] **WSS (TLS)** — use `wss://` in production (remove `usesCleartextTraffic`)
- [ ] **Dockerfile** for containerized backend deployment
- [ ] **CI/CD pipeline** for automated builds

---

## License

MIT — free to use and modify for personal or commercial projects.

---

## Troubleshooting

**"Room not found" when joining**
- Make sure the Room ID is exactly 6 uppercase characters
- The room may have been deleted (empty rooms are deleted after 30s)

**YouTube player shows a blank/black screen**
- Ensure `usesCleartextTraffic="true"` is set (Android) or `NSAllowsArbitraryLoads` (iOS) for local dev
- Some videos are restricted by YouTube and cannot be embedded

**Videos not in sync**
- Check server logs for any WebSocket errors
- Ensure both devices can reach the backend server
- Try pressing "Request Sync" (the app auto-requests sync on reconnect)

**WebSocket won't connect on physical device**
- Make sure both device and backend are on the same network
- Use your computer's LAN IP, not `10.0.2.2` (that's only for emulators)
- Check firewall isn't blocking port 3000

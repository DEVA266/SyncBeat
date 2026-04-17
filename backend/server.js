/**
 * SyncBeat Backend Server
 * =======================
 * Express HTTP server + WebSocket server for real-time room sync.
 *
 * Architecture:
 *   HTTP  :3000  — Health check, room existence check
 *   WS    :3000  — Real-time events (same port, upgraded connections)
 *
 * Each WebSocket client is assigned a unique userId (UUID) on connect.
 * All subsequent messages carry this userId implicitly (via the socket).
 */

const express = require('express');
const http = require('http');
const { WebSocketServer } = require('ws');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');

const messageHandler = require('./src/messageHandler');
const roomManager = require('./src/roomManager');
const timeManager = require('./src/timeManager');

// ─── Express Setup ────────────────────────────────────────────────────────────

const app = express();
app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    serverTime: timeManager.now(),
    activeRooms: roomManager.rooms.size,
  });
});

// Check if a room exists (useful before showing "Join" UI)
app.get('/rooms/:roomId', (req, res) => {
  const room = roomManager.getRoom(req.params.roomId.toUpperCase());
  if (!room) {
    return res.status(404).json({ error: 'Room not found' });
  }
  res.json({
    id: room.id,
    memberCount: [...room.members.values()].filter(m => m.isOnline).length,
    hasVideo: !!room.playback.videoId,
    videoTitle: room.playback.videoTitle,
  });
});

// ─── HTTP + WS Server ─────────────────────────────────────────────────────────

const server = http.createServer(app);
const wss = new WebSocketServer({ server });

wss.on('connection', (ws) => {
  // Assign a unique ID to this connection
  const userId = uuidv4();

  // Register with the message handler
  messageHandler.register(userId, ws);

  // Send the client their assigned userId immediately
  ws.send(JSON.stringify({
    type: 'CONNECTED',
    userId,
    serverTime: timeManager.now(),
  }));

  // Handle incoming messages
  ws.on('message', (data) => {
    messageHandler.handleMessage(userId, data.toString());
  });

  // Handle disconnection
  ws.on('close', () => {
    messageHandler.handleDisconnect(userId);
  });

  // Handle errors (log but don't crash)
  ws.on('error', (err) => {
    console.error(`[WS Error] userId=${userId}:`, err.message);
  });
});

// ─── Periodic Heartbeat ───────────────────────────────────────────────────────
// Send pings every 25s to keep mobile connections alive through NAT/firewalls

setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.readyState === ws.OPEN) {
      ws.ping();
    }
  });
}, 25000);

// ─── Start ────────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`\n🎵 SyncBeat Backend running on port ${PORT}`);
  console.log(`   HTTP: http://localhost:${PORT}`);
  console.log(`   WS:   ws://localhost:${PORT}`);
  console.log(`   Health: http://localhost:${PORT}/health\n`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('[Server] SIGTERM received, shutting down...');
  server.close(() => process.exit(0));
});
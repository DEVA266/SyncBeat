/**
 * MessageHandler
 * --------------
 * Processes incoming WebSocket messages and coordinates
 * broadcasting to room members.
 *
 * Message types handled (client → server):
 *   PING            - Clock sync
 *   CREATE_ROOM     - Create a new room
 *   JOIN_ROOM       - Join an existing room
 *   PLAY            - Host: play video
 *   PAUSE           - Host: pause video
 *   SEEK            - Host: seek to position
 *   LOAD_VIDEO      - Host: load a new video
 *   CHAT_MESSAGE    - Send a chat message
 *   ADD_HOST        - Admin: promote a member to host
 *   REMOVE_HOST     - Admin: demote a host
 *   REQUEST_SYNC    - Client: request current playback state
 *
 * Message types sent (server → client):
 *   PONG            - Clock sync response
 *   ROOM_CREATED    - Room creation confirmation
 *   ROOM_JOINED     - Join confirmation with full room state
 *   ROOM_ERROR      - Error joining/creating
 *   MEMBER_JOINED   - Broadcast when someone joins
 *   MEMBER_LEFT     - Broadcast when someone disconnects
 *   SYNC_PLAY       - Broadcast: play event with timestamp
 *   SYNC_PAUSE      - Broadcast: pause event with timestamp
 *   SYNC_SEEK       - Broadcast: seek event with timestamp
 *   SYNC_LOAD       - Broadcast: new video loaded
 *   SYNC_STATE      - Full playback state (for late joiners / resync)
 *   CHAT_MESSAGE    - Broadcast chat message
 *   HOST_ADDED      - Broadcast: user promoted to host
 *   HOST_REMOVED    - Broadcast: user demoted from host
 *   ERROR           - Generic error
 */

const roomManager = require('./roomManager');
const timeManager = require('./timeManager');

class MessageHandler {
  constructor() {
    // Map<userId, WebSocket> — tracks all connected sockets
    this.connections = new Map();
    // Map<userId, roomId> — tracks which room each user is in
    this.userRooms = new Map();
  }

  /**
   * Register a new WebSocket connection.
   */
  register(userId, ws) {
    this.connections.set(userId, ws);
    console.log(`[WS] Client connected: ${userId}`);
  }

  /**
   * Handle disconnect — notify room members.
   */
  handleDisconnect(userId) {
    console.log(`[WS] Client disconnected: ${userId}`);
    this.connections.delete(userId);

    const roomId = this.userRooms.get(userId);
    if (roomId) {
      const room = roomManager.getRoom(roomId);
      const member = room?.members.get(userId);

      roomManager.memberDisconnected(userId);
      this.userRooms.delete(userId);

      if (room && member) {
        this._broadcastToRoom(roomId, userId, {
          type: 'MEMBER_LEFT',
          userId,
          userName: member.name,
          serverTime: timeManager.now(),
        });
      }
    }
  }

  /**
   * Route an incoming message to the appropriate handler.
   */
  handleMessage(userId, rawMessage) {
    let msg;
    try {
      msg = JSON.parse(rawMessage);
    } catch {
      this._send(userId, { type: 'ERROR', message: 'Invalid JSON' });
      return;
    }

    const { type, ...payload } = msg;
    console.log(`[WS] Message from ${userId}: ${type}`);

    switch (type) {
      case 'PING':          return this._handlePing(userId, payload);
      case 'CREATE_ROOM':   return this._handleCreateRoom(userId, payload);
      case 'JOIN_ROOM':     return this._handleJoinRoom(userId, payload);
      case 'PLAY':          return this._handlePlay(userId, payload);
      case 'PAUSE':         return this._handlePause(userId, payload);
      case 'SEEK':          return this._handleSeek(userId, payload);
      case 'LOAD_VIDEO':    return this._handleLoadVideo(userId, payload);
      case 'CHAT_MESSAGE':  return this._handleChat(userId, payload);
      case 'ADD_HOST':      return this._handleAddHost(userId, payload);
      case 'REMOVE_HOST':   return this._handleRemoveHost(userId, payload);
      case 'REQUEST_SYNC':  return this._handleRequestSync(userId, payload);
      default:
        this._send(userId, { type: 'ERROR', message: `Unknown message type: ${type}` });
    }
  }

  // ─── Handlers ──────────────────────────────────────────────────────────────

  _handlePing(userId, { clientTime }) {
    this._send(userId, {
      type: 'PONG',
      ...timeManager.buildPingResponse(clientTime),
    });
  }

  _handleCreateRoom(userId, { displayName }) {
    if (!displayName) {
      return this._send(userId, { type: 'ROOM_ERROR', message: 'displayName required' });
    }
    const room = roomManager.createRoom(userId, displayName);
    this.userRooms.set(userId, room.id);
    this._send(userId, { type: 'ROOM_CREATED', room, serverTime: timeManager.now() });
  }

  _handleJoinRoom(userId, { roomId, displayName }) {
    if (!roomId || !displayName) {
      return this._send(userId, { type: 'ROOM_ERROR', message: 'roomId and displayName required' });
    }

    const room = roomManager.joinRoom(roomId.toUpperCase(), userId, displayName);
    if (!room) {
      return this._send(userId, { type: 'ROOM_ERROR', message: 'Room not found' });
    }

    this.userRooms.set(userId, room.id);

    // Send full room state to the joining user
    this._send(userId, {
      type: 'ROOM_JOINED',
      room,
      serverTime: timeManager.now(),
    });

    // Notify existing members
    this._broadcastToRoom(room.id, userId, {
      type: 'MEMBER_JOINED',
      member: { id: userId, name: displayName },
      serverTime: timeManager.now(),
    });
  }

  _handlePlay(userId, { position }) {
    const roomId = this.userRooms.get(userId);
    if (!roomId) return this._send(userId, { type: 'ERROR', message: 'Not in a room' });

    const playback = roomManager.updatePlayback(roomId, userId, {
      isPlaying: true,
      position: position ?? 0,
    });

    if (playback?.error) {
      return this._send(userId, { type: 'ERROR', message: playback.error });
    }

    // Broadcast PLAY to all members (including sender for confirmation)
    this._broadcastToRoom(roomId, null, {
      type: 'SYNC_PLAY',
      position: playback.position,
      serverTime: playback.updatedAt, // use the exact time state was set
    });
  }

  _handlePause(userId, { position }) {
    const roomId = this.userRooms.get(userId);
    if (!roomId) return this._send(userId, { type: 'ERROR', message: 'Not in a room' });

    const playback = roomManager.updatePlayback(roomId, userId, {
      isPlaying: false,
      position: position ?? 0,
    });

    if (playback?.error) {
      return this._send(userId, { type: 'ERROR', message: playback.error });
    }

    this._broadcastToRoom(roomId, null, {
      type: 'SYNC_PAUSE',
      position: playback.position,
      serverTime: playback.updatedAt,
    });
  }

  _handleSeek(userId, { position }) {
    const roomId = this.userRooms.get(userId);
    if (!roomId) return this._send(userId, { type: 'ERROR', message: 'Not in a room' });

    const playback = roomManager.updatePlayback(roomId, userId, {
      position: position ?? 0,
      // Keep isPlaying state unchanged
    });

    if (playback?.error) {
      return this._send(userId, { type: 'ERROR', message: playback.error });
    }

    this._broadcastToRoom(roomId, null, {
      type: 'SYNC_SEEK',
      position: playback.position,
      isPlaying: playback.isPlaying,
      serverTime: playback.updatedAt,
    });
  }

  _handleLoadVideo(userId, { videoId, videoTitle, videoThumbnail }) {
    const roomId = this.userRooms.get(userId);
    if (!roomId) return this._send(userId, { type: 'ERROR', message: 'Not in a room' });

    const playback = roomManager.updatePlayback(roomId, userId, {
      videoId,
      videoTitle,
      videoThumbnail,
      isPlaying: false,
      position: 0,
    });

    if (playback?.error) {
      return this._send(userId, { type: 'ERROR', message: playback.error });
    }

    this._broadcastToRoom(roomId, null, {
      type: 'SYNC_LOAD',
      videoId: playback.videoId,
      videoTitle: playback.videoTitle,
      videoThumbnail: playback.videoThumbnail,
      serverTime: playback.updatedAt,
    });
  }

  _handleChat(userId, { text }) {
    const roomId = this.userRooms.get(userId);
    if (!roomId) return this._send(userId, { type: 'ERROR', message: 'Not in a room' });
    if (!text || text.trim().length === 0) return;

    const message = roomManager.addMessage(roomId, userId, text.trim().substring(0, 500));
    if (!message) return;

    this._broadcastToRoom(roomId, null, {
      type: 'CHAT_MESSAGE',
      message,
    });
  }

  _handleAddHost(userId, { targetUserId }) {
    const roomId = this.userRooms.get(userId);
    if (!roomId) return this._send(userId, { type: 'ERROR', message: 'Not in a room' });

    const result = roomManager.addHost(roomId, userId, targetUserId);
    if (result.error) {
      return this._send(userId, { type: 'ERROR', message: result.error });
    }

    this._broadcastToRoom(roomId, null, {
      type: 'HOST_ADDED',
      hostId: targetUserId,
      serverTime: timeManager.now(),
    });
  }

  _handleRemoveHost(userId, { targetUserId }) {
    const roomId = this.userRooms.get(userId);
    if (!roomId) return this._send(userId, { type: 'ERROR', message: 'Not in a room' });

    const result = roomManager.removeHost(roomId, userId, targetUserId);
    if (result.error) {
      return this._send(userId, { type: 'ERROR', message: result.error });
    }

    this._broadcastToRoom(roomId, null, {
      type: 'HOST_REMOVED',
      hostId: targetUserId,
      serverTime: timeManager.now(),
    });
  }

  _handleRequestSync(userId, _payload) {
    const roomId = this.userRooms.get(userId);
    if (!roomId) return this._send(userId, { type: 'ERROR', message: 'Not in a room' });

    const room = roomManager.getRoom(roomId);
    if (!room) return;

    const now = timeManager.now();
    this._send(userId, {
      type: 'SYNC_STATE',
      playback: room.playback,
      serverTime: now,
    });
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /**
   * Send a JSON message to a specific user.
   */
  _send(userId, data) {
    const ws = this.connections.get(userId);
    if (ws && ws.readyState === 1 /* OPEN */) {
      ws.send(JSON.stringify(data));
    }
  }

  /**
   * Broadcast a message to all online members of a room.
   * @param {string|null} excludeUserId - If set, skip this user
   */
  _broadcastToRoom(roomId, excludeUserId, data) {
    const room = roomManager.getRoom(roomId);
    if (!room) return;

    const payload = JSON.stringify(data);
    for (const [memberId] of room.members) {
      if (memberId === excludeUserId) continue;
      const ws = this.connections.get(memberId);
      if (ws && ws.readyState === 1 /* OPEN */) {
        ws.send(payload);
      }
    }
  }
}

module.exports = new MessageHandler(); // singleton
/**
 * RoomManager
 * -----------
 * Manages all active rooms, their members, host assignments,
 * and current playback state. This is the authoritative source
 * of truth for room state on the server.
 */

const { v4: uuidv4 } = require('uuid');

class RoomManager {
  constructor() {
    // Map<roomId, RoomState>
    this.rooms = new Map();
  }

  /**
   * Create a new room.
   * @param {string} hostUserId - The socket/user ID of the room creator
   * @param {string} hostDisplayName - Display name of the creator
   * @returns {object} The newly created room state
   */
  createRoom(hostUserId, hostDisplayName) {
    const roomId = this._generateRoomId();
    const room = {
      id: roomId,
      createdAt: Date.now(),
      // adminId is fixed — only admin can add/remove hosts
      adminId: hostUserId,
      // hosts can control playback
      hosts: new Set([hostUserId]),
      // members: Map<userId, MemberInfo>
      members: new Map([[
        hostUserId,
        { id: hostUserId, name: hostDisplayName, joinedAt: Date.now(), isOnline: true }
      ]]),
      // playback state — server is authoritative
      playback: {
        videoId: null,
        videoTitle: null,
        videoThumbnail: null,
        isPlaying: false,
        position: 0,           // seconds into the video
        updatedAt: Date.now(), // server timestamp when this state was last set
      },
      // chat messages (kept in memory — in production, use Redis/DB)
      messages: [],
    };

    this.rooms.set(roomId, room);
    console.log(`[RoomManager] Room created: ${roomId} by ${hostDisplayName}`);
    return this._serializeRoom(room, hostUserId);
  }

  /**
   * Join an existing room.
   * @returns {object|null} Room state or null if room not found
   */
  joinRoom(roomId, userId, displayName) {
    const room = this.rooms.get(roomId);
    if (!room) return null;

    // Add or re-activate member
    if (room.members.has(userId)) {
      room.members.get(userId).isOnline = true;
    } else {
      room.members.set(userId, {
        id: userId,
        name: displayName,
        joinedAt: Date.now(),
        isOnline: true,
      });
    }

    console.log(`[RoomManager] ${displayName} joined room ${roomId}`);
    return this._serializeRoom(room, userId);
  }

  /**
   * Mark a member as offline (disconnected).
   * @returns {string|null} roomId if found, null otherwise
   */
  memberDisconnected(userId) {
    for (const [roomId, room] of this.rooms) {
      if (room.members.has(userId)) {
        room.members.get(userId).isOnline = false;

        // If admin leaves, pick a new admin from remaining online hosts
        if (room.adminId === userId) {
          const onlineHost = [...room.hosts].find(
            hId => hId !== userId && room.members.get(hId)?.isOnline
          );
          if (onlineHost) {
            room.adminId = onlineHost;
            console.log(`[RoomManager] Admin transferred to ${onlineHost} in room ${roomId}`);
          }
        }

        // Clean up empty rooms after a grace period
        const onlineCount = [...room.members.values()].filter(m => m.isOnline).length;
        if (onlineCount === 0) {
          setTimeout(() => {
            const r = this.rooms.get(roomId);
            if (r) {
              const stillOnline = [...r.members.values()].filter(m => m.isOnline).length;
              if (stillOnline === 0) {
                this.rooms.delete(roomId);
                console.log(`[RoomManager] Room ${roomId} deleted (empty)`);
              }
            }
          }, 30000); // 30 second grace period for reconnection
        }

        return roomId;
      }
    }
    return null;
  }

  /**
   * Update the playback state of a room (called when host sends events).
   * Returns the updated playback state with server timestamp.
   */
  updatePlayback(roomId, userId, playbackUpdate) {
    const room = this.rooms.get(roomId);
    if (!room) return null;
    if (!room.hosts.has(userId)) return { error: 'NOT_HOST' };

    room.playback = {
      ...room.playback,
      ...playbackUpdate,
      updatedAt: Date.now(), // authoritative server time
    };

    return room.playback;
  }

  /**
   * Assign host role to a user (admin only).
   */
  addHost(roomId, adminId, targetUserId) {
    const room = this.rooms.get(roomId);
    if (!room) return { error: 'ROOM_NOT_FOUND' };
    if (room.adminId !== adminId) return { error: 'NOT_ADMIN' };
    if (!room.members.has(targetUserId)) return { error: 'USER_NOT_IN_ROOM' };

    room.hosts.add(targetUserId);
    return { success: true, hostId: targetUserId };
  }

  /**
   * Remove host role from a user (admin only).
   */
  removeHost(roomId, adminId, targetUserId) {
    const room = this.rooms.get(roomId);
    if (!room) return { error: 'ROOM_NOT_FOUND' };
    if (room.adminId !== adminId) return { error: 'NOT_ADMIN' };
    if (targetUserId === adminId) return { error: 'CANNOT_REMOVE_ADMIN' };

    room.hosts.delete(targetUserId);
    return { success: true };
  }

  /**
   * Add a chat message to room history.
   */
  addMessage(roomId, userId, text) {
    const room = this.rooms.get(roomId);
    if (!room) return null;

    const member = room.members.get(userId);
    if (!member) return null;

    const message = {
      id: uuidv4(),
      userId,
      userName: member.name,
      text,
      timestamp: Date.now(),
    };

    // Keep last 200 messages in memory
    room.messages.push(message);
    if (room.messages.length > 200) room.messages.shift();

    return message;
  }

  getRoom(roomId) {
    return this.rooms.get(roomId) || null;
  }

  isHost(roomId, userId) {
    const room = this.rooms.get(roomId);
    return room ? room.hosts.has(userId) : false;
  }

  isAdmin(roomId, userId) {
    const room = this.rooms.get(roomId);
    return room ? room.adminId === userId : false;
  }

  /**
   * Serialize room state for sending to clients.
   * Sets are converted to arrays, Maps to arrays of values.
   */
  _serializeRoom(room, requestingUserId) {
    return {
      id: room.id,
      adminId: room.adminId,
      hosts: [...room.hosts],
      members: [...room.members.values()],
      playback: room.playback,
      messages: room.messages.slice(-50), // send last 50 messages on join
      yourRole: {
        isAdmin: room.adminId === requestingUserId,
        isHost: room.hosts.has(requestingUserId),
      },
    };
  }

  /**
   * Generate a short, human-readable room ID (6 uppercase alphanumeric chars).
   */
  _generateRoomId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no confusable chars
    let id;
    do {
      id = Array.from({ length: 6 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
    } while (this.rooms.has(id));
    return id;
  }
}

module.exports = new RoomManager(); // singleton
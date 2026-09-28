/**
 * WebRTC Online Cloud Signaling Server
 * Node.js + Express + Socket.io
 *
 * Handles user presence, WebRTC SDP negotiation (Offer/Answer),
 * ICE candidate relay, and call lifecycle state.
 */

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});

const PORT = process.env.PORT || 3000;

// Map: userId -> { socketId, username, connectedAt }
const connectedUsers = new Map();
// Map: socketId -> userId
const socketToUser = new Map();

app.get('/', (req, res) => {
  res.send({
    status: 'online',
    server: 'WebRTC Signaling Server',
    activeUsersCount: connectedUsers.size
  });
});

app.get('/users', (req, res) => {
  const users = Array.from(connectedUsers.values()).map(u => ({
    userId: u.userId,
    username: u.username
  }));
  res.json({ users });
});

io.on('connection', (socket) => {
  console.log(`[Socket Connected] Socket ID: ${socket.id}`);

  // 1. User Registration
  socket.on('register_user', ({ userId, username }) => {
    if (!userId) return;

    connectedUsers.set(userId, {
      socketId: socket.id,
      username: username || userId,
      userId: userId,
      connectedAt: new Date()
    });
    socketToUser.set(socket.id, userId);

    console.log(`[Registered] User: ${username} (${userId}) on Socket: ${socket.id}`);

    // Broadcast updated online user list to all connected clients
    broadcastUserList();
  });

  // 2. Call Request (Caller -> Server -> Callee)
  socket.on('call_user', ({ targetUserId, callerId, callerName }) => {
    const target = connectedUsers.get(targetUserId);
    if (target) {
      console.log(`[Call Request] ${callerName} (${callerId}) calling ${targetUserId}`);
      io.to(target.socketId).emit('incoming_call', {
        callerId,
        callerName,
        callerSocketId: socket.id
      });
    } else {
      socket.emit('call_failed', { reason: 'User is offline or unavailable.' });
    }
  });

  // 3. Call Acceptance (Callee -> Server -> Caller)
  socket.on('accept_call', ({ targetUserId }) => {
    const target = connectedUsers.get(targetUserId);
    if (target) {
      console.log(`[Call Accepted] User ${socketToUser.get(socket.id)} accepted call from ${targetUserId}`);
      io.to(target.socketId).emit('call_accepted', {
        responderId: socketToUser.get(socket.id)
      });
    }
  });

  // 4. Call Rejection (Callee -> Server -> Caller)
  socket.on('reject_call', ({ targetUserId, reason }) => {
    const target = connectedUsers.get(targetUserId);
    if (target) {
      console.log(`[Call Rejected] User ${socketToUser.get(socket.id)} rejected call from ${targetUserId}`);
      io.to(target.socketId).emit('call_rejected', {
        reason: reason || 'Call rejected by user.'
      });
    }
  });

  // 5. WebRTC SDP Offer Relay
  socket.on('webrtc_offer', ({ targetUserId, sdp }) => {
    const target = connectedUsers.get(targetUserId);
    if (target) {
      console.log(`[SDP Offer] Relaying offer from ${socketToUser.get(socket.id)} to ${targetUserId}`);
      io.to(target.socketId).emit('webrtc_offer', {
        senderId: socketToUser.get(socket.id),
        sdp
      });
    }
  });

  // 6. WebRTC SDP Answer Relay
  socket.on('webrtc_answer', ({ targetUserId, sdp }) => {
    const target = connectedUsers.get(targetUserId);
    if (target) {
      console.log(`[SDP Answer] Relaying answer from ${socketToUser.get(socket.id)} to ${targetUserId}`);
      io.to(target.socketId).emit('webrtc_answer', {
        senderId: socketToUser.get(socket.id),
        sdp
      });
    }
  });

  // 7. ICE Candidate Relay
  socket.on('ice_candidate', ({ targetUserId, candidate }) => {
    const target = connectedUsers.get(targetUserId);
    if (target) {
      io.to(target.socketId).emit('ice_candidate', {
        senderId: socketToUser.get(socket.id),
        candidate
      });
    }
  });

  // 8. End Call Notification
  socket.on('end_call', ({ targetUserId }) => {
    const target = connectedUsers.get(targetUserId);
    if (target) {
      console.log(`[Call Ended] Notification sent from ${socketToUser.get(socket.id)} to ${targetUserId}`);
      io.to(target.socketId).emit('call_ended', {
        senderId: socketToUser.get(socket.id)
      });
    }
  });

  // 9. Disconnect Handling
  socket.on('disconnect', () => {
    const userId = socketToUser.get(socket.id);
    if (userId) {
      console.log(`[Socket Disconnected] User: ${userId}, Socket: ${socket.id}`);
      connectedUsers.delete(userId);
      socketToUser.delete(socket.id);
      broadcastUserList();
    }
  });
});

function broadcastUserList() {
  const users = Array.from(connectedUsers.values()).map(u => ({
    userId: u.userId,
    username: u.username
  }));
  io.emit('online_users', users);
}

server.listen(PORT, () => {
  console.log(`WebRTC Online Signaling Server running on http://localhost:${PORT}`);
});

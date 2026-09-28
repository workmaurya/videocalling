# Dual-Mode WebRTC Video Calling Architecture & Connection Sequence

This document details the system architecture, network protocols, signaling workflows, and WebRTC peer connection handshakes for both **Online Mode** (Cloud Signaling via Socket.io) and **Offline Mode** (Local Network Discovery & P2P Signaling via UDP + HTTP/WebSocket).

---

## System Architecture Overview

```
                          +-----------------------------------+
                          |     Online Cloud Signaling        |
                          |     (Node.js + Socket.io)         |
                          +-----------------------------------+
                                    ^               ^
                    Socket.io (WSS) |               | Socket.io (WSS)
                                    v               v
    +----------------------------------+         +----------------------------------+
    |           Device A               |         |           Device B               |
    |  - Network Auto-Detector         |         |  - Network Auto-Detector         |
    |  - WebRTC Engine                 |<------->|  - WebRTC Engine                 |
    |  - Local UDP Discovery Server    | P2P     |  - Local UDP Discovery Server    |
    |  - Local HTTP/WS Signaling       | WebRTC  |  - Local HTTP/WS Signaling       |
    +----------------------------------+         +----------------------------------+
                    ^                                       ^
                    |           Local Wi-Fi Network         |
                    +-- UDP Broadcast / Direct Local WS ---+
```

---

## 1. Online Mode Signaling & Connection Sequence

When internet connectivity is active, devices connect to the centralized cloud signaling server using WebSockets/Socket.io.

### Online Connection Flow

```
Device A (Caller)              Cloud Server (Node.js)             Device B (Callee)
       |                                |                                |
       |--- 1. Register User (ID) ----->|                                |
       |                                |<----- 1. Register User (ID) ---|
       |                                |                                |
       |--- 2. Call Request (Target B) ->|                                |
       |                                |--- 3. Incoming Call Alert ---->|
       |                                |<-- 4. Accept Call -------------|
       |<-- 5. Call Accepted -----------|                                |
       |                                |                                |
       |--- 6. Send WebRTC Offer ------>|                                |
       |    (SDP Offer)                 |--- 7. Relay Offer ------------>|
       |                                |<-- 8. Send WebRTC Answer ------|
       |<-- 9. Relay Answer ------------|    (SDP Answer)                |
       |                                |                                |
       |--- 10. Send ICE Candidate ---->|                                |
       |                                |--- 11. Relay ICE Candidate --->|
       |                                |<-- 12. Send ICE Candidate -----|
       |<-- 13. Relay ICE Candidate ----|                                |
       |                                |                                |
       +=================== 14. WebRTC P2P Media Stream =================+
       |                  (Audio / Video via STUN/TURN)                  |
```

### Protocol Steps (Online Mode):
1. **User Registration:** Each client connects to Socket.io and emits `register_user` with a unique User ID and display name.
2. **Call Initiation:** Device A selects Device B from the online user directory and sends a `call_user` event containing `targetUserId`.
3. **Ringing & Acceptance:** Device B receives `incoming_call`. If accepted, Device B emits `accept_call`.
4. **Offer Generation:** Device A creates a local WebRTC media stream, creates an SDP offer (`peerConnection.createOffer()`), sets local description, and transmits the offer to Device B via Socket.io.
5. **Answer Generation:** Device B receives the SDP offer, sets remote description, creates a local WebRTC media stream, creates an SDP answer (`peerConnection.createAnswer()`), sets local description, and transmits the SDP answer back.
6. **ICE Candidate Exchange:** As ICE candidates are gathered on both ends (from public STUN servers such as `stun:stun.l.google.com:19302`), they are trickled through the Socket.io server to the remote peer via `ice_candidate` events.
7. **P2P Media Session:** Direct WebRTC peer connection is established. Audio/video media frames travel directly between peers.

---

## 2. Offline Mode Discovery & Connection Sequence

When internet connectivity is unavailable, the app relies on **Local Wi-Fi Network Auto-Discovery** (UDP Broadcasting on Port `45454`) and a **Local HTTP/WebSocket Signaling Server** hosted directly on the device initiating or listening for calls.

### Offline Connection Flow

```
Device A (Caller)                                                 Device B (Callee)
       |                                                                 |
       |--- 1. UDP Discovery Broadcast (Port 45454) "HELO_PEER" -------->|
       |<-- 2. UDP Discovery Response "PEER_ALIVE" (Device B IP/Port) ---|
       |                                                                 |
       |   (Device A discovers Device B on Local Subnet 192.168.x.x)     |
       |                                                                 |
       |--- 3. Local HTTP POST /call-request (to Device B Local IP) ----->|
       |    {"callerId": "A", "callerIp": "192.168.1.10", "port": 8080}    |
       |                                                                 |
       |<-- 4. Local Call Accept Response 200 OK -----------------------|
       |                                                                 |
       |--- 5. Connect to Device A Local Signaling Server (WebSocket) --->|
       |                       (ws://192.168.1.10:8080)                  |
       |                                                                 |
       |--- 6. Send SDP Offer (via Local WebSocket) -------------------->|
       |<-- 7. Send SDP Answer (via Local WebSocket) -------------------|
       |                                                                 |
       |<== 8. Trickle ICE Candidates (Local IP Host Candidates) ======>|
       |                                                                 |
       +=================== 9. WebRTC Local P2P Stream ==================+
       |                    (Direct Local LAN Transport)                 |
```

### Protocol Steps (Offline Mode):
1. **UDP Peer Discovery:**
   - Every node runs a local UDP listener bound to port `45454`.
   - Nodes periodically broadcast a UDP packet `HELO_PEER` to `255.255.255.255:45454` containing JSON data: `{ "deviceId": "...", "deviceName": "...", "localIp": "192.168.1.10", "signalPort": 8080 }`.
   - Receiving devices parse the broadcast and populate their "Nearby Offline Devices" list.
2. **Local HTTP Signaling Setup:**
   - Every client runs a lightweight embedded HTTP/WebSocket server on port `8080`.
3. **Call Initiation over LAN:**
   - Device A triggers a local HTTP `POST /call-request` to `http://<Device_B_IP>:8080/call-request`.
   - Device B displays an incoming call ringing dialog.
4. **Call Acceptance & Local WebSockets:**
   - When Device B accepts, both devices establish a direct WebSocket connection on Device A's local signaling port.
5. **WebRTC Direct Exchange:**
   - Devices exchange SDP Offer and SDP Answer over the direct local WebSocket.
   - ICE Candidate gathering identifies local Host candidates (e.g., `192.168.1.10:50000`). Direct local socket pairs are bound without needing STUN or TURN servers.
6. **Local Media Session:** Audio and video streams flow with ultra-low latency over the local Wi-Fi router or direct Wi-Fi hotspot.

---

## 3. Network Mode Switch & Reconnection Handling

```
 +------------------------+
 | Monitoring Connectivity|
 +------------------------+
             |
             +---> Internet Available? ---> YES ---> Connect to Cloud Socket.io (Online Mode)
             |                                        - Refresh peer directory
             |                                        - Enable STUN/TURN ICE servers
             |
             +---> Internet Unavailable? -> YES ---> Enable Local UDP Discovery (Offline Mode)
                                                      - Bind UDP Port 45454
                                                      - Start Local HTTP/WS Server Port 8080
                                                      - Restrict ICE candidates to Host interfaces
```

### Graceful Reconnection Mechanism:
- If network connectivity drops mid-call, the WebRTC engine enters `ICE_DISCONNECTED` or `ICE_FAILED` state.
- The `WebRTCService` triggers a 5-second renegotiation timer.
- If online connectivity returns, Socket.io re-registers the user and attempts ICE restart (`peerConnection.restartIce()`).
- If offline connectivity is active on the same LAN, local signaling renegotiates local host ICE candidates seamlessly.

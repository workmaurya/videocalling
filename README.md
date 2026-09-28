# Hybrid Online and Offline Video Calling Application

A production-grade, dual-mode WebRTC Video Calling App built with Flutter, Node.js Socket.io signaling, and UDP local network auto-discovery.

---

## Key Capabilities & Features

- **Dual-Mode System Architecture:**
  - **Online Mode:** Uses a central Node.js & Socket.io server with public STUN servers for internet-wide WebRTC video/audio calls.
  - **Offline Mode:** Uses local network UDP broadcasting (Port `45454`) and embedded HTTP signaling (Port `8080`) to discover and call nearby devices on the same Wi-Fi router or hotspot without internet access.
- **Automatic Connection Mode Detection:** Switches seamlessly between Cloud Socket.io and Local UDP discovery when network connectivity changes.
- **Full Call Lifecycle Management:** Call invitation, ringing alerts, accept/reject, mute/unmute audio, video stream toggle, camera flip (front/rear), and call termination.
- **Graceful Reconnection:** Network drop handling with automatic ICE candidate renegotiation.

---

## Directory & File Structure

```
├── docs/
│   └── architecture.md              # Detailed signaling sequence and system architecture
├── server/
│   ├── package.json                 # Signaling server dependencies
│   └── server.js                    # Node.js + Socket.io cloud signaling server
├── lib/
│   ├── main.dart                    # App entrypoint
│   ├── services/
│   │   ├── offline_discovery_service.dart # UDP local discovery & local HTTP signaling
│   │   └── webrtc_service.dart      # WebRTC media controller & mode switcher
│   └── screens/
│       ├── home_screen.dart         # Peer discovery dashboard & network state indicator
│       └── call_screen.dart         # Video stream grid & RTC call controls
├── android/
│   └── app/src/main/AndroidManifest.xml # Android permissions (Camera, Mic, Wi-Fi)
├── ios/
│   └── Runner/Info.plist            # iOS permissions & Local Network keys
├── pubspec.yaml                     # Flutter dependencies
└── README.md                        # Documentation & Physical Device Testing Guide
```

---

## Step-by-Step Setup Instructions

### 1. Cloud Signaling Server Setup
```bash
cd server
npm install
npm start
```
The server runs by default on `http://localhost:3000`.

### 2. Mobile Flutter Client Setup
```bash
# Get dependencies
flutter pub get

# Run on Android physical device or simulator
flutter run -d <device_id>
```

---

## Step-by-Step Physical Device Testing Guide

### Testing Online Mode (Internet Active)

1. **Start Cloud Signaling Server:** Ensure `node server/server.js` is running on a reachable server or local machine accessible to both devices.
2. **Connect Physical Devices:** Connect Device A and Device B to the internet.
3. **Launch Mobile App:**
   - Open the app on both physical devices.
   - The app will automatically connect to Socket.io signaling server and assign unique User IDs (`user_XXXX`).
4. **Initiate Call:**
   - On Device A, locate Device B in the "Online Users" list.
   - Tap the video call button next to Device B.
5. **Accept Call:**
   - Device B receives an incoming call alert with caller name and "Online Mode" badge.
   - Tap **Accept**.
6. **Verify Audio & Video Stream:**
   - Confirm local and remote video streams render on both screens.
   - Test mute/unmute, flip camera, and end call controls.

---

### Testing Offline Mode (No Internet / Local Wi-Fi / Hotspot)

1. **Setup Offline Network:**
   - Turn off cellular data on both Device A and Device B.
   - Connect both devices to the same Wi-Fi network (or turn on Portable Hotspot on Device A and connect Device B to Device A's hotspot).
   - Ensure **no internet access** is active on the network.
2. **Launch Mobile App:**
   - Open the app on both physical devices.
   - The connectivity listener will detect no internet and automatically activate **Offline Mode**.
3. **Local UDP Peer Auto-Discovery:**
   - Both devices begin broadcasting UDP packets to `255.255.255.255:45454`.
   - Within 3 seconds, Device B will appear in Device A's "Nearby Offline Devices" list showing its local IP address (e.g. `192.168.1.15:8080`).
4. **Initiate Direct LAN Call:**
   - On Device A, tap the call icon next to Device B in the offline discovery list.
   - Device A sends a direct HTTP POST request to Device B's local IP address (`http://192.168.1.15:8080/call-request`).
5. **Accept Offline Call:**
   - Device B receives a ringing dialog indicating "Local LAN Offline".
   - Tap **Accept**.
6. **Local WebRTC Media Handshake:**
   - Devices exchange SDP Offer/Answer and Host ICE candidates directly over local IP without external server routing.
   - WebRTC media streams are established directly over the local network.
7. **Verify Local Performance:**
   - Notice ultra-low latency video/audio streaming over LAN.
   - Test camera flip, audio mute, and disconnect controls.

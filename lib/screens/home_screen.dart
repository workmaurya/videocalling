import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/webrtc_service.dart';
import '../services/offline_discovery_service.dart';
import 'call_screen.dart';

class HomeScreen extends StatefulWidget {
  final WebRTCService rtcService;

  const HomeScreen({Key? key, required this.rtcService}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ConnectionMode _activeMode = ConnectionMode.disconnected;
  List<dynamic> _onlineUsers = [];
  List<DiscoveredPeer> _discoveredPeers = [];
  StreamSubscription? _connectivitySub;
  StreamSubscription? _offlinePeersSub;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initRtcListeners();
    _monitorNetworkConnectivity();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();
  }

  void _initRtcListeners() {
    widget.rtcService.onModeChanged = (mode) {
      if (mounted) setState(() => _activeMode = mode);
    };

    widget.rtcService.onOnlineUsersUpdated = (users) {
      if (mounted) setState(() => _onlineUsers = users);
    };

    _offlinePeersSub = widget.rtcService.offlineDiscoveryService.peersStream.listen((peers) {
      if (mounted) setState(() => _discoveredPeers = peers);
    });

    widget.rtcService.onIncomingCall = (callInfo) {
      _showIncomingCallDialog(callInfo);
    };
  }

  void _monitorNetworkConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isConnected = results.any((r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile);
      if (isConnected) {
        widget.rtcService.connectOnline();
      } else {
        widget.rtcService.enableOfflineMode();
      }
    });
  }

  void _showIncomingCallDialog(Map<String, dynamic> callInfo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Incoming Video Call'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Caller: ${callInfo['callerName']}'),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(
                callInfo['mode'] == ConnectionMode.online ? Icons.cloud : Icons.wifi,
                color: Colors.white,
                size: 16,
              ),
              label: Text(
                callInfo['mode'] == ConnectionMode.online ? 'Online Mode' : 'Local LAN Offline',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: callInfo['mode'] == ConnectionMode.online
                  ? Colors.blue
                  : Colors.orange,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.rtcService.rejectIncomingCall();
              Navigator.pop(context);
            },
            child: const Text('Reject', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              Navigator.pop(context);
              await widget.rtcService.acceptIncomingCall();
              _navigateToCallScreen(
                peerName: callInfo['callerName'],
                isIncoming: true,
              );
            },
            child: const Text('Accept', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _navigateToCallScreen({required String peerName, bool isIncoming = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          rtcService: widget.rtcService,
          peerName: peerName,
          isIncoming: isIncoming,
        ),
      ),
    );
  }

  void _startCall(String targetId, String name, {String? targetIp}) async {
    await widget.rtcService.initiateCall(targetId, targetIp: targetIp);
    _navigateToCallScreen(peerName: name, isIncoming: false);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _offlinePeersSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = _activeMode == ConnectionMode.online;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dual-Mode Video Call'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  isOnline ? Icons.cloud_done : Icons.wifi_tethering,
                  color: isOnline ? Colors.greenAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  isOnline ? 'Online' : 'Offline Direct',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // Network Switch Manual Toggle Banner
          Container(
            color: isOnline ? Colors.blue[50] : Colors.orange[50],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User ID: ${widget.rtcService.userId}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      isOnline ? 'Connected to Cloud Server' : 'Scanning LAN (UDP 45454)',
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                  ],
                ),
                Switch(
                  value: isOnline,
                  activeTrackColor: Colors.blueAccent,
                  inactiveThumbColor: Colors.orange,
                  onChanged: (val) {
                    if (val) {
                      widget.rtcService.connectOnline();
                    } else {
                      widget.rtcService.enableOfflineMode();
                    }
                  },
                )
              ],
            ),
          ),

          Expanded(
            child: isOnline ? _buildOnlineUsersList() : _buildOfflinePeersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineUsersList() {
    final filteredUsers =
        _onlineUsers.where((u) => u['userId'] != widget.rtcService.userId).toList();

    if (filteredUsers.isEmpty) {
      return const Center(
        child: Text('No other users currently online.'),
      );
    }

    return ListView.builder(
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        final user = filteredUsers[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(user['username'] ?? 'User'),
          subtitle: Text('ID: ${user['userId']}'),
          trailing: IconButton(
            icon: const Icon(Icons.videocam, color: Colors.blue),
            onPressed: () => _startCall(user['userId'], user['username']),
          ),
        );
      },
    );
  }

  Widget _buildOfflinePeersList() {
    if (_discoveredPeers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning local Wi-Fi network for nearby devices...'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _discoveredPeers.length,
      itemBuilder: (context, index) {
        final peer = _discoveredPeers[index];
        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.orangeAccent,
            child: Icon(Icons.phone_android, color: Colors.white),
          ),
          title: Text(peer.deviceName),
          subtitle: Text('IP: ${peer.localIp}:${peer.signalPort}'),
          trailing: IconButton(
            icon: const Icon(Icons.videocam, color: Colors.orange),
            onPressed: () => _startCall(
              peer.deviceId,
              peer.deviceName,
              targetIp: peer.localIp,
            ),
          ),
        );
      },
    );
  }
}

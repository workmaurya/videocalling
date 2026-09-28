import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveredPeer {
  final String deviceId;
  final String deviceName;
  final String localIp;
  final int signalPort;
  DateTime lastSeen;

  DiscoveredPeer({
    required this.deviceId,
    required this.deviceName,
    required this.localIp,
    required this.signalPort,
    required this.lastSeen,
  });

  factory DiscoveredPeer.fromJson(Map<String, dynamic> json, String senderIp) {
    return DiscoveredPeer(
      deviceId: json['deviceId'] ?? 'unknown',
      deviceName: json['deviceName'] ?? 'Unknown Device',
      localIp: senderIp,
      signalPort: json['signalPort'] ?? 8080,
      lastSeen: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'localIp': localIp,
        'signalPort': signalPort,
      };
}

class OfflineDiscoveryService {
  static const int udpPort = 45454;
  static const int localSignalPort = 8080;

  final String currentDeviceId;
  final String currentDeviceName;

  RawDatagramSocket? _udpSocket;
  HttpServer? _httpServer;
  Timer? _broadcastTimer;
  Timer? _pruneTimer;

  final Map<String, DiscoveredPeer> _discoveredPeers = {};
  final StreamController<List<DiscoveredPeer>> _peersStreamController =
      StreamController<List<DiscoveredPeer>>.broadcast();

  // Callbacks for local HTTP signaling
  Function(Map<String, dynamic> callData)? onIncomingLocalCall;
  Function(Map<String, dynamic> sdpOfferData)? onLocalOfferReceived;
  Function(Map<String, dynamic> sdpAnswerData)? onLocalAnswerReceived;
  Function(Map<String, dynamic> iceData)? onLocalIceCandidateReceived;
  Function(String callerId)? onLocalCallEnded;

  Stream<List<DiscoveredPeer>> get peersStream => _peersStreamController.stream;

  OfflineDiscoveryService({
    required this.currentDeviceId,
    required this.currentDeviceName,
  });

  /// Starts local discovery listeners and UDP broadcasting
  Future<void> startDiscovery() async {
    await _startUdpListener();
    await _startLocalHttpServer();
    _startBroadcasting();
    _startPruningStalePeers();
  }

  /// Stops discovery services
  Future<void> stopDiscovery() async {
    _broadcastTimer?.cancel();
    _pruneTimer?.cancel();
    _udpSocket?.close();
    await _httpServer?.close(force: true);
    _discoveredPeers.clear();
    _peersStreamController.add([]);
  }

  /// Listens on UDP broadcast port 45454
  Future<void> _startUdpListener() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
      _udpSocket?.broadcastEnabled = true;

      _udpSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final Datagram? dg = _udpSocket?.receive();
          if (dg == null) return;

          try {
            final message = utf8.decode(dg.data);
            final json = jsonDecode(message);

            if (json['type'] == 'HELO_PEER' && json['deviceId'] != currentDeviceId) {
              final peer = DiscoveredPeer.fromJson(json, dg.address.address);
              _discoveredPeers[peer.deviceId] = peer;
              _peersStreamController.add(_discoveredPeers.values.toList());
            }
          } catch (e) {
            // Ignore malformed packets
          }
        }
      });
    } catch (e) {
      print('[Offline Discovery] UDP Bind Error: $e');
    }
  }

  /// Periodically broadcasts device presence on LAN
  void _startBroadcasting() {
    _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_udpSocket == null) return;

      final payload = jsonEncode({
        'type': 'HELO_PEER',
        'deviceId': currentDeviceId,
        'deviceName': currentDeviceName,
        'signalPort': localSignalPort,
      });

      final data = utf8.encode(payload);
      try {
        _udpSocket?.send(
          data,
          InternetAddress('255.255.255.255'),
          udpPort,
        );
      } catch (e) {
        print('[Offline Discovery] Broadcast Send Error: $e');
      }
    });
  }

  /// Removes peers that haven't broadcasted in > 10 seconds
  void _startPruningStalePeers() {
    _pruneTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      final now = DateTime.now();
      bool changed = false;

      _discoveredPeers.removeWhere((id, peer) {
        final isStale = now.difference(peer.lastSeen).inSeconds > 10;
        if (isStale) changed = true;
        return isStale;
      });

      if (changed) {
        _peersStreamController.add(_discoveredPeers.values.toList());
      }
    });
  }

  /// Starts local HTTP signaling server on port 8080
  Future<void> _startLocalHttpServer() async {
    try {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, localSignalPort);
      _httpServer?.listen((HttpRequest request) async {
        final path = request.uri.path;
        final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';

        if (request.method == 'POST') {
          final content = await utf8.decoder.bind(request).join();
          final data = jsonDecode(content) as Map<String, dynamic>;

          // Ensure callerIp is set to actual client IP if missing or set to placeholder
          if (remoteIp.isNotEmpty && (data['callerIp'] == null || data['callerIp'] == 'LOCAL' || (data['callerIp'] as String).isEmpty)) {
            data['callerIp'] = remoteIp;
          }

          switch (path) {
            case '/call-request':
              onIncomingLocalCall?.call(data);
              _sendJsonResponse(request, {'status': 'ringing'});
              break;
            case '/webrtc-offer':
              onLocalOfferReceived?.call(data);
              _sendJsonResponse(request, {'status': 'offer_received'});
              break;
            case '/webrtc-answer':
              onLocalAnswerReceived?.call(data);
              _sendJsonResponse(request, {'status': 'answer_received'});
              break;
            case '/ice-candidate':
              onLocalIceCandidateReceived?.call(data);
              _sendJsonResponse(request, {'status': 'ice_received'});
              break;
            case '/end-call':
              onLocalCallEnded?.call(data['callerId'] ?? '');
              _sendJsonResponse(request, {'status': 'ended'});
              break;
            default:
              request.response.statusCode = HttpStatus.notFound;
              await request.response.close();
          }
        } else {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
        }
      });
    } catch (e) {
      print('[Offline Signaling] HTTP Server Bind Error: $e');
    }
  }

  void _sendJsonResponse(HttpRequest request, Map<String, dynamic> data) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  /// Sends a local HTTP signaling message to a target IP
  Future<bool> sendLocalSignalingMessage(
    String targetIp,
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final request = await client.postUrl(
        Uri.parse('http://$targetIp:$localSignalPort$path'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      print('[Offline Signaling] Send failed to http://$targetIp:$localSignalPort$path: $e');
      return false;
    }
  }
}

import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'offline_discovery_service.dart';

enum ConnectionMode { online, offline, disconnected }

class WebRTCService {
  final String userId;
  final String userName;
  final String onlineServerUrl;

  // WebRTC Media Stream & Renderer variables
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  MediaStream? localStream;
  RTCPeerConnection? peerConnection;

  // Online Signaling
  io.Socket? _socket;

  // Offline Discovery & Signaling
  late OfflineDiscoveryService offlineDiscoveryService;

  // Connection State
  ConnectionMode currentMode = ConnectionMode.disconnected;
  bool isAudioMuted = false;
  bool isVideoMuted = false;
  bool isFrontCamera = true;
  String? activeCallPeerId;
  String? activeCallPeerIp;

  // Callbacks
  Function(ConnectionMode mode)? onModeChanged;
  Function(List<dynamic> onlineUsers)? onOnlineUsersUpdated;
  Function(Map<String, dynamic> callInfo)? onIncomingCall;
  Function()? onCallAccepted;
  Function(String reason)? onCallRejected;
  Function()? onCallEnded;

  WebRTCService({
    required this.userId,
    required this.userName,
    this.onlineServerUrl = 'http://localhost:3000',
  }) {
    offlineDiscoveryService = OfflineDiscoveryService(
      currentDeviceId: userId,
      currentDeviceName: userName,
    );
  }

  /// Initialize Renderers, Media Streams & Discovery
  Future<void> initialize() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();

    _setupOfflineCallbacks();
    await offlineDiscoveryService.startDiscovery();
  }

  /// Connect to Cloud Signaling (Online Mode)
  void connectOnline() {
    currentMode = ConnectionMode.online;
    onModeChanged?.call(currentMode);

    _socket = io.io(onlineServerUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    _socket?.onConnect((_) {
      print('[WebRTC Online] Socket Connected. Registering user...');
      _socket?.emit('register_user', {'userId': userId, 'username': userName});
    });

    _socket?.on('online_users', (data) {
      if (data is List) {
        onOnlineUsersUpdated?.call(data);
      }
    });

    _socket?.on('incoming_call', (data) {
      activeCallPeerId = data['callerId'];
      onIncomingCall?.call({
        'callerId': data['callerId'],
        'callerName': data['callerName'],
        'mode': ConnectionMode.online,
      });
    });

    _socket?.on('call_accepted', (_) {
      onCallAccepted?.call();
    });

    _socket?.on('call_rejected', (data) {
      onCallRejected?.call(data['reason'] ?? 'Call rejected');
      cleanupCall();
    });

    _socket?.on('webrtc_offer', (data) async {
      await _handleReceivedOffer(data['sdp'], isOnline: true);
    });

    _socket?.on('webrtc_answer', (data) async {
      await _handleReceivedAnswer(data['sdp']);
    });

    _socket?.on('ice_candidate', (data) async {
      await _handleReceivedIceCandidate(data['candidate']);
    });

    _socket?.on('call_ended', (_) {
      onCallEnded?.call();
      cleanupCall();
    });

    _socket?.onDisconnect((_) {
      print('[WebRTC Online] Socket Disconnected.');
    });
  }

  /// Switch to Offline Local Network Mode
  void enableOfflineMode() {
    _socket?.disconnect();
    currentMode = ConnectionMode.offline;
    onModeChanged?.call(currentMode);
  }

  /// Setup Offline HTTP/WS Signaling Callbacks
  void _setupOfflineCallbacks() {
    offlineDiscoveryService.onIncomingLocalCall = (data) {
      activeCallPeerId = data['callerId'];
      activeCallPeerIp = data['callerIp'];
      onIncomingCall?.call({
        'callerId': data['callerId'],
        'callerName': data['callerName'] ?? data['callerId'],
        'callerIp': data['callerIp'],
        'mode': ConnectionMode.offline,
      });
    };

    offlineDiscoveryService.onLocalOfferReceived = (data) async {
      await _handleReceivedOffer(data['sdp'], isOnline: false);
    };

    offlineDiscoveryService.onLocalAnswerReceived = (data) async {
      await _handleReceivedAnswer(data['sdp']);
    };

    offlineDiscoveryService.onLocalIceCandidateReceived = (data) async {
      await _handleReceivedIceCandidate(data['candidate']);
    };

    offlineDiscoveryService.onLocalCallEnded = (_) {
      onCallEnded?.call();
      cleanupCall();
    };
  }

  /// Start Local Media Stream (Camera & Microphone)
  Future<void> startLocalMediaStream() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': isFrontCamera ? 'user' : 'environment',
        'optional': [],
      }
    };

    localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localRenderer.srcObject = localStream;
  }

  /// Create WebRTC Peer Connection with STUN configuration
  Future<void> _createPeerConnection({required bool isOnline}) async {
    final Map<String, dynamic> configuration = {
      'iceServers': isOnline
          ? [
              {'urls': 'stun:stun.l.google.com:19302'},
              {'urls': 'stun:stun1.l.google.com:19302'},
            ]
          : [], // Direct LAN Host ICE Gathering only in Offline Mode
      'sdpSemantics': 'unified-plan',
    };

    peerConnection = await createPeerConnection(configuration);

    if (localStream != null) {
      localStream!.getTracks().forEach((track) {
        peerConnection?.addTrack(track, localStream!);
      });
    }

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;

      final candidateMap = {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };

      if (currentMode == ConnectionMode.online) {
        _socket?.emit('ice_candidate', {
          'targetUserId': activeCallPeerId,
          'candidate': candidateMap,
        });
      } else if (currentMode == ConnectionMode.offline && activeCallPeerIp != null) {
        offlineDiscoveryService.sendLocalSignalingMessage(
          activeCallPeerIp!,
          '/ice-candidate',
          {'callerId': userId, 'candidate': candidateMap},
        );
      }
    };

    peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
      }
    };

    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      print('[WebRTC PeerState] Connection state changed: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        print('[WebRTC PeerState] Connection lost. Attempting reconnection...');
      }
    };
  }

  /// Initiate Call (Caller)
  Future<void> initiateCall(String targetId, {String? targetIp}) async {
    activeCallPeerId = targetId;
    activeCallPeerIp = targetIp;

    await startLocalMediaStream();
    await _createPeerConnection(isOnline: currentMode == ConnectionMode.online);

    if (currentMode == ConnectionMode.online) {
      _socket?.emit('call_user', {
        'targetUserId': targetId,
        'callerId': userId,
        'callerName': userName,
      });
    } else if (currentMode == ConnectionMode.offline && targetIp != null) {
      await offlineDiscoveryService.sendLocalSignalingMessage(
        targetIp,
        '/call-request',
        {'callerId': userId, 'callerName': userName, 'callerIp': 'LOCAL'},
      );
    }
  }

  /// Accept Call (Callee)
  Future<void> acceptIncomingCall() async {
    await startLocalMediaStream();
    await _createPeerConnection(isOnline: currentMode == ConnectionMode.online);

    if (currentMode == ConnectionMode.online) {
      _socket?.emit('accept_call', {'targetUserId': activeCallPeerId});
    }

    // Generate SDP Offer if caller requires answer-first flow
    await createAndSendOffer();
  }

  /// Reject Incoming Call
  void rejectIncomingCall() {
    if (currentMode == ConnectionMode.online && activeCallPeerId != null) {
      _socket?.emit('reject_call', {'targetUserId': activeCallPeerId});
    }
    cleanupCall();
  }

  /// Create and Send WebRTC SDP Offer
  Future<void> createAndSendOffer() async {
    if (peerConnection == null) return;

    RTCSessionDescription offer = await peerConnection!.createOffer({});
    await peerConnection!.setLocalDescription(offer);

    final sdpMap = {'sdp': offer.sdp, 'type': offer.type};

    if (currentMode == ConnectionMode.online) {
      _socket?.emit('webrtc_offer', {
        'targetUserId': activeCallPeerId,
        'sdp': sdpMap,
      });
    } else if (currentMode == ConnectionMode.offline && activeCallPeerIp != null) {
      offlineDiscoveryService.sendLocalSignalingMessage(
        activeCallPeerIp!,
        '/webrtc-offer',
        {'callerId': userId, 'sdp': sdpMap},
      );
    }
  }

  /// Handle Received Offer
  Future<void> _handleReceivedOffer(Map<String, dynamic> sdpMap, {required bool isOnline}) async {
    if (peerConnection == null) {
      await startLocalMediaStream();
      await _createPeerConnection(isOnline: isOnline);
    }

    RTCSessionDescription description = RTCSessionDescription(
      sdpMap['sdp'],
      sdpMap['type'],
    );

    await peerConnection!.setRemoteDescription(description);

    RTCSessionDescription answer = await peerConnection!.createAnswer({});
    await peerConnection!.setLocalDescription(answer);

    final answerMap = {'sdp': answer.sdp, 'type': answer.type};

    if (currentMode == ConnectionMode.online) {
      _socket?.emit('webrtc_answer', {
        'targetUserId': activeCallPeerId,
        'sdp': answerMap,
      });
    } else if (currentMode == ConnectionMode.offline && activeCallPeerIp != null) {
      offlineDiscoveryService.sendLocalSignalingMessage(
        activeCallPeerIp!,
        '/webrtc-answer',
        {'callerId': userId, 'sdp': answerMap},
      );
    }
  }

  /// Handle Received Answer
  Future<void> _handleReceivedAnswer(Map<String, dynamic> sdpMap) async {
    if (peerConnection == null) return;
    RTCSessionDescription description = RTCSessionDescription(
      sdpMap['sdp'],
      sdpMap['type'],
    );
    await peerConnection!.setRemoteDescription(description);
  }

  /// Handle ICE Candidate
  Future<void> _handleReceivedIceCandidate(Map<String, dynamic> candidateMap) async {
    if (peerConnection == null) return;
    RTCIceCandidate candidate = RTCIceCandidate(
      candidateMap['candidate'],
      candidateMap['sdpMid'],
      candidateMap['sdpMLineIndex'],
    );
    await peerConnection!.addCandidate(candidate);
  }

  /// Toggle Audio Mute
  void toggleMuteAudio() {
    if (localStream != null && localStream!.getAudioTracks().isNotEmpty) {
      isAudioMuted = !isAudioMuted;
      localStream!.getAudioTracks()[0].enabled = !isAudioMuted;
    }
  }

  /// Toggle Video Stream
  void toggleVideo() {
    if (localStream != null && localStream!.getVideoTracks().isNotEmpty) {
      isVideoMuted = !isVideoMuted;
      localStream!.getVideoTracks()[0].enabled = !isVideoMuted;
    }
  }

  /// Flip Front / Rear Camera
  Future<void> switchCamera() async {
    if (localStream != null && localStream!.getVideoTracks().isNotEmpty) {
      final videoTrack = localStream!.getVideoTracks()[0];
      await Helper.switchCamera(videoTrack);
      isFrontCamera = !isFrontCamera;
    }
  }

  /// End Active Call
  Future<void> endCall() async {
    if (currentMode == ConnectionMode.online && activeCallPeerId != null) {
      _socket?.emit('end_call', {'targetUserId': activeCallPeerId});
    } else if (currentMode == ConnectionMode.offline && activeCallPeerIp != null) {
      offlineDiscoveryService.sendLocalSignalingMessage(
        activeCallPeerIp!,
        '/end-call',
        {'callerId': userId},
      );
    }
    cleanupCall();
  }

  /// Cleanup Call & Release Resources
  void cleanupCall() {
    localStream?.getTracks().forEach((track) => track.stop());
    localStream?.dispose();
    localStream = null;

    peerConnection?.close();
    peerConnection = null;

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    activeCallPeerId = null;
    activeCallPeerIp = null;
    isAudioMuted = false;
    isVideoMuted = false;
  }

  /// Dispose All Resources
  Future<void> dispose() async {
    cleanupCall();
    localRenderer.dispose();
    remoteRenderer.dispose();
    _socket?.dispose();
    await offlineDiscoveryService.stopDiscovery();
  }
}

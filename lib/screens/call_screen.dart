import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_service.dart';

class CallScreen extends StatefulWidget {
  final WebRTCService rtcService;
  final String peerName;
  final bool isIncoming;

  const CallScreen({
    Key? key,
    required this.rtcService,
    required this.peerName,
    this.isIncoming = false,
  }) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isAudioMuted = false;
  bool _isVideoMuted = false;

  @override
  void initState() {
    super.initState();
    widget.rtcService.onCallEnded = () {
      if (mounted) {
        Navigator.pop(context);
      }
    };
  }

  void _toggleMuteAudio() {
    setState(() {
      widget.rtcService.toggleMuteAudio();
      _isAudioMuted = widget.rtcService.isAudioMuted;
    });
  }

  void _toggleMuteVideo() {
    setState(() {
      widget.rtcService.toggleVideo();
      _isVideoMuted = widget.rtcService.isVideoMuted;
    });
  }

  void _switchCamera() async {
    await widget.rtcService.switchCamera();
    setState(() {});
  }

  void _endCall() async {
    await widget.rtcService.endCall();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote Video View (Full Screen)
          Positioned.fill(
            child: RTCVideoView(
              widget.rtcService.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),

          // Local Video View (Overlay Thumbnail)
          Positioned(
            top: 50,
            right: 20,
            width: 120,
            height: 160,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24, width: 2),
                color: Colors.grey[900],
              ),
              clipBehavior: Clip.antiAlias,
              child: RTCVideoView(
                widget.rtcService.localRenderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),

          // Top Header Info
          Positioned(
            top: 50,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.peerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.rtcService.currentMode == ConnectionMode.online
                            ? Colors.green
                            : Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.rtcService.currentMode == ConnectionMode.online
                          ? 'Online Encrypted Call'
                          : 'Offline Local Wi-Fi Direct Call',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Call Controls Bar
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Audio Mute Button
                FloatingActionButton(
                  heroTag: 'audio_mute',
                  backgroundColor: _isAudioMuted ? Colors.red : Colors.grey[800],
                  onPressed: _toggleMuteAudio,
                  child: Icon(
                    _isAudioMuted ? Icons.mic_off : Icons.mic,
                    color: Colors.white,
                  ),
                ),

                // Video Toggle Button
                FloatingActionButton(
                  heroTag: 'video_mute',
                  backgroundColor: _isVideoMuted ? Colors.red : Colors.grey[800],
                  onPressed: _toggleMuteVideo,
                  child: Icon(
                    _isVideoMuted ? Icons.videocam_off : Icons.videocam,
                    color: Colors.white,
                  ),
                ),

                // Switch Camera Button
                FloatingActionButton(
                  heroTag: 'switch_camera',
                  backgroundColor: Colors.grey[800],
                  onPressed: _switchCamera,
                  child: const Icon(Icons.switch_camera, color: Colors.white),
                ),

                // End Call Button
                FloatingActionButton(
                  heroTag: 'end_call',
                  backgroundColor: Colors.redAccent,
                  onPressed: _endCall,
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

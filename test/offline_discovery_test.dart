import 'package:flutter_test/flutter_test.dart';
import 'package:dual_mode_video_call/services/offline_discovery_service.dart';

void main() {
  group('DiscoveredPeer Tests', () {
    test('FromJson creates valid peer object', () {
      final json = {
        'deviceId': 'device_123',
        'deviceName': 'Test Device',
        'signalPort': 8080,
      };

      final peer = DiscoveredPeer.fromJson(json, '192.168.1.50');

      expect(peer.deviceId, 'device_123');
      expect(peer.deviceName, 'Test Device');
      expect(peer.localIp, '192.168.1.50');
      expect(peer.signalPort, 8080);
    });

    test('ToJson generates valid map', () {
      final peer = DiscoveredPeer(
        deviceId: 'device_999',
        deviceName: 'Mobile Phone',
        localIp: '10.0.0.12',
        signalPort: 8080,
        lastSeen: DateTime.now(),
      );

      final json = peer.toJson();

      expect(json['deviceId'], 'device_999');
      expect(json['deviceName'], 'Mobile Phone');
      expect(json['localIp'], '10.0.0.12');
      expect(json['signalPort'], 8080);
    });
  });
}

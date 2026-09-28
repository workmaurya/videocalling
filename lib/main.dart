import 'dart:math';
import 'package:flutter/material.dart';
import 'services/webrtc_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final randomId = Random().nextInt(10000).toString();
  final userId = 'user_$randomId';
  final userName = 'Device_$randomId';

  final rtcService = WebRTCService(
    userId: userId,
    userName: userName,
    onlineServerUrl: 'http://localhost:3000',
  );

  await rtcService.initialize();

  runApp(MyApp(rtcService: rtcService));
}

class MyApp extends StatelessWidget {
  final WebRTCService rtcService;

  const MyApp({Key? key, required this.rtcService}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dual Mode Video Call',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: HomeScreen(rtcService: rtcService),
    );
  }
}

import 'package:flutter/services.dart';

class ConnectionForegroundService {
  const ConnectionForegroundService._();

  static const MethodChannel _channel = MethodChannel(
    'br.sp.gov.cps.dsm.chat/connection_foreground_service',
  );

  static Future<void> start() async {
    await _channel.invokeMethod<void>('start');
  }

  static Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }
}

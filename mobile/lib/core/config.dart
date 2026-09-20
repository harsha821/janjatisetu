import 'package:flutter/foundation.dart';

/// App-wide configuration.
///
/// [apiBaseUrl] points at the FastAPI backend's `/api/v1` prefix.
///   - Android emulator reaches the host machine at 10.0.2.2.
///   - iOS simulator / desktop / web reach it at localhost.
///   - A real device on the same Wi-Fi needs the machine's LAN IP.
/// Override at build/run time with:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api/v1
class AppConfig {
  AppConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) {
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
      return 'http://$host:8000/api/v1';
    }
    return 'http://10.0.2.2:8000/api/v1';
  }

  static const String appName = 'JanjatiSetu';
  static const List<String> supportedLanguages = ['en', 'hi'];
}

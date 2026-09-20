import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/storage.dart';

/// Holds who is signed in and hands out a token-bearing [ApiClient] to the
/// rest of the app. One instance lives for the whole app (see main.dart).
class Session extends ChangeNotifier {
  Session(this._store) : api = ApiClient(token: _store.token);

  final LocalStore _store;
  final ApiClient api;

  bool get isSignedIn => _store.isSignedIn;
  String? get role => _store.role;
  int? get userId => _store.userId;
  String? get fullName => _store.fullName;
  String get language => _store.language;

  bool get isStudent => role == 'STUDENT';
  bool get isStaff => role == 'VERIFIER' || role == 'ADMIN';
  bool get isAdmin => role == 'ADMIN';

  Future<void> login(String phone, String password) async {
    final r = await api.login(phone, password);
    api.token = r['access_token'] as String;
    await _store.saveSession(
      token: r['access_token'] as String,
      role: r['role'] as String,
      userId: r['user_id'] as int,
      fullName: (r['full_name'] as String?) ?? '',
      language: (r['language'] as String?) ?? 'en',
    );
    notifyListeners();
  }

  Future<void> register({required String phone, required String password, required String fullName, String? email}) async {
    final r = await api.register(phone: phone, password: password, fullName: fullName, email: email);
    api.token = r['access_token'] as String;
    await _store.saveSession(
      token: r['access_token'] as String,
      role: r['role'] as String,
      userId: r['user_id'] as int,
      fullName: (r['full_name'] as String?) ?? fullName,
      language: (r['language'] as String?) ?? 'en',
    );
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    await _store.setLanguage(lang);
    try {
      await api.setLanguage(lang);
    } catch (_) {
      // offline: the server copy will catch up next successful call
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _store.clearSession();
    api.token = null;
    notifyListeners();
  }
}

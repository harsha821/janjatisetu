import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences for the few things the app must
/// remember across launches: the auth token, the signed-in user, the chosen
/// language, and the offline outbox of queued sync operations.
///
/// Uses plain SharedPreferences (not encrypted at rest). A production build can
/// swap in flutter_secure_storage or an encrypted Hive box without changing
/// this class's API: queue while offline, replay in order, idempotent by `op_id`.
class LocalStore {
  LocalStore._(this._prefs);

  final SharedPreferences _prefs;

  static LocalStore? _instance;

  static Future<LocalStore> instance() async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    _instance = LocalStore._(prefs);
    return _instance!;
  }

  static const _kToken = 'auth_token';
  static const _kRole = 'auth_role';
  static const _kUserId = 'auth_user_id';
  static const _kFullName = 'auth_full_name';
  static const _kLanguage = 'language';
  static const _kOutbox = 'offline_outbox';
  static const _kCachedPull = 'cached_pull';

  // ------------------------------------------------------------- session
  String? get token => _prefs.getString(_kToken);
  String? get role => _prefs.getString(_kRole);
  int? get userId => _prefs.getInt(_kUserId);
  String? get fullName => _prefs.getString(_kFullName);
  String get language => _prefs.getString(_kLanguage) ?? 'en';

  Future<void> saveSession({
    required String token,
    required String role,
    required int userId,
    required String fullName,
    required String language,
  }) async {
    await _prefs.setString(_kToken, token);
    await _prefs.setString(_kRole, role);
    await _prefs.setInt(_kUserId, userId);
    await _prefs.setString(_kFullName, fullName);
    await _prefs.setString(_kLanguage, language);
  }

  Future<void> setLanguage(String lang) => _prefs.setString(_kLanguage, lang);

  Future<void> clearSession() async {
    await _prefs.remove(_kToken);
    await _prefs.remove(_kRole);
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kFullName);
    await _prefs.remove(_kOutbox);
    await _prefs.remove(_kCachedPull);
  }

  bool get isSignedIn => token != null && token!.isNotEmpty;

  // -------------------------------------------------------------- outbox
  List<Map<String, dynamic>> get outbox {
    final raw = _prefs.getString(_kOutbox);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> enqueue(Map<String, dynamic> op) async {
    final ops = outbox..add(op);
    await _prefs.setString(_kOutbox, jsonEncode(ops));
  }

  Future<void> clearOutbox() async => _prefs.remove(_kOutbox);

  Future<void> replaceOutbox(List<Map<String, dynamic>> ops) async {
    await _prefs.setString(_kOutbox, jsonEncode(ops));
  }

  // ---------------------------------------------------------- last pull
  /// Caches the last `/sync/pull` response so the app has something to show
  /// (dashboard, schemes, profile) the moment it opens offline.
  Future<void> cachePull(Map<String, dynamic> data) async {
    await _prefs.setString(_kCachedPull, jsonEncode(data));
  }

  Map<String, dynamic>? get cachedPull {
    final raw = _prefs.getString(_kCachedPull);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}

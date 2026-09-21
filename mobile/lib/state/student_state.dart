import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/api_client.dart';
import '../core/storage.dart';

String _newId(String prefix) {
  final rnd = Random();
  final suffix = List.generate(8, (_) => rnd.nextInt(36).toRadixString(36)).join();
  return '$prefix-${DateTime.now().millisecondsSinceEpoch}-$suffix';
}

/// True when the exception means "could not reach the server" (queue it),
/// as opposed to [ApiException] which means "the server answered, and said no".
bool _isNetworkFailure(Object e) => e.runtimeType.toString() == 'SocketException' || e is http.ClientException || e is TimeoutException;

/// Central store for everything the student screens show: dashboard,
/// profile, eligibility, wallet documents, notifications — plus the offline
/// outbox described in the README (queue while offline, replay in order,
/// idempotent by `op_id`).
class StudentState extends ChangeNotifier {
  StudentState(this.api, this.store) {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && store.outbox.isNotEmpty) {
        flushOutbox();
      }
    });
  }

  final ApiClient api;
  final LocalStore store;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  Map<String, dynamic>? dashboard;
  Map<String, dynamic>? profileData;
  List<dynamic> eligibility = [];
  List<dynamic> documents = [];
  List<dynamic> notifications = [];
  List<dynamic> schemes = [];
  List<dynamic> consents = [];

  bool loading = false;
  bool offline = false;
  String? error;

  int get pendingSyncCount => store.outbox.length;
  int get unreadCount => notifications.where((n) => n['is_read'] == false).length;

  // ------------------------------------------------------------- loading
  Future<void> loadAll() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final pull = await api.syncPull();
      offline = false;
      profileData = pull['profile'] as Map<String, dynamic>?;
      eligibility = (pull['eligibility'] as List?) ?? [];
      schemes = (pull['schemes'] as List?) ?? [];
      documents = (pull['documents'] as List?) ?? [];
      notifications = (pull['notifications'] as List?) ?? [];
      await store.cachePull(pull);
      try {
        dashboard = await api.getDashboard();
      } catch (_) {
        dashboard = _dashboardFromPull(pull);
      }
      try {
        consents = await api.getConsents();
      } catch (_) {
        consents = [];
      }
    } catch (e) {
      if (_isNetworkFailure(e)) {
        offline = true;
        final cached = store.cachedPull;
        if (cached != null) {
          profileData = cached['profile'] as Map<String, dynamic>?;
          eligibility = (cached['eligibility'] as List?) ?? [];
          schemes = (cached['schemes'] as List?) ?? [];
          documents = (cached['documents'] as List?) ?? [];
          notifications = (cached['notifications'] as List?) ?? [];
          dashboard = _dashboardFromPull(cached);
        } else {
          error = 'No internet connection yet, and nothing saved on this device.';
        }
      } else {
        error = '$e';
      }
    }
    loading = false;
    notifyListeners();
  }

  Map<String, dynamic> _dashboardFromPull(Map<String, dynamic> pull) {
    final apps = (pull['applications'] as List?) ?? [];
    return {
      'student': {'name': profileData?['full_name'] ?? '', 'verification': profileData?['verification_status'],
        'profile_percent': profileData?['completeness'] ?? 0},
      'applications': apps,
      'next_step': null,
      'totals': {'sanctioned': 0, 'paid': 0},
      'unread_notifications': notifications.where((n) => n['is_read'] == false).length,
    };
  }

  Future<void> refreshDashboard() async {
    try {
      dashboard = await api.getDashboard();
      notifyListeners();
    } catch (_) {/* keep showing what we have */}
  }

  Future<void> refreshEligibility() async {
    try {
      eligibility = await api.getEligibility();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshDocuments() async {
    try {
      documents = await api.walletDocuments();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshNotifications() async {
    try {
      notifications = await api.notifications();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshProfile() async {
    try {
      profileData = await api.getProfile();
      notifyListeners();
    } catch (_) {}
  }

  // -------------------------------------------------------- offline queue
  /// Runs [onlineCall] now; if the device is offline, queues [op] (with a
  /// fresh `op_id`) for later instead of failing the user's action outright.
  /// Returns true if it ran online immediately, false if it was queued.
  Future<bool> runOrQueue({
    required String type,
    int? applicationId,
    String? clientUuid,
    required Map<String, dynamic> payload,
    required Future<void> Function() onlineCall,
  }) async {
    try {
      await onlineCall();
      return true;
    } catch (e) {
      if (_isNetworkFailure(e)) {
        await store.enqueue({
          'op_id': _newId('op'),
          'type': type,
          if (applicationId != null) 'application_id': applicationId,
          if (clientUuid != null) 'client_uuid': clientUuid,
          'payload': payload,
        });
        notifyListeners();
        return false;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> flushOutbox() async {
    final ops = store.outbox;
    if (ops.isEmpty) return {'results': []};
    try {
      final result = await api.syncPush(ops.cast<Map<String, dynamic>>());
      await store.clearOutbox();
      await loadAll();
      return result;
    } catch (e) {
      if (_isNetworkFailure(e)) return {'results': [], 'offline': true};
      rethrow;
    }
  }

  String newClientUuid() => _newId('app');

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}

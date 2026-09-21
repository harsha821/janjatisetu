import 'dart:convert';


import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, [this.detail]);

  final int statusCode;
  final String message;
  final dynamic detail;

  @override
  String toString() => message;
}

/// Thin REST client for the JanjatiSetu FastAPI backend.
///
/// Every method throws [ApiException] on a non-2xx response, with `detail`
/// carrying whatever structured body the backend sent (see
/// docs/API_REFERENCE.md — some endpoints return `{"detail": {...}}`).
class ApiClient {
  ApiClient({this.token});

  String? token;
  final http.Client _http = http.Client();

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final full = base.replace(
      path: base.path + path,
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );
    return full;
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _decode(http.Response r) async {
    dynamic body;
    try {
      body = r.body.isNotEmpty ? jsonDecode(r.body) : null;
    } catch (_) {
      body = r.body;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    String message = 'Request failed (${r.statusCode})';
    dynamic detail = body;
    if (body is Map && body['detail'] != null) {
      detail = body['detail'];
      message = detail is String ? detail : (detail is Map && detail['message'] != null ? '${detail['message']}' : message);
    }
    throw ApiException(r.statusCode, message, detail);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final r = await _http.get(_uri(path, query), headers: _headers);
    return _decode(r);
  }

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) async {
    final r = await _http.post(_uri(path, query),
        headers: {..._headers, 'Content-Type': 'application/json'}, body: body == null ? null : jsonEncode(body));
    return _decode(r);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final r = await _http.put(_uri(path), headers: {..._headers, 'Content-Type': 'application/json'},
        body: body == null ? null : jsonEncode(body));
    return _decode(r);
  }

  Future<dynamic> delete(String path) async {
    final r = await _http.delete(_uri(path), headers: _headers);
    return _decode(r);
  }

  Future<dynamic> postForm(String path, Map<String, String> fields) async {
    final r = await _http.post(_uri(path), headers: _headers, body: fields);
    return _decode(r);
  }

  Future<dynamic> uploadFile(String path, {required String fieldName, required String filename, required List<int> bytes, required Map<String, String> fields}) async {
    final req = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers)
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes(fieldName, bytes, filename: filename));
    final streamed = await _http.send(req);
    final r = await http.Response.fromStream(streamed);
    return _decode(r);
  }

  // ---------------------------------------------------------------- auth
  Future<Map<String, dynamic>> login(String phone, String password) async {
    final r = await postForm('/auth/login', {'username': phone, 'password': password});
    return r as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register({
    required String phone,
    required String password,
    required String fullName,
    String? email,
    String language = 'en',
  }) async {
    final r = await post('/auth/register', body: {
      'phone': phone,
      'password': password,
      'full_name': fullName,
      if (email != null && email.isNotEmpty) 'email': email,
      'language': language,
    });
    return r as Map<String, dynamic>;
  }

  // ------------------------------------------------------------- profile
  Future<Map<String, dynamic>> getProfile() async => (await get('/profile')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) async =>
      (await put('/profile', body: body)) as Map<String, dynamic>;

  Future<List<dynamic>> getConsents() async => (await get('/profile/consents')) as List<dynamic>;

  Future<void> setConsent(String purpose, bool granted) async =>
      put('/profile/consents', body: {'purpose': purpose, 'granted': granted});

  Future<Map<String, dynamic>> verifyProfile() async => (await post('/profile/verify')) as Map<String, dynamic>;

  Future<void> setLanguage(String lang) async => put('/profile/language', body: {'language': lang});

  // --------------------------------------------------------- eligibility
  Future<List<dynamic>> getEligibility() async => (await get('/eligibility')) as List<dynamic>;

  Future<Map<String, dynamic>> getDashboard() async => (await get('/dashboard')) as Map<String, dynamic>;

  // ------------------------------------------------------------- wallet
  Future<List<dynamic>> digilockerDocuments() async => (await get('/wallet/digilocker')) as List<dynamic>;

  /// Returns ``{sandbox_configured, auth_url?, already_connected}``.
  /// Open ``auth_url`` in a browser to start the DigiLocker OAuth2 flow.
  Future<Map<String, dynamic>> digilockerConnect() async =>
      (await get('/wallet/digilocker/connect')) as Map<String, dynamic>;

  /// Returns ``{sandbox_configured, connected, expiry?}``.
  Future<Map<String, dynamic>> digilockerStatus() async =>
      (await get('/wallet/digilocker/status')) as Map<String, dynamic>;

  /// Clears the stored DigiLocker token for the current user.
  Future<void> digilockerDisconnect() async => delete('/wallet/digilocker/disconnect');

  Future<Map<String, dynamic>> importDigilockerDoc(String uri) async =>
      (await post('/wallet/import', body: {'uri': uri})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> fetchCustomDigilockerDoc({
    required String docType,
    required String docNumber,
    String? issuer,
  }) async =>
      (await post('/wallet/digilocker/fetch_custom', body: {
        'doc_type': docType,
        'doc_number': docNumber,
        if (issuer != null && issuer.isNotEmpty) 'issuer': issuer,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> uploadDocument(String docType, String filename, List<int> bytes) async =>
      (await uploadFile('/wallet/upload', fieldName: 'file', filename: filename, bytes: bytes, fields: {'doc_type': docType})) as Map<String, dynamic>;

  Future<List<dynamic>> walletDocuments() async => (await get('/wallet/documents')) as List<dynamic>;

  Future<void> deleteDocument(int id) async => delete('/wallet/documents/$id');

  Future<Map<String, dynamic>> useDocumentInApplication(int docId, int applicationId) async =>
      (await post('/wallet/documents/$docId/use', body: {'application_id': applicationId})) as Map<String, dynamic>;

  // -------------------------------------------------------- applications
  String getReceiptUrl(int id) {
    var u = _uri('/applications/$id/receipt.pdf', token != null ? {'token': token} : null);
    if (u.host == 'localhost') {
      u = u.replace(host: '127.0.0.1');
    }
    return u.toString();
  }

  Future<Map<String, dynamic>> createApplication(String schemeCode, {String academicYear = '2026-27', String? clientUuid}) async =>
      (await post('/applications', body: {
        'scheme_code': schemeCode,
        'academic_year': academicYear,
        if (clientUuid != null) 'client_uuid': clientUuid,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> getApplication(int id) async => (await get('/applications/$id')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateApplication(int id, {Map<String, dynamic>? formData, List<int>? documentIds}) async =>
      (await put('/applications/$id', body: {
        if (formData != null) 'form_data': formData,
        if (documentIds != null) 'document_ids': documentIds,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> autofillApplication(int id) async =>
      (await post('/applications/$id/autofill', body: {})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> submitApplication(int id) async => (await post('/applications/$id/submit')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> resolveDeficiency(int appId, int defId, String note, {int? documentId}) async =>
      (await post('/applications/$appId/deficiencies/$defId/resolve',
          body: {'note': note, if (documentId != null) 'document_id': documentId})) as Map<String, dynamic>;

  /// Returns the scheme-aware verification step list for an existing application,
  /// with each step enriched with ``status``, ``document_id``, and ``source_check``.
  Future<Map<String, dynamic>> getVerificationChecklist(int appId) async =>
      (await get('/applications/$appId/verification-checklist')) as Map<String, dynamic>;

  /// Standalone (no application required). Returns the raw verification step list
  /// for a (scheme_code, course_level, semester) combination.
  Future<Map<String, dynamic>> getVerificationRequirements({
    required String schemeCode,
    required String courseLevel,
    int? semester,
  }) async =>
      (await get('/verification-requirements', query: {
        'scheme_code': schemeCode,
        'course_level': courseLevel,
        if (semester != null) 'semester': semester,
      })) as Map<String, dynamic>;

  // ------------------------------------------------------------- notify
  Future<List<dynamic>> notifications({bool unreadOnly = false}) async =>
      (await get('/notifications', query: {'unread_only': unreadOnly})) as List<dynamic>;

  Future<void> markNotificationRead(int id) async => post('/notifications/$id/read');

  Future<void> markAllRead() async => post('/notifications/read-all');

  // ----------------------------------------------------------- assistant
  Future<Map<String, dynamic>> chat(String message) async =>
      (await post('/assistant/chat', body: {'message': message})) as Map<String, dynamic>;

  // ---------------------------------------------------------------- sync
  Future<Map<String, dynamic>> syncPush(List<Map<String, dynamic>> operations) async =>
      (await post('/sync/push', body: {'operations': operations})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> syncPull({DateTime? since}) async =>
      (await get('/sync/pull', query: since == null ? null : {'since': since.toIso8601String()})) as Map<String, dynamic>;

  // ------------------------------------------------------------- admin
  Future<Map<String, dynamic>> adminOverview() async => (await get('/admin/overview')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> adminApplications({String? status, String? scheme, String? district, String? q, int limit = 50, int offset = 0}) async =>
      (await get('/admin/applications', query: {
        if (status != null) 'status': status,
        if (scheme != null) 'scheme': scheme,
        if (district != null) 'district': district,
        if (q != null && q.isNotEmpty) 'q': q,
        'limit': limit,
        'offset': offset,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> adminApplicationDetail(int id) async =>
      (await get('/admin/applications/$id')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> adminAction(int id, String action, {String? note, String? docType, double? amount, String? utr}) async =>
      (await post('/admin/applications/$id/action', body: {
        'action': action,
        if (note != null) 'note': note,
        if (docType != null) 'doc_type': docType,
        if (amount != null) 'amount': amount,
        if (utr != null) 'utr': utr,
      })) as Map<String, dynamic>;

  Future<List<dynamic>> adminExceptions({String status = 'OPEN', String? kind}) async =>
      (await get('/admin/exceptions', query: {'status': status, if (kind != null) 'kind': kind})) as List<dynamic>;

  Future<Map<String, dynamic>> resolveException(int id, String resolution, {String? note}) async =>
      (await post('/admin/exceptions/$id/resolve', body: {'resolution': resolution, if (note != null) 'note': note}))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> runCoverageGap() async => (await post('/admin/coverage-gap/run')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> coverageGapSummary() async => (await get('/admin/coverage-gap/summary')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> coverageGapList({String? state, String? district, int limit = 100, int offset = 0}) async =>
      (await get('/admin/coverage-gap', query: {
        if (state != null) 'state': state,
        if (district != null) 'district': district,
        'limit': limit,
        'offset': offset,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> sendOutreach(List<int> gapIds, String channel, {String? message}) async =>
      (await post('/admin/coverage-gap/outreach',
          body: {'gap_ids': gapIds, 'channel': channel, if (message != null) 'message': message})) as Map<String, dynamic>;

  /// Reviewer closes or reopens a coverage gap. [action] is DISMISS (note required), MARK_APPLIED or REOPEN.
  Future<Map<String, dynamic>> resolveGap(int id, String action, {String? note}) async =>
      (await post('/admin/coverage-gap/$id/resolve',
          body: {'action': action, if (note != null && note.isNotEmpty) 'note': note})) as Map<String, dynamic>;

  Future<List<dynamic>> auditLog({int limit = 100}) async => (await get('/admin/audit', query: {'limit': limit})) as List<dynamic>;
}

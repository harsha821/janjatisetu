import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../state/student_state.dart';
import '../../widgets/bridge_progress.dart';
import '../../widgets/common.dart';
import 'wallet_screen.dart';

class ApplicationScreen extends StatefulWidget {
  const ApplicationScreen({super.key, required this.applicationId});

  final int applicationId;

  @override
  State<ApplicationScreen> createState() => _ApplicationScreenState();
}

class _ApplicationScreenState extends State<ApplicationScreen> {
  Map<String, dynamic>? app;
  Map<String, dynamic>? scheme;
  bool loading = true;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final state = context.read<StudentState>();
    try {
      final data = await state.api.getApplication(widget.applicationId);
      setState(() {
        app = data;
        scheme = state.schemes.cast<Map<String, dynamic>>().firstWhere(
            (s) => s['code'] == data['scheme_code'],
            orElse: () => {'code': data['scheme_code'], 'short_name': data['short_name'], 'documents': const []});
        loading = false;
        error = null;
      });
    } catch (e) {
      setState(() {
        loading = false;
        error = 'Could not load this application. ${e is ApiException ? e.message : "Check your connection."}';
      });
    }
  }

  List<String> get _requiredDocs => ((scheme?['documents'] as List?) ?? []).cast<String>();
  List<String> get _attachedTypes {
    final ids = ((app?['document_ids'] as List?) ?? []).cast<int>().toSet();
    final wallet = context.read<StudentState>().documents.cast<Map<String, dynamic>>();
    return wallet.where((d) => ids.contains(d['id'])).map((d) => d['doc_type'] as String).toList();
  }

  Future<void> _attachDoc(String docType) async {
    final wallet = context.read<StudentState>();
    final chosen = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => WalletScreen(pickDocType: docType)),
    );
    if (chosen == null) return;
    setState(() => busy = true);
    try {
      await wallet.api.useDocumentInApplication(chosen, widget.applicationId);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() => busy = true);
    final state = context.read<StudentState>();
    try {
      await state.api.submitApplication(widget.applicationId);
      await state.refreshDashboard();
      await _load();
      if (mounted) {
        final url = Uri.parse(state.api.getReceiptUrl(widget.applicationId));
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Application Submitted'),
            content: Text('Your Application ID is JS-APP-${widget.applicationId}'),
            actions: [
              TextButton(
                onPressed: () => launchUrl(url),
                child: const Text('Download PDF'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } on ApiException catch (e) {
      final detail = e.detail;
      String msg = e.message;
      if (detail is Map && detail['missing_documents'] != null) {
        msg = 'Attach: ${(detail['missing_documents'] as List).join(', ')}';
      } else if (detail is Map && detail['reason'] != null) {
        msg = '${detail['reason']}';
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      // offline: queue the submission
      final ok = await state.runOrQueue(
        type: 'SUBMIT_APPLICATION',
        applicationId: widget.applicationId,
        payload: const {},
        onlineCall: () async => state.api.submitApplication(widget.applicationId),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Submitted' : 'No connection — queued to submit once you are back online')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resolveDeficiency(Map<String, dynamic> deficiency) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit correction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${deficiency['message']}'),
            const SizedBox(height: 12),
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'What did you fix?'), maxLines: 3),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Submit')),
        ],
      ),
    );
    if (note == null || note.isEmpty) return;
    setState(() => busy = true);
    final state = context.read<StudentState>();
    try {
      await state.api.resolveDeficiency(widget.applicationId, deficiency['id'] as int, note);
      await state.refreshDashboard();
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _autoAttachAll() async {
    final state = context.read<StudentState>();
    final wallet = state.documents.cast<Map<String, dynamic>>();
    final attached = _attachedTypes;
    final missing = _requiredDocs.where((d) => !attached.contains(d)).toList();

    setState(() => busy = true);
    int count = 0;
    try {
      for (final docType in missing) {
        final found = wallet.firstWhere(
          (d) => d['doc_type'] == docType,
          orElse: () => const {},
        );
        if (found.isNotEmpty && found['id'] != null) {
          await state.api.useDocumentInApplication(found['id'] as int, widget.applicationId);
          count++;
        }
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(count > 0 ? '✓ Auto-attached $count document(s) from Wallet' : 'Attach documents from your DigiLocker Wallet or device'),
          backgroundColor: count > 0 ? AppColors.success : null,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not auto-attach: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _handleSubmitWithCheck(List<String> missing) async {
    if (missing.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100)),
              SizedBox(width: 8),
              Text('Pending Documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The following documents are not yet attached:'),
              const SizedBox(height: 10),
              ...missing.map((d) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 6, color: AppColors.danger),
                        const SizedBox(width: 8),
                        Expanded(child: Text(d.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      ],
                    ),
                  )),
              const SizedBox(height: 14),
              const Text('Would you like to submit the application now? Verification officers will review available records.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Attach First'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002970), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit Application'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    await _submit();
  }

  Widget _buildBottomBar(Strings s) {
    final attached = _attachedTypes;
    final missing = _requiredDocs.where((d) => !attached.contains(d)).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
        border: const Border(top: BorderSide(color: Color(0xFFE2EEF8))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        missing.isEmpty ? Icons.check_circle : Icons.pending_outlined,
                        color: missing.isEmpty ? AppColors.success : const Color(0xFFE65100),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        missing.isEmpty ? 'All Docs Ready' : '${missing.length} Missing',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: missing.isEmpty ? AppColors.success : const Color(0xFFE65100),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    missing.isEmpty ? 'Ready for verification' : 'Tap submit to proceed',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: busy ? null : () => _handleSubmitWithCheck(missing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF002970),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  busy ? 'Submitting...' : 'Submit Application',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = Strings(session.language);

    return Scaffold(
      appBar: AppBar(title: Text('${scheme?['short_name'] ?? app?['short_name'] ?? 'Application'}')),
      body: loading
          ? const LoadingView()
          : error != null
              ? ErrorView(message: error!, onRetry: _load)
              : _body(s),
    );
  }

  Widget _body(Strings s) {
    final a = app!;
    final status = a['status'] as String;
    final timeline = (a['timeline'] as List?) ?? [];
    final events = (a['events'] as List?) ?? [];
    final openDefs = ((a['deficiencies'] as List?) ?? []).where((d) => d['resolved'] == false).toList();
    final attached = _attachedTypes;
    final missing = _requiredDocs.where((d) => !attached.contains(d)).toList();
    final editable = status == 'DRAFT' || status == 'DEFICIENCY';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [StatusChip(label: s.statusLabel(status), status: status), if (a['auto_verified'] == true) const Padding(padding: EdgeInsets.only(left: 8), child: Chip(label: Text('Auto-Verified', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: AppColors.success, visualDensity: VisualDensity.compact)), const Spacer(), Text('v${a['version']}', style: const TextStyle(color: Colors.grey, fontSize: 12))]),
          const SizedBox(height: 16),
          if (a['verification_report'] != null && status != 'DRAFT' && status != 'SUBMITTED' && status != 'DEFICIENCY') ...[
            _VerificationStatusCard(report: a['verification_report'], autoVerified: a['auto_verified'] == true),
            const SizedBox(height: 16),
          ],
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.timeline, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                BridgeProgress(timeline: timeline, stageLabel: s.stageLabel),
              ],
            ),
          ),
          if (openDefs.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...openDefs.map((d) => Card(
                  color: AppColors.danger.withValues(alpha: 0.06),
                  child: ListTile(
                    leading: const Icon(Icons.error_outline, color: AppColors.danger),
                    title: Text('${d['message']}'),
                    trailing: ElevatedButton(onPressed: busy ? null : () => _resolveDeficiency(d as Map<String, dynamic>), child: Text(s.resolveCorrection)),
                  ),
                )),
          ],
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(s.requiredDocuments, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (missing.isNotEmpty && editable)
                      TextButton.icon(
                        onPressed: busy ? null : _autoAttachAll,
                        icon: const Icon(Icons.auto_fix_high, size: 14),
                        label: const Text('Auto-Attach All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF002970),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_requiredDocs.isEmpty) const Text('No documents required for this scheme.', style: TextStyle(color: Colors.grey)),
                ..._requiredDocs.map((d) {
                  final ok = attached.contains(d);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? AppColors.success : Colors.grey),
                    title: Text(d.replaceAll('_', ' ')),
                    trailing: ok || !editable
                        ? (ok ? Text(s.attached, style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold)) : null)
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF002970),
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            ),
                            onPressed: busy ? null : () => _attachDoc(d),
                            child: Text(s.attach, style: const TextStyle(fontSize: 12)),
                          ),
                  );
                }),
              ],
            ),
          ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('History', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...events.reversed.take(10).map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.circle, size: 6)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.statusLabel(e['status'] as String), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  if (e['note'] != null) Text('${e['note']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],
          if (status == 'DRAFT' || status == 'DEFICIENCY') ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2EEF8)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        missing.isEmpty ? Icons.check_circle : Icons.info_outline,
                        color: missing.isEmpty ? AppColors.success : const Color(0xFFE65100),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          missing.isEmpty
                              ? 'All required documents attached'
                              : '${missing.length} document${missing.length > 1 ? "s" : ""} pending attachment',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: missing.isEmpty ? AppColors.success : const Color(0xFFE65100),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: busy ? null : () => _handleSubmitWithCheck(missing),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF002970),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      busy ? 'Submitting...' : 'Submit Application',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _VerificationStatusCard extends StatelessWidget {
  const _VerificationStatusCard({required this.report, required this.autoVerified});

  final Map<String, dynamic> report;
  final bool autoVerified;

  @override
  Widget build(BuildContext context) {
    final checks = (report['checks'] as List?) ?? [];
    final confidence = report['confidence'] as num?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: autoVerified ? AppColors.success.withValues(alpha: 0.08) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: autoVerified ? AppColors.success.withValues(alpha: 0.3) : const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                autoVerified ? Icons.check_circle : Icons.search_rounded,
                color: autoVerified ? AppColors.success : const Color(0xFFEA580C),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  autoVerified ? 'Auto-Verified by System' : 'Queued for Manual Officer Verification',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: autoVerified ? AppColors.success : const Color(0xFF9A3412),
                  ),
                ),
              ),
              if (confidence != null)
                Text(
                  '${(confidence * 100).toStringAsFixed(0)}% Match',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: autoVerified ? AppColors.success : const Color(0xFF9A3412),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: checks.map((c) {
              final status = c['status'] as String;
              final isMatch = status == 'MATCH';
              final isReview = status == 'REVIEW';
              final color = isMatch ? AppColors.success : (isReview ? const Color(0xFFF59E0B) : AppColors.danger);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMatch ? Icons.check : (isReview ? Icons.search : Icons.close),
                      size: 12,
                      color: color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      c['source'],
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          if (!autoVerified) ...[
            const SizedBox(height: 12),
            const Text(
              'No action is needed unless an officer requests clarification. Multi-source matching requires manual review for some items.',
              style: TextStyle(fontSize: 12, color: Color(0xFF9A3412)),
            ),
          ],
        ],
      ),
    );
  }
}

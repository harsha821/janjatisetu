import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../widgets/bridge_progress.dart';
import '../../widgets/common.dart';

const _stageLabels = {
  'APPLICATION': 'Application', 'VERIFICATION': 'Verification', 'DEFICIENCY': 'Correction',
  'SANCTION': 'Sanction', 'DBT': 'Payment',
};

class AdminApplicationDetailScreen extends StatefulWidget {
  const AdminApplicationDetailScreen({super.key, required this.applicationId});

  final int applicationId;

  @override
  State<AdminApplicationDetailScreen> createState() => _AdminApplicationDetailScreenState();
}

class _AdminApplicationDetailScreenState extends State<AdminApplicationDetailScreen> {
  Map<String, dynamic>? data;
  bool loading = true;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await context.read<Session>().api.adminApplicationDetail(widget.applicationId);
      setState(() => data = d);
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _act(String action, {String? note, String? docType, double? amount, String? utr}) async {
    setState(() => busy = true);
    try {
      await context.read<Session>().api.adminAction(widget.applicationId, action, note: note, docType: docType, amount: amount, utr: utr);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Done')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resolveCase(int caseId) async {
    final resolution = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Resolve case'),
        children: [
          for (final r in ['CONFIRMED_OK', 'CORRECTED', 'DISMISS', 'ESCALATE'])
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, r), child: Text(r.replaceAll('_', ' '))),
        ],
      ),
    );
    if (resolution == null) return;
    setState(() => busy = true);
    try {
      await context.read<Session>().api.resolveException(caseId, resolution);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _promptNote(String action, String title) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Note'), maxLines: 3, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Confirm')),
        ],
      ),
    );
    if (note == null) return;
    if (action == 'REJECT' && note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason is required to reject')));
      return;
    }
    _act(action, note: note.isEmpty ? null : note);
  }

  Future<void> _promptSanction() async {
    final controller = TextEditingController();
    final noteController = TextEditingController();
    final amount = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sanction amount'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (\u20b9)')),
          TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Sanction')),
        ],
      ),
    );
    final value = double.tryParse(amount ?? '');
    if (value == null) return;
    _act('SANCTION', amount: value, note: noteController.text.trim().isEmpty ? null : noteController.text.trim());
  }

  Future<void> _promptPay() async {
    final amountCtrl = TextEditingController();
    final utrCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record DBT payment'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (\u20b9)')),
          TextField(controller: utrCtrl, decoration: const InputDecoration(labelText: 'UTR / payment reference')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm payment')),
        ],
      ),
    );
    if (ok != true) return;
    final value = double.tryParse(amountCtrl.text.trim());
    if (value == null || utrCtrl.text.trim().isEmpty) return;
    _act('PAY', amount: value, utr: utrCtrl.text.trim());
  }

  Future<void> _promptDeficiency() async {
    final noteCtrl = TextEditingController();
    String? docType;
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: const Text('Raise a correction'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'What must the student fix?'), maxLines: 3),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: docType,
              decoration: const InputDecoration(labelText: 'Related document (optional)'),
              items: const ['CASTE_CERT', 'INCOME_CERT', 'MARKSHEET', 'BANK_PASSBOOK', 'ADMISSION_LETTER', 'NET_JRF_CERT']
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) => setS(() => docType = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, {'note': noteCtrl.text.trim(), 'doc_type': docType}), child: const Text('Raise')),
          ],
        );
      }),
    );
    if (result == null || (result['note'] ?? '').isEmpty) return;
    _act('RAISE_DEFICIENCY', note: result['note'], docType: result['doc_type']);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Application review')),
      body: loading
          ? const LoadingView()
          : error != null
              ? ErrorView(message: error!, onRetry: _load)
              : _body(),
    );
  }

  Widget _body() {
    final d = data!;
    final app = d['application'] as Map<String, dynamic>;
    final student = d['student'] as Map<String, dynamic>;
    final documents = (d['documents'] as List?) ?? [];
    final cases = ((d['cases'] as List?) ?? []).cast<Map<String, dynamic>>();
    final openCases = cases.where((c) => c['status'] == 'OPEN' || c['status'] == 'ESCALATED').toList();
    final status = app['status'] as String;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: Text('${app['short_name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            StatusChip(label: status, status: status),
          ]),
          Text('${student['tribe_name'] ?? ''} \u00b7 ${student['district'] ?? ''}, ${student['state'] ?? ''}', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          SectionCard(child: BridgeProgress(timeline: (app['timeline'] as List?) ?? [], stageLabel: (s) => _stageLabels[s] ?? s)),
          const SizedBox(height: 12),
          if (openCases.isNotEmpty) ...[
            const Text('Open review cases', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ...openCases.map((c) => Card(
                  color: AppColors.danger.withOpacity(0.06),
                  child: ListTile(
                    leading: SeverityChip(severity: c['severity'] as String),
                    title: Text('${c['title']}'),
                    subtitle: Text('${c['kind']}'),
                    trailing: TextButton(onPressed: busy ? null : () => _resolveCase(c['id'] as int), child: const Text('Resolve')),
                  ),
                )),
            const SizedBox(height: 12),
          ],
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Student', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Category: ${student['category'] ?? '-'}   Course: ${student['course_level'] ?? '-'}'),
                Text('Income: \u20b9${student['annual_family_income'] ?? '-'}'),
                Text('Verification: ${student['verification_status'] ?? 'NOT_VERIFIED'}'
                    '${student['verification_confidence'] != null ? ' (${((student['verification_confidence'] as num) * 100).toStringAsFixed(0)}%)' : ''}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Documents', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (documents.isEmpty) const Text('No documents attached.', style: TextStyle(color: Colors.grey)),
                ...documents.map((doc) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Icon(doc['verified'] == true ? Icons.verified_outlined : Icons.description_outlined, size: 18,
                            color: doc['verified'] == true ? AppColors.success : Colors.grey),
                        const SizedBox(width: 8),
                        Text('${doc['doc_type']}'),
                      ]),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'SUBMITTED')
                ElevatedButton(onPressed: busy ? null : () => _act('START_REVIEW'), child: const Text('Start review')),
              if (status == 'UNDER_VERIFICATION' || status == 'SUBMITTED') ...[
                OutlinedButton(onPressed: busy ? null : _promptDeficiency, child: const Text('Raise correction')),
                ElevatedButton(
                  onPressed: busy || openCases.isNotEmpty ? null : () => _act('VERIFY'),
                  child: Text(openCases.isNotEmpty ? 'Resolve cases to verify' : 'Verify'),
                ),
              ],
              if (status == 'VERIFIED')
                ElevatedButton(onPressed: busy ? null : _promptSanction, child: const Text('Sanction')),
              if (status == 'SANCTIONED')
                ElevatedButton(onPressed: busy ? null : _promptPay, child: const Text('Record DBT payment')),
              if (app['portal_sync'] == 'PENDING_PUSH')
                OutlinedButton(onPressed: busy ? null : () => _act('RETRY_PUSH'), child: const Text('Retry portal push')),
              if (status != 'REJECTED' && status != 'DBT_PAID')
                TextButton(
                  onPressed: busy ? null : () => _promptNote('REJECT', 'Reject application'),
                  child: const Text('Reject', style: TextStyle(color: AppColors.danger)),
                ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../state/student_state.dart';
import '../../widgets/common.dart';
import 'profile_screen.dart';
import 'verification_screen.dart';
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
  Map<String, dynamic>? _checklistSummary;
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
      // Load application + checklist summary in parallel
      final results = await Future.wait([
        state.api.getApplication(widget.applicationId),
        state.api.getVerificationChecklist(widget.applicationId).catchError((_) => <String, dynamic>{}),
      ]);
      final data = results[0];
      final checklist = results[1];
      if (!mounted) return;
      setState(() {
        app = data;
        _checklistSummary = checklist.isNotEmpty ? checklist : null;
        scheme = state.schemes.cast<Map<String, dynamic>>().firstWhere(
            (s) => s['code'] == data['scheme_code'],
            orElse: () => {'code': data['scheme_code'], 'short_name': data['short_name'], 'documents': const []});
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
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

  Future<void> _syncFromProfile() async {
    setState(() => busy = true);
    final state = context.read<StudentState>();
    try {
      final updated = await state.api.autofillApplication(widget.applicationId);
      await state.refreshDashboard();
      if (!mounted) return;
      setState(() {
        app = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Profile details synchronized and auto-filled according to scheme!'),
          backgroundColor: AppColors.success,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not sync profile: $e')));
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

  Future<void> _openEditDetailsModal(Map<String, dynamic> form) async {
    final state = context.read<StudentState>();
    final courseCtrl = TextEditingController(text: '${form['course_name'] ?? ''}');
    final instNameCtrl = TextEditingController(text: '${form['institution_name'] ?? ''}');
    final instCodeCtrl = TextEditingController(text: '${form['institution_code'] ?? ''}');
    final incomeCtrl = TextEditingController(text: form['annual_family_income'] != null ? '${form['annual_family_income']}' : '');
    final pctCtrl = TextEditingController(text: form['last_exam_percentage'] != null ? '${form['last_exam_percentage']}' : '');
    final semCtrl = TextEditingController(text: form['semester'] != null ? '${form['semester']}' : '');
    final ifscCtrl = TextEditingController(text: '${form['ifsc'] ?? ''}');

    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Edit Application Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const Text('Update details specific to this scholarship draft:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(controller: courseCtrl, decoration: const InputDecoration(labelText: 'Course Name (e.g. Class X, B.Sc)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: instNameCtrl, decoration: const InputDecoration(labelText: 'Institution / School / College Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: instCodeCtrl, decoration: const InputDecoration(labelText: 'Institution Code', border: OutlineInputBorder()))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: semCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Semester/Year', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: incomeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Family Income (₹)', border: OutlineInputBorder()))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: pctCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Last Exam Marks (%)', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 12),
              TextField(controller: ifscCtrl, decoration: const InputDecoration(labelText: 'Bank IFSC Code', border: OutlineInputBorder())),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002970), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () {
                    final data = Map<String, dynamic>.from(form);
                    if (courseCtrl.text.trim().isNotEmpty) data['course_name'] = courseCtrl.text.trim();
                    if (instNameCtrl.text.trim().isNotEmpty) data['institution_name'] = instNameCtrl.text.trim();
                    if (instCodeCtrl.text.trim().isNotEmpty) data['institution_code'] = instCodeCtrl.text.trim();
                    if (incomeCtrl.text.trim().isNotEmpty) data['annual_family_income'] = int.tryParse(incomeCtrl.text.trim());
                    if (pctCtrl.text.trim().isNotEmpty) data['last_exam_percentage'] = double.tryParse(pctCtrl.text.trim());
                    if (semCtrl.text.trim().isNotEmpty) data['semester'] = int.tryParse(semCtrl.text.trim());
                    if (ifscCtrl.text.trim().isNotEmpty) data['ifsc'] = ifscCtrl.text.trim().toUpperCase();
                    Navigator.pop(ctx, data);
                  },
                  child: const Text('Save to Application Draft', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );

    if (updated != null) {
      setState(() => busy = true);
      try {
        await state.api.updateApplication(widget.applicationId, formData: updated);
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Application details updated successfully!'), backgroundColor: AppColors.success));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save details: $e')));
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
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
      appBar: AppBar(
        title: Text('${scheme?['short_name'] ?? app?['short_name'] ?? 'Application'}'),
        actions: [
          if (app?['status'] == 'DRAFT')
            IconButton(
              icon: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.sync_rounded),
              tooltip: 'Re-sync Profile & Autofill',
              onPressed: busy ? null : _syncFromProfile,
            ),
        ],
      ),
      body: loading
          ? const LoadingView()
          : error != null
              ? ErrorView(message: error!, onRetry: _load)
              : _body(s),
      bottomNavigationBar: (loading || error != null || app?['status'] != 'DRAFT') ? null : _buildBottomBar(s),
    );
  }

  Widget _body(Strings s) {
    final a = app!;
    final status = a['status'] as String;
    final events = (a['events'] as List?) ?? [];
    final openDefs = ((a['deficiencies'] as List?) ?? []).where((d) => d['resolved'] == false).toList();
    final attached = _attachedTypes;
    final missing = _requiredDocs.where((d) => !attached.contains(d)).toList();
    final editable = status == 'DRAFT' || status == 'DEFICIENCY';
    final formData = (a['form_data'] as Map<String, dynamic>?) ?? {};
    final state = context.watch<StudentState>();
    final profile = state.profileData ?? {};

    // Combine form data with fallback to live profile data if some fields are empty
    final mergedForm = <String, dynamic>{
      ...formData,
      if (formData['applicant_name'] == null) 'applicant_name': profile['full_name'],
      if (formData['phone'] == null) 'phone': profile['phone'],
      if (formData['dob'] == null) 'dob': profile['dob'],
      if (formData['gender'] == null) 'gender': profile['gender'],
      if (formData['category'] == null) 'category': profile['category'] ?? 'ST',
      if (formData['tribe_name'] == null) 'tribe_name': profile['tribe_name'],
      if (formData['is_pvtg'] == null) 'is_pvtg': profile['is_pvtg'],
      if (formData['state'] == null) 'state': profile['state'],
      if (formData['district'] == null) 'district': profile['district'],
      if (formData['course_level'] == null) 'course_level': profile['course_level'],
      if (formData['course_name'] == null) 'course_name': profile['course_name'],
      if (formData['institution_name'] == null) 'institution_name': profile['institution_name'],
      if (formData['institution_code'] == null) 'institution_code': profile['institution_code'],
      if (formData['annual_family_income'] == null) 'annual_family_income': profile['annual_family_income'],
      if (formData['last_exam_percentage'] == null) 'last_exam_percentage': profile['last_exam_percentage'],
      if (formData['apaar_id'] == null) 'apaar_id': profile['apaar_id'],
      if (formData['ifsc'] == null) 'ifsc': profile['ifsc'],
      if (formData['bank_account_last4'] == null) 'bank_account_last4': profile['bank_account_last4'],
    };

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Status Bar
          Row(
            children: [
              StatusChip(label: s.statusLabel(status), status: status),
              if (a['auto_verified'] == true)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Chip(
                    label: Text('Auto-Verified', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                    backgroundColor: AppColors.success,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              const Spacer(),
              Text('v${a['version']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),

          // Verification Checklist progress banner
          if (_checklistSummary != null) ...[
            _VerificationChecklistBanner(
              applicationId: widget.applicationId,
              schemeCode: a['scheme_code'] as String,
              checklistSummary: _checklistSummary,
            ),
            const SizedBox(height: 12),
          ],

          // Verification report card (if available after submission)
          if (a['verification_report'] != null && status != 'DRAFT' && status != 'SUBMITTED' && status != 'DEFICIENCY') ...[
            _VerificationStatusCard(report: a['verification_report'], autoVerified: a['auto_verified'] == true),
            const SizedBox(height: 12),
          ],

          // Open deficiencies / correction requests
          if (openDefs.isNotEmpty) ...[
            ...openDefs.map((d) => Card(
                  color: AppColors.danger.withValues(alpha: 0.06),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.error_outline, color: AppColors.danger),
                    title: Text('${d['message']}'),
                    trailing: ElevatedButton(
                      onPressed: busy ? null : () => _resolveDeficiency(d as Map<String, dynamic>),
                      child: Text(s.resolveCorrection),
                    ),
                  ),
                )),
          ],

          // Missing profile information warning banner
          _buildMissingProfileBanner(mergedForm),

          // Scheme Rules and Eligibility Criteria Card
          _buildSchemeRulesCard(mergedForm),
          const SizedBox(height: 12),

          // Auto-filled Application Details Card (Personal, Academic, Financial)
          _buildApplicationDetailsCard(mergedForm, editable),
          const SizedBox(height: 12),

          // Required documents card
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

          // Application History
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

          // Inline submit button for drafts
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

  Widget _buildMissingProfileBanner(Map<String, dynamic> form) {
    final List<String> missingFields = [];
    if (form['applicant_name'] == null || form['applicant_name'] == '') missingFields.add('Full Name');
    if (form['dob'] == null || form['dob'] == '') missingFields.add('Date of Birth');
    if (form['course_level'] == null || form['course_level'] == '') missingFields.add('Course Level');
    if (form['annual_family_income'] == null) missingFields.add('Family Income');

    if (missingFields.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Profile Information Incomplete',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Missing details needed for auto-filling: ${missingFields.join(", ")}.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF78350F)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
                  await _syncFromProfile();
                },
                icon: const Icon(Icons.badge_outlined, size: 14),
                label: const Text('Complete Profile', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF92400E),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: busy ? null : _syncFromProfile,
                icon: const Icon(Icons.sync, size: 14),
                label: const Text('Re-check Profile', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSchemeRulesCard(Map<String, dynamic> form) {
    final rules = (scheme?['rules'] as List?) ?? [];
    if (rules.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EEF8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rule_folder_outlined, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Scheme Eligibility Rules (${scheme?['short_name'] ?? 'Rules'})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rules.map((r) {
            final rule = r as Map<String, dynamic>;
            final field = rule['field'] as String;
            final op = rule['op'] as String;
            final expected = rule['value'];
            final actual = form[field];

            bool satisfied = false;
            bool missing = actual == null;

            if (!missing) {
              if (op == 'eq') satisfied = actual == expected;
              if (op == 'lte' && actual is num && expected is num) satisfied = actual <= expected;
              if (op == 'gte' && actual is num && expected is num) satisfied = actual >= expected;
              if (op == 'in' && expected is List) satisfied = expected.contains(actual);
              if (op == 'truthy') satisfied = actual == true;
            }

            final color = missing
                ? const Color(0xFFD97706)
                : satisfied
                    ? AppColors.success
                    : AppColors.danger;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    missing
                        ? Icons.help_outline_rounded
                        : satisfied
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${rule['label']}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      missing ? 'Missing' : (satisfied ? 'Eligible' : 'Mismatch'),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildApplicationDetailsCard(Map<String, dynamic> form, bool editable) {
    return Container(
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header with Sync & Edit actions
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.assignment_ind_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Application Profile & Form', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
                    Text(
                      'Auto-filled according to ${scheme?['short_name'] ?? 'Scheme'}',
                      style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (editable) ...[
                IconButton(
                  icon: const Icon(Icons.sync_rounded, color: AppColors.primary, size: 20),
                  tooltip: 'Sync with Latest Profile',
                  onPressed: busy ? null : _syncFromProfile,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF002970), size: 22),
                  tooltip: 'Edit Application Details',
                  onPressed: busy ? null : () => _openEditDetailsModal(form),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Source badges
          const Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _SourceChip(label: 'eKYC / Aadhaar', icon: Icons.fingerprint),
              _SourceChip(label: 'DigiLocker', icon: Icons.folder_shared_outlined),
              _SourceChip(label: 'APAAR Academic', icon: Icons.school_outlined),
              _SourceChip(label: 'e-District Caste', icon: Icons.account_balance_outlined),
            ],
          ),
          const Divider(height: 24, color: Color(0xFFE2EEF8)),

          // 1. Personal & Identity
          _buildGroupTitle(Icons.person_outline, 'Personal & Identity Details'),
          _buildDetailRow('Applicant Name', form['applicant_name'] ?? '—', isBold: true),
          _buildDetailRow('Mobile Number', form['phone'] ?? '—'),
          _buildDetailRow('Date of Birth', form['dob'] != null ? '${form['dob']}' : '—'),
          _buildDetailRow('Gender', form['gender'] == 'F' ? 'Female' : (form['gender'] == 'M' ? 'Male' : (form['gender'] ?? '—'))),
          _buildDetailRow('Category / Tribe', '${form['category'] ?? 'ST'}${form['tribe_name'] != null ? ' (${form['tribe_name']})' : ''}'),
          if (form['is_pvtg'] == true)
            _buildDetailRow('PVTG Status', 'Particularly Vulnerable Tribal Group', highlightColor: const Color(0xFF0D9488)),
          _buildDetailRow('Domicile', '${form['district'] ?? '—'}, ${form['state'] ?? '—'}'),
          if (form['apaar_id'] != null)
            _buildDetailRow('APAAR ID', '${form['apaar_id']}'),

          const Divider(height: 20, color: Color(0xFFE2EEF8)),

          // 2. Academic Enrollment Details
          _buildGroupTitle(Icons.school_outlined, 'Academic Enrollment Details'),
          _buildDetailRow('Course Level', _formatCourseLevel(form['course_level'])),
          _buildDetailRow('Course Name', form['course_name'] ?? '—'),
          _buildDetailRow('Institution Name', form['institution_name'] ?? '—'),
          _buildDetailRow('Institution Code', form['institution_code'] ?? '—'),
          if (form['semester'] != null)
            _buildDetailRow('Semester / Year', 'Semester ${form['semester']}'),
          if (form['last_exam_percentage'] != null)
            _buildDetailRow('Last Exam Score', '${form['last_exam_percentage']}%'),
          if (form['institution_top_class_notified'] == true)
            _buildDetailRow('Top-Class Institute', 'Yes (Recognized Premier Institute)', highlightColor: AppColors.success),
          if (form['ugc_nta_qualified'] == true)
            _buildDetailRow('UGC-NET / JRF', 'Qualified ${form['ugc_nta_roll'] != null ? "(${form['ugc_nta_roll']})" : ""}', highlightColor: AppColors.success),
          if (form['foreign_admission'] == true)
            _buildDetailRow('Foreign Admission', 'Admission Offer Confirmed', highlightColor: AppColors.success),

          const Divider(height: 20, color: Color(0xFFE2EEF8)),

          // 3. Financial & Bank Details
          _buildGroupTitle(Icons.account_balance_outlined, 'Income & Bank Disbursement'),
          _buildDetailRow(
            'Annual Family Income',
            form['annual_family_income'] != null ? '₹ ${form['annual_family_income']} / annum' : '—',
            isBold: true,
          ),
          _buildDetailRow('Bank Account', form['bank_account_last4'] != null ? '•••• •••• ${form['bank_account_last4']}' : '—'),
          _buildDetailRow('IFSC Code', form['ifsc'] ?? '—'),
          _buildDetailRow('Direct Benefit Transfer', 'Aadhaar Seeded & Active ✓', highlightColor: AppColors.success),
        ],
      ),
    );
  }

  Widget _buildGroupTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: const Color(0xFF002970)),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF002970))),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false, Color? highlightColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: highlightColor ?? (value == '—' ? Colors.grey : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCourseLevel(dynamic level) {
    if (level == null) return '—';
    final s = level.toString();
    switch (s) {
      case 'CLASS_9':
        return 'Class 9 (Secondary)';
      case 'CLASS_10':
        return 'Class 10 (Secondary)';
      case 'CLASS_11':
        return 'Class 11 (Higher Secondary)';
      case 'CLASS_12':
        return 'Class 12 (Higher Secondary)';
      case 'DIPLOMA':
        return 'Polytechnic / Diploma';
      case 'UG':
        return 'Undergraduate (UG)';
      case 'PG':
        return 'Postgraduate (PG)';
      case 'MPHIL':
        return 'M.Phil.';
      case 'PHD':
        return 'Ph.D. / Doctoral';
      default:
        return s.replaceAll('_', ' ');
    }
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: const Color(0xFF1D4ED8)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
          ),
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

// ================================================= _VerificationChecklistBanner

/// Compact banner card that shows the X/Y verification progress and navigates
/// to the full [VerificationScreen] on tap.
class _VerificationChecklistBanner extends StatelessWidget {
  const _VerificationChecklistBanner({
    required this.applicationId,
    required this.schemeCode,
    required this.checklistSummary,
  });

  final int applicationId;
  final String schemeCode;
  final Map<String, dynamic>? checklistSummary;

  @override
  Widget build(BuildContext context) {
    final total = checklistSummary?['total'] as int?;
    final verified = checklistSummary?['verified'] as int?;
    final hasData = total != null && verified != null;
    final isComplete = hasData && verified == total && total > 0;

    final fraction = hasData && total > 0 ? verified / total : 0.0;
    final Color progressColor = isComplete
        ? AppColors.success
        : fraction > 0.5
            ? const Color(0xFFF59E0B)
            : AppColors.accent;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerificationScreen(
            applicationId: applicationId,
            schemeCode: schemeCode,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isComplete
                ? AppColors.success.withValues(alpha: 0.35)
                : AppColors.accent.withValues(alpha: 0.30),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Shield icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isComplete
                    ? AppColors.success.withValues(alpha: 0.12)
                    : AppColors.accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isComplete
                    ? Icons.verified_user_rounded
                    : Icons.shield_outlined,
                color: isComplete ? AppColors.success : AppColors.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verification Checklist',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasData
                        ? isComplete
                            ? 'All $total verifications complete ✓'
                            : '$verified of $total verifications complete'
                        : 'Check document requirements →',
                    style: TextStyle(
                      fontSize: 12,
                      color: isComplete ? AppColors.success : Colors.black54,
                    ),
                  ),
                  if (hasData && !isComplete) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 4,
                        backgroundColor: const Color(0xFFE2EEF8),
                        valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.accent, size: 22),
          ],
        ),
      ),
    );
  }
}

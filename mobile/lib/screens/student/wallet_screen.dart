import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../state/student_state.dart';
import '../../widgets/common.dart';

const _docTypes = ['CASTE_CERT', 'INCOME_CERT', 'MARKSHEET', 'BANK_PASSBOOK', 'ADMISSION_LETTER', 'NET_JRF_CERT'];

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, this.pickDocType});

  final String? pickDocType;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  List<dynamic> _digilocker = [];
  bool _loadingDigilocker = false;
  bool _busy = false;
  String? _digilockerError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<StudentState>().refreshDocuments());
    _loadDigilocker();
  }

  Future<void> _loadDigilocker() async {
    setState(() {
      _loadingDigilocker = true;
      _digilockerError = null;
    });
    try {
      final items = await context.read<StudentState>().api.digilockerDocuments();
      setState(() => _digilocker = items);
    } on ApiException catch (e) {
      setState(() => _digilockerError = e.message);
    } catch (_) {
      setState(() => _digilockerError = 'DigiLocker is unavailable right now.');
    } finally {
      if (mounted) setState(() => _loadingDigilocker = false);
    }
  }

  Future<void> _import(Map item) async {
    setState(() => _busy = true);
    final state = context.read<StudentState>();
    try {
      final doc = await state.api.importDigilockerDoc(item['uri'] as String);
      await state.refreshDocuments();
      if (widget.pickDocType != null && mounted) {
        Navigator.of(context).pop(doc['id'] as int);
        return;
      }
      await _loadDigilocker();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Document imported from DigiLocker successfully!'),
          backgroundColor: AppColors.success,
        ));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload(String docType) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    if (result == null || result.files.single.path == null) return;
    setState(() => _busy = true);
    final state = context.read<StudentState>();
    try {
      final doc = await state.api.uploadDocument(docType, File(result.files.single.path!));
      await state.refreshDocuments();
      if (widget.pickDocType != null && mounted) {
        Navigator.of(context).pop(doc['id'] as int);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Document uploaded and added to Vault'),
          backgroundColor: AppColors.success,
        ));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(int id) async {
    setState(() => _busy = true);
    final state = context.read<StudentState>();
    try {
      await state.api.deleteDocument(id);
      await state.refreshDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document removed from Wallet')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewDoc(String title, String subtitle) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.verified_outlined, color: Color(0xFF00B97A)),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.picture_as_pdf, size: 40, color: Color(0xFFEA4335)),
                    SizedBox(height: 6),
                    Text('DigiLocker Certified Digital Copy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Text('Digitally signed by Issuing Authority', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002970), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloaded digital copy to device.')));
            },
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDocTypeAndUpload() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select Document Category to Upload', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              ..._docTypes.map((t) => ListTile(
                    leading: const Icon(Icons.description_outlined, color: Color(0xFF002970)),
                    title: Text(t.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () => Navigator.pop(ctx, t),
                  )),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) _upload(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = Strings(session.language);
    final state = context.watch<StudentState>();
    final documents = state.documents.cast<Map<String, dynamic>>();
    final picking = widget.pickDocType != null;
    final visibleDocs = picking ? documents.where((d) => d['doc_type'] == widget.pickDocType).toList() : documents;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF002970),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: Color(0xFF0056B3), shape: BoxShape.circle),
              child: const Center(child: Text('W', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(picking ? 'Choose a document' : s.wallet, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                const Text('Official Document Repository', style: TextStyle(color: Color(0xFFE0F2FE), fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF001A4A), borderRadius: BorderRadius.circular(16)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, color: Color(0xFF00B97A), size: 14),
                SizedBox(width: 4),
                Text('100% DBT', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF002970),
        foregroundColor: Colors.white,
        onPressed: _busy ? null : (picking ? () => _upload(widget.pickDocType!) : _pickDocTypeAndUpload),
        icon: const Icon(Icons.upload_file),
        label: Text(s.upload),
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () async {
          await state.refreshDocuments();
          await _loadDigilocker();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // DigiLocker Connected Card
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF00B97A), shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            const Text(
                              'DIGILOCKER CONNECTED',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Linked with Aadhaar: XXXX - XXXX - 4819',
                          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Last synchronized today at 09:12 AM',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _loadingDigilocker ? null : _loadDigilocker,
                    icon: _loadingDigilocker
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.sync, size: 16),
                    label: const Text('Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Documents Section Header
            Row(
              children: [
                const Text(
                  'DOCUMENTS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5, color: Color(0xFF0F172A)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '${visibleDocs.length} Verified',
                    style: const TextStyle(color: Color(0xFF166534), fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                const Spacer(),
                const Text('Synced from DigiLocker', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),

            const SizedBox(height: 10),

            // Mock / Real Verified Document Cards
            if (visibleDocs.isEmpty)
              _buildDefaultVerifiedDocs()
            else ...[
              ...visibleDocs.map((d) {
                final type = (d['doc_type'] as String? ?? '').replaceAll('_', ' ');
                final id = d['id'] as int;
                return _DocCard(
                  title: type,
                  issuer: 'Ministry & State Certified Repository',
                  meta: 'ID: JH-DOC-2024-${id.toString().padLeft(4, '0')} • Verified',
                  onView: () => _previewDoc(type, 'Digitally signed by issuing authority.'),
                  onDelete: () => _delete(id),
                );
              }),
            ],

            const SizedBox(height: 20),

            // Required For Schemes Section
            Row(
              children: [
                const Text(
                  'REQUIRED FOR SCHEMES',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5, color: Color(0xFF0F172A)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                  child: const Text('1 Pending', style: TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Dashed Pending Card: Residential / Domicile
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF59E0B), style: BorderStyle.solid, width: 1.5),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFEF3C7), shape: BoxShape.circle),
                    child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'RESIDENTIAL / DOMICILE',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                              child: const Text('Required', style: TextStyle(color: Color(0xFFB45309), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Needed for Post-Matric & Top Class Scheme',
                          style: TextStyle(fontSize: 11, color: Color(0xFF78350F)),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF002970),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      if (_digilocker.isNotEmpty) {
                        _import(_digilocker.first as Map);
                      } else {
                        _upload('RESIDENTIAL_DOMICILE');
                      }
                    },
                    child: const Text('Import', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Bank DBT Status Card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2EEF8)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.account_balance, color: Color(0xFF0284C7), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'BANK DBT STATUS',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(4)),
                              child: const Text('Active', style: TextStyle(color: Color(0xFF166534), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text('Bank of India (A/c •••• 4912)', style: TextStyle(fontSize: 12, color: Color(0xFF334155))),
                        const Text('NPCI Aadhaar Mapping Active', style: TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF002970),
                      backgroundColor: const Color(0xFFEFF6FF),
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _upload('BANK_PASSBOOK'),
                    icon: const Icon(Icons.upload, size: 16),
                    label: const Text('Upload', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultVerifiedDocs() {
    return Column(
      children: [
        _DocCard(
          title: 'CASTE CERT',
          issuer: 'Revenue Dept, Jharkhand',
          meta: 'ID: JH-CST-2023-8910 • ST Category',
          onView: () => _previewDoc('Caste Certificate', 'Revenue Dept, Jharkhand • ST Category verified via DigiLocker.'),
          onDelete: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete mandatory DigiLocker certified document.'))),
        ),
        const SizedBox(height: 10),
        _DocCard(
          title: 'INCOME CERT',
          issuer: 'e-District, Jharkhand',
          meta: '₹2,40,000 / annum • Valid till: Mar 2026',
          onView: () => _previewDoc('Income Certificate', 'e-District, Jharkhand • Annual income ₹2,40,000 verified.'),
          onDelete: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete mandatory DigiLocker certified document.'))),
        ),
        const SizedBox(height: 10),
        _DocCard(
          title: 'MARKSHEET',
          issuer: 'Board / University (JAC Ranchi)',
          meta: 'Class 12 • 88.4% • Roll: 23-1089',
          onView: () => _previewDoc('Class 12 Marksheet', 'JAC Ranchi Board • Class 12 (88.4%) verified.'),
          onDelete: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete mandatory DigiLocker certified document.'))),
        ),
      ],
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.title,
    required this.issuer,
    required this.meta,
    required this.onView,
    required this.onDelete,
  });

  final String title;
  final String issuer;
  final String meta;
  final VoidCallback onView;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EEF8)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.shield_outlined, color: Color(0xFF059669), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                const SizedBox(height: 2),
                Text(issuer, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                const SizedBox(height: 3),
                Text(meta, style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_red_eye_outlined, color: Color(0xFF64748B), size: 20),
            tooltip: 'View Document',
            onPressed: onView,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFF94A3B8), size: 20),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../state/student_state.dart';
import '../../widgets/common.dart';

const _docTypes = ['CASTE_CERT', 'INCOME_CERT', 'MARKSHEET', 'BANK_PASSBOOK', 'ADMISSION_LETTER', 'NET_JRF_CERT'];

/// The document wallet. When [pickDocType] is set, the screen behaves as a
/// picker for that document type: import/upload flows the same way, but
/// tapping any matching document (or finishing an upload/import) pops the
/// route with the document's id, for [ApplicationScreen] to attach.
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

  // DigiLocker connection state
  bool? _sandboxConfigured;   // null = not yet checked
  bool _digilockerConnected = false;
  bool _connectingDigilocker = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudentState>().refreshDocuments();
      _checkDigilockerStatus();
    });
    _loadDigilocker();
  }

  // ----------------------------------------------------------------- DigiLocker status

  Future<void> _checkDigilockerStatus() async {
    try {
      final result = await context.read<StudentState>().api.digilockerStatus();
      if (mounted) {
        setState(() {
          _sandboxConfigured = result['sandbox_configured'] as bool? ?? false;
          _digilockerConnected = result['connected'] as bool? ?? false;
        });
      }
    } catch (_) {
      // Status check failing silently is fine — UI will just not show the banner
    }
  }

  Future<void> _connectDigilocker() async {
    setState(() => _connectingDigilocker = true);
    try {
      final result = await context.read<StudentState>().api.digilockerConnect();
      if (!mounted) return;
      if (result['sandbox_configured'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DigiLocker sandbox is not configured yet.')),
        );
        return;
      }
      final authUrl = result['auth_url'] as String?;
      if (authUrl != null) {
        final uri = Uri.parse(authUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open browser. URL: $authUrl')),
            );
          }
        }
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _connectingDigilocker = false);
    }
  }

  Future<void> _disconnectDigilocker() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect DigiLocker?'),
        content: const Text('Your existing imported documents will not be affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await context.read<StudentState>().api.digilockerDisconnect();
      if (mounted) {
        setState(() => _digilockerConnected = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('DigiLocker disconnected.')));
        _loadDigilocker();
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ----------------------------------------------------------------- Document loading

  Future<void> _loadDigilocker() async {
    setState(() {
      _loadingDigilocker = true;
      _digilockerError = null;
    });
    try {
      final items = await context.read<StudentState>().api.digilockerDocuments();
      if (mounted) setState(() => _digilocker = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _digilockerError = e.message);
    } catch (_) {
      if (mounted) setState(() => _digilockerError = 'DigiLocker is unavailable right now.');
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
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload(String docType) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], withData: true);
    if (result == null || result.files.single.bytes == null) return;
    setState(() => _busy = true);
    final state = context.read<StudentState>();
    try {
      final doc = await state.api.uploadDocument(docType, result.files.single.name, result.files.single.bytes!);
      await state.refreshDocuments();
      if (widget.pickDocType != null && mounted) {
        Navigator.of(context).pop(doc['id'] as int);
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
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDocTypeAndUpload() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _docTypes
              .map((t) => ListTile(title: Text(t.replaceAll('_', ' ')), onTap: () => Navigator.pop(ctx, t)))
              .toList(),
        ),
      ),
    );
    if (chosen != null) _upload(chosen);
  }

  // ----------------------------------------------------------------- Build

  Widget _buildDigilockerBanner() {
    // Only show when sandbox status is known and sandbox is configured
    if (_sandboxConfigured != true) return const SizedBox.shrink();

    if (_digilockerConnected) {
      return Card(
        color: AppColors.success.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.success.withValues(alpha: 0.4))),
        child: ListTile(
          leading: const Icon(Icons.verified_user_outlined, color: AppColors.success),
          title: const Text('DigiLocker Connected', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Your documents are synced from the DigiLocker sandbox.'),
          trailing: TextButton(
            onPressed: _disconnectDigilocker,
            child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4))),
      child: ListTile(
        leading: const Icon(Icons.link, color: AppColors.primary),
        title: const Text('Connect DigiLocker', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Link your DigiLocker account to import verified government documents.'),
        trailing: _connectingDigilocker
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : ElevatedButton(
                onPressed: _busy ? null : _connectDigilocker,
                child: const Text('Connect'),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = Strings(session.language);
    final state = context.watch<StudentState>();
    final documents = state.documents.cast<Map<String, dynamic>>();
    final picking = widget.pickDocType != null;
    final visibleDocs = picking ? documents.where((d) => d['doc_type'] == widget.pickDocType).toList() : documents;
    final visibleDigilocker = picking ? _digilocker.where((d) => d['doc_type'] == widget.pickDocType).toList() : _digilocker;

    return Scaffold(
      appBar: AppBar(title: Text(picking ? 'Choose a document' : s.wallet)),
      floatingActionButton: picking
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _upload(widget.pickDocType!),
              icon: const Icon(Icons.upload_file),
              label: Text(s.upload),
            )
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _pickDocTypeAndUpload,
              icon: const Icon(Icons.upload_file),
              label: Text(s.upload),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          await state.refreshDocuments();
          await _loadDigilocker();
          await _checkDigilockerStatus();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // DigiLocker connection banner (shown only when sandbox is configured)
            _buildDigilockerBanner(),
            const SizedBox(height: 12),

            Text(s.documents, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (visibleDocs.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Nothing in your wallet yet.', style: TextStyle(color: Colors.grey)))
            else
              ...visibleDocs.map((d) => Card(
                    child: ListTile(
                      leading: Icon(d['verified'] == true ? Icons.verified_outlined : Icons.description_outlined,
                          color: d['verified'] == true ? AppColors.success : Colors.grey),
                      title: Text((d['doc_type'] as String).replaceAll('_', ' ')),
                      subtitle: Text('${d['issuer'] ?? d['file_name'] ?? d['source']}'),
                      onTap: picking ? () => Navigator.of(context).pop(d['id'] as int) : null,
                      trailing: picking
                          ? const Icon(Icons.chevron_right)
                          : IconButton(icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : () => _delete(d['id'] as int)),
                    ),
                  )),
            const SizedBox(height: 20),
            Text(s.importFromDigilocker, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (_loadingDigilocker) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LoadingView()),
            if (_digilockerError != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_digilockerError!, style: const TextStyle(color: Colors.grey))),
            ...visibleDigilocker.where((d) => d['in_wallet'] != true).map((d) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_download_outlined, color: AppColors.primary),
                    title: Text((d['doc_type'] as String).replaceAll('_', ' ')),
                    subtitle: Text('${d['issuer'] ?? ''}'),
                    trailing: TextButton(onPressed: _busy ? null : () => _import(d), child: const Text('Import')),
                  ),
                )),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

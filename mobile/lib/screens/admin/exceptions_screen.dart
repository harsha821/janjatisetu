import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import 'admin_application_detail_screen.dart';

const _statusOptions = ['OPEN', 'RESOLVED', 'DISMISSED', 'ESCALATED'];

class ExceptionsScreen extends StatefulWidget {
  const ExceptionsScreen({super.key});

  @override
  State<ExceptionsScreen> createState() => _ExceptionsScreenState();
}

class _ExceptionsScreenState extends State<ExceptionsScreen> {
  String _status = 'OPEN';
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await context.read<Session>().api.adminExceptions(status: _status);
      setState(() => _items = items);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(Map<String, dynamic> c) async {
    final resolution = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${c['title']}'),
        children: [
          for (final r in ['CONFIRMED_OK', 'CORRECTED', 'DISMISS', 'ESCALATE'])
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, r), child: Text(r.replaceAll('_', ' '))),
        ],
      ),
    );
    if (resolution == null) return;
    try {
      await context.read<Session>().api.resolveException(c['id'] as int, resolution);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exceptions')),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: _statusOptions
                  .map((st) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(st),
                          selected: _status == st,
                          onSelected: (_) {
                            setState(() => _status = st);
                            _load();
                          },
                        ),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : _items.isEmpty
                        ? const EmptyView(message: 'Nothing here.', icon: Icons.task_alt_outlined)
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              itemCount: _items.length,
                              itemBuilder: (context, i) {
                                final c = _items[i] as Map<String, dynamic>;
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: ListTile(
                                    leading: SeverityChip(severity: c['severity'] as String),
                                    title: Text('${c['title']}'),
                                    subtitle: Text('${c['kind']}${c['resolution_note'] != null ? " \u00b7 ${c['resolution_note']}" : ''}'),
                                    trailing: c['status'] == 'OPEN' || c['status'] == 'ESCALATED'
                                        ? TextButton(onPressed: () => _resolve(c), child: const Text('Resolve'))
                                        : Text('${c['status']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    onTap: c['application_id'] == null
                                        ? null
                                        : () => Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => AdminApplicationDetailScreen(applicationId: c['application_id'] as int))),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

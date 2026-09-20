import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import 'admin_application_detail_screen.dart';

const _statusFilters = ['ALL', 'SUBMITTED', 'UNDER_VERIFICATION', 'DEFICIENCY', 'VERIFIED', 'SANCTIONED', 'DBT_PAID', 'REJECTED'];

class AdminApplicationsScreen extends StatefulWidget {
  const AdminApplicationsScreen({super.key});

  @override
  State<AdminApplicationsScreen> createState() => _AdminApplicationsScreenState();
}

class _AdminApplicationsScreenState extends State<AdminApplicationsScreen> {
  String _status = 'ALL';
  final _search = TextEditingController();
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
      final r = await context.read<Session>().api.adminApplications(status: _status == 'ALL' ? null : _status, q: _search.text.trim());
      setState(() => _items = (r['items'] as List?) ?? []);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Applications')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by student name or reference',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _load),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _statusFilters
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
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : _items.isEmpty
                        ? const EmptyView(message: 'No applications match this filter.', icon: Icons.folder_open_outlined)
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              itemCount: _items.length,
                              itemBuilder: (context, i) {
                                final a = _items[i] as Map<String, dynamic>;
                                return ListTile(
                                  title: Text('${a['student']}'),
                                  subtitle: Text('${a['scheme_code']} \u00b7 ${a['district'] ?? '-'}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if ((a['open_cases'] as int? ?? 0) > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Icon(Icons.flag, size: 16, color: AppColors.danger),
                                        ),
                                      StatusChip(label: a['status'] as String, status: a['status'] as String),
                                    ],
                                  ),
                                  onTap: () => Navigator.of(context)
                                      .push(MaterialPageRoute(builder: (_) => AdminApplicationDetailScreen(applicationId: a['id'] as int)))
                                      .then((_) => _load()),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../state/session.dart';
import '../../state/student_state.dart';
import '../../widgets/common.dart';
import 'application_screen.dart';

class SchemesScreen extends StatefulWidget {
  const SchemesScreen({super.key});

  @override
  State<SchemesScreen> createState() => _SchemesScreenState();
}

class _SchemesScreenState extends State<SchemesScreen> {
  bool _busy = false;

  Map<String, dynamic>? _eligFor(List<dynamic> eligibility, String code) {
    for (final e in eligibility) {
      if (e['scheme_code'] == code) return e as Map<String, dynamic>;
    }
    return null;
  }

  Map<String, dynamic>? _appFor(List<dynamic> apps, String code) {
    for (final a in apps) {
      if (a['scheme_code'] == code) return a as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> _apply(BuildContext context, String schemeCode) async {
    final state = context.read<StudentState>();
    setState(() => _busy = true);
    try {
      final app = await state.api.createApplication(schemeCode, clientUuid: state.newClientUuid());
      if (context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApplicationScreen(applicationId: app['id'] as int)));
      }
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = Strings(session.language);
    final state = context.watch<StudentState>();
    final schemes = state.schemes;
    final apps = (state.dashboard?['applications'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(s.schemes)),
      body: schemes.isEmpty
          ? RefreshIndicator(
              onRefresh: () => state.loadAll(),
              child: ListView(children: [const SizedBox(height: 120), EmptyView(message: 'No schemes loaded yet.', icon: Icons.school_outlined)]),
            )
          : RefreshIndicator(
              onRefresh: () => state.loadAll(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: schemes.length,
                itemBuilder: (context, i) {
                  final scheme = schemes[i] as Map<String, dynamic>;
                  final code = scheme['code'] as String;
                  final elig = _eligFor(state.eligibility, code);
                  final existingApp = _appFor(apps, code);
                  return _SchemeCard(
                    scheme: scheme,
                    eligibility: elig,
                    existingApp: existingApp,
                    busy: _busy,
                    s: s,
                    onApply: () => _apply(context, code),
                    onOpen: existingApp == null
                        ? null
                        : () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => ApplicationScreen(applicationId: existingApp['id'] as int))),
                  );
                },
              ),
            ),
    );
  }
}

class _SchemeCard extends StatelessWidget {
  const _SchemeCard({
    required this.scheme,
    required this.eligibility,
    required this.existingApp,
    required this.busy,
    required this.s,
    required this.onApply,
    required this.onOpen,
  });

  final Map<String, dynamic> scheme;
  final Map<String, dynamic>? eligibility;
  final Map<String, dynamic>? existingApp;
  final bool busy;
  final Strings s;
  final VoidCallback onApply;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final status = eligibility?['status'] as String? ?? 'NEEDS_REVIEW';
    final label = status == 'ELIGIBLE' ? s.eligible : status == 'NOT_ELIGIBLE' ? s.notEligible : s.needsReview;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${scheme['short_name'] ?? scheme['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              StatusChip(label: label, status: status == 'ELIGIBLE' ? 'SANCTIONED' : status == 'NOT_ELIGIBLE' ? 'REJECTED' : 'SUBMITTED'),
            ],
          ),
          const SizedBox(height: 6),
          Text('${scheme['description'] ?? ''}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
          if (eligibility != null && eligibility!['summary'] != null) ...[
            const SizedBox(height: 6),
            Text('${eligibility!['summary']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: existingApp != null
                ? OutlinedButton(onPressed: onOpen, child: Text(s.continueApplication))
                : ElevatedButton(
                    onPressed: (status == 'NOT_ELIGIBLE' || busy) ? null : onApply,
                    child: Text(s.startApplication),
                  ),
          ),
        ],
      ),
    );
  }
}

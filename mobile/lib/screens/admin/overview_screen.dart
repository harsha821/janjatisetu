import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  Map<String, dynamic>? _data;
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
      final data = await context.read<Session>().api.adminOverview();
      setState(() => _data = data);
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
      appBar: AppBar(title: const Text('Ministry Overview')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _body(_data!)),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final apps = (d['applications'] as Map?) ?? {};
    final exceptions = (d['exceptions'] as Map?) ?? {};
    final money = (d['money'] as Map?) ?? {};
    final byStatus = (apps['by_status'] as Map?) ?? {};
    final byScheme = (apps['by_scheme'] as Map?) ?? {};
    final coverage = d['coverage'] as Map?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: _StatCard(label: 'Applications', value: '${apps['total'] ?? 0}', color: AppColors.primary)),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(label: 'Open cases', value: '${exceptions['open'] ?? 0}', color: AppColors.danger)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _StatCard(label: 'Sanctioned', value: '\u20b9${_fmt(money['sanctioned'])}', color: AppColors.accent)),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(label: 'Paid', value: '\u20b9${_fmt(money['paid'])}', color: AppColors.success)),
        ]),
        const SizedBox(height: 10),
        _StatCard(label: 'Registered students', value: '${d['students'] ?? 0}', color: AppColors.primaryDark, wide: true),
        const SizedBox(height: 20),
        const Text('By status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        SectionCard(
          child: Column(
            children: byStatus.entries
                .map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text('${e.key}')),
                        Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ]),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('By scheme', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        SectionCard(
          child: Column(
            children: byScheme.entries
                .map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text('${e.key}')),
                        Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ]),
                    ))
                .toList(),
          ),
        ),
        if (coverage != null) ...[
          const SizedBox(height: 16),
          const Text('Coverage funnel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _funnelRow('Enrolled ST students', coverage['enrolled_st']),
                _funnelRow('Matched to a scholarship', coverage['matched']),
                _funnelRow('Uncertain match', coverage['uncertain']),
                _funnelRow('Potential gap', coverage['potential_gap']),
                _funnelRow('Validated (unreached)', coverage['validated']),
                _funnelRow('Outreach sent', coverage['outreach_sent']),
                _funnelRow('Applied', coverage['applied']),
                const SizedBox(height: 8),
                Text('${coverage['note'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _funnelRow(String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(label)), Text('${value ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold))]),
      );

  String _fmt(dynamic v) {
    final n = (v is num) ? v : 0;
    return n.toStringAsFixed(0);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color, this.wide = false});

  final String label;
  final String value;
  final Color color;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

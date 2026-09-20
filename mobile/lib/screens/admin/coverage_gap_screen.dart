import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';

class CoverageGapScreen extends StatefulWidget {
  const CoverageGapScreen({super.key});

  @override
  State<CoverageGapScreen> createState() => _CoverageGapScreenState();
}

class _CoverageGapScreenState extends State<CoverageGapScreen> {
  static const _pageSize = 50;

  /// Filter chip label -> backend gap state (null = every state).
  static const _filters = <String, String?>{
    'Ready': 'VALIDATED',
    'Potential': 'POTENTIAL_GAP',
    'Contacted': 'OUTREACH_SENT',
    'Applied': 'APPLIED',
    'Dismissed': 'DISMISSED',
    'All': null,
  };

  // Which reviewer actions the backend allows from each state (mirrors RESOLVE_TRANSITIONS).
  static const _closableFrom = ['POTENTIAL_GAP', 'VALIDATED', 'OUTREACH_SENT'];
  static const _reopenableFrom = ['DISMISSED', 'OUTREACH_SENT', 'APPLIED'];

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _gaps = [];
  int _total = 0;
  String? _filter = 'VALIDATED';
  final Set<int> _selected = {};
  bool _loading = true; // first load: full-screen spinner
  bool _busy = false; // refresh / filter change: thin progress bar
  bool _loadingMore = false;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load({bool more = false}) async {
    final api = context.read<Session>().api;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _busy = true;
        if (_summary == null) _loading = true;
      }
      _error = null;
    });
    try {
      final summary = more ? _summary : await api.coverageGapSummary();
      final list = await api.coverageGapList(state: _filter, limit: _pageSize, offset: more ? _gaps.length : 0);
      if (!mounted) return;
      final items = ((list['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _summary = summary;
        _total = (list['total'] as int?) ?? items.length;
        _gaps = more ? [..._gaps, ...items] : items;
        // drop selections that no longer refer to a visible, still-contactable record
        _selected.removeWhere((id) => !_gaps.any((g) => g['id'] == id && g['state'] == 'VALIDATED'));
      });
    } on ApiException catch (e) {
      if (more) {
        _snack(e.message);
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (more) {
        _snack('Could not reach the server.');
      } else if (mounted) {
        setState(() => _error = 'Could not reach the server.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _busy = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _setFilter(String? state) {
    if (state == _filter) return;
    setState(() {
      _filter = state;
      _selected.clear();
      _gaps = [];
      _total = 0;
    });
    _load();
  }

  Future<void> _runDetection() async {
    setState(() => _running = true);
    try {
      await context.read<Session>().api.runCoverageGap();
      await _load();
      _snack('Coverage gap detection re-run');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _outreach(String channel) async {
    if (_selected.isEmpty) return;
    try {
      final r = await context.read<Session>().api.sendOutreach(_selected.toList(), channel);
      if (!mounted) return;
      setState(() => _selected.clear());
      await _load();
      _snack('Delivered ${r['delivered'] ?? 0}, queued ${r['queued'] ?? 0}, '
          'undelivered ${r['undelivered'] ?? 0}, skipped ${r['skipped'] ?? 0}');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<String?> _askNote({required String title, required bool required}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(labelText: required ? 'Reason (required)' : 'Note (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (required && text.isEmpty) return;
              Navigator.pop(ctx, text);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(Map<String, dynamic> gap, String action) async {
    String? note;
    if (action == 'DISMISS') {
      note = await _askNote(title: 'Dismiss this gap', required: true);
      if (note == null) return; // cancelled
    } else if (action == 'MARK_APPLIED') {
      note = await _askNote(title: 'Mark as applied', required: false);
      if (note == null) return;
    }
    if (!mounted) return;
    try {
      await context.read<Session>().api.resolveGap(gap['id'] as int, action, note: note);
      _selected.remove(gap['id']);
      await _load();
      _snack(switch (action) {
        'DISMISS' => 'Gap dismissed',
        'MARK_APPLIED' => 'Marked as applied',
        _ => 'Gap reopened and re-checked',
      });
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _showActions(Map<String, dynamic> gap) {
    final state = gap['state'] as String;
    final canClose = _closableFrom.contains(state);
    final canReopen = _reopenableFrom.contains(state);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('${gap['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_stateLabel(state)),
            ),
            const Divider(height: 1),
            if (canClose)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Mark as applied'),
                subtitle: const Text('The student applied outside JanjatiSetu'),
                onTap: () {
                  Navigator.pop(ctx);
                  _resolve(gap, 'MARK_APPLIED');
                },
              ),
            if (canClose)
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Dismiss'),
                subtitle: const Text('Not a real gap (a written reason is required)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _resolve(gap, 'DISMISS');
                },
              ),
            if (canReopen)
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reopen'),
                subtitle: const Text('Re-check it so it can be contacted again, e.g. on another channel'),
                onTap: () {
                  Navigator.pop(ctx);
                  _resolve(gap, 'REOPEN');
                },
              ),
          ],
        ),
      ),
    );
  }

  static String _stateLabel(String state) => switch (state) {
        'POTENTIAL_GAP' => 'Potential gap',
        'VALIDATED' => 'Ready for outreach',
        'OUTREACH_SENT' => 'Contacted',
        'APPLIED' => 'Applied',
        'DISMISSED' => 'Dismissed',
        _ => state,
      };

  static IconData _stateIcon(String state) => switch (state) {
        'POTENTIAL_GAP' => Icons.hourglass_empty,
        'OUTREACH_SENT' => Icons.mark_email_read_outlined,
        'APPLIED' => Icons.check_circle,
        'DISMISSED' => Icons.block,
        _ => Icons.circle_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coverage gap'),
        actions: [
          IconButton(
            tooltip: 'Re-run detection',
            icon: _running
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh),
            onPressed: _running ? null : _runDetection,
          ),
        ],
      ),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.campaign_outlined),
              label: Text('Outreach (${_selected.length})'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const {
                      'JAGO': 'In-app message (registered students only)',
                      'SMS': 'Text message to the mobile number on record',
                      'APP': 'In-app notification (registered students only)',
                      'INSTITUTION': "Recorded for the institution's nodal officer",
                    }
                        .entries
                        .map((c) => ListTile(
                              title: Text(c.key),
                              subtitle: Text(c.value),
                              onTap: () {
                                Navigator.pop(ctx);
                                _outreach(c.key);
                              },
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final funnel = (_summary?['funnel'] as Map?) ?? {};
    final districts = ((_summary?['districts'] as List?) ?? []).take(5).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_busy) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator()),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Funnel', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _row('Enrolled ST students', funnel['enrolled_st']),
              _row('Matched to a scholarship', funnel['matched']),
              _row('Uncertain match (review)', funnel['uncertain']),
              _row('Potential gap', funnel['potential_gap']),
              _row('Validated (unreached)', funnel['validated']),
              _row('Ready for outreach', funnel['ready_for_outreach']),
              _row('Outreach sent', funnel['outreach_sent']),
              _row('Applied', funnel['applied']),
              _row('Dismissed', funnel['dismissed']),
              const SizedBox(height: 8),
              Text('${funnel['note'] ?? ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        if (districts.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Districts with the most open gaps', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...districts.map((d) {
                  final m = d as Map;
                  return _row('${m['district']}, ${m['state']} (${m['validated'] ?? 0} ready)', m['open_gaps']);
                }),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: _filters.entries
              .map((e) => ChoiceChip(label: Text(e.key), selected: _filter == e.value, onSelected: (_) => _setFilter(e.value)))
              .toList(),
        ),
        const SizedBox(height: 8),
        Text('Showing ${_gaps.length} of $_total', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const Text('Tick "Ready" records to send outreach. Tap any record to fix it.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        if (_gaps.isEmpty && !_busy)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No records in this view.'))),
        ..._gaps.map(_tile),
        if (_gaps.length < _total)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(onPressed: () => _load(more: true), child: Text('Load more (${_total - _gaps.length} left)')),
            ),
          ),
        const SizedBox(height: 60),
      ],
    );
  }

  Widget _tile(Map<String, dynamic> gap) {
    final id = gap['id'] as int;
    final state = gap['state'] as String;
    final validated = state == 'VALIDATED';
    final schemes = ((gap['possible_schemes'] as List?) ?? []).join(', ');
    final reason = (gap['reason'] ?? '').toString();
    final outreach = gap['outreach_status'] == null ? '' : ' \u00b7 ${gap['outreach_channel']}: ${gap['outreach_status']}';
    final details = [
      '${gap['district'] ?? ''}, ${gap['state_name'] ?? ''} \u00b7 ${gap['class_level'] ?? ''}',
      '${_stateLabel(state)}$outreach',
      if (reason.isNotEmpty) reason,
      if (validated && schemes.isNotEmpty) 'May apply: $schemes',
    ].join('\n');

    return InkWell(
      onTap: () => _showActions(gap),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: validated
                  ? Checkbox(
                      value: _selected.contains(id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(id);
                        } else {
                          _selected.remove(id);
                        }
                      }),
                    )
                  : Padding(padding: const EdgeInsets.only(top: 10), child: Icon(_stateIcon(state), color: Colors.grey)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${gap['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(details, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.more_vert), tooltip: 'Fix this gap', onPressed: () => _showActions(gap)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text('${value ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      );
}

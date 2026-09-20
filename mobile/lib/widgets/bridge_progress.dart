import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The "Setu" (bridge) progress indicator described in the README: completed
/// spans are solid teal, the current pier is saffron, pending spans are
/// dashed, and a stage that was skipped (no correction was ever raised)
/// renders as a small dot so the bridge never looks broken.
class BridgeProgress extends StatelessWidget {
  const BridgeProgress({super.key, required this.timeline, required this.stageLabel});

  /// Each item: `{"stage": "APPLICATION", "state": "done"}` — states are one
  /// of done | current | pending | skipped | rejected | blocked.
  final List<dynamic> timeline;
  final String Function(String stage) stageLabel;

  @override
  Widget build(BuildContext context) {
    if (timeline.isEmpty) return const SizedBox.shrink();
    final items = timeline.cast<Map<String, dynamic>>();
    final description = items.map((s) => '${stageLabel(s['stage'] as String)}: ${s['state']}').join(', ');
    return Semantics(
      label: description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 56,
            child: CustomPaint(
              size: const Size(double.infinity, 56),
              painter: _BridgePainter(items.map((e) => e['state'] as String).toList()),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: items.map((s) {
              final state = s['state'] as String;
              return Expanded(
                child: Text(
                  stageLabel(s['stage'] as String),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: state == 'pending' || state == 'blocked' ? Colors.grey : Colors.black87,
                    fontWeight: state == 'current' ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _BridgePainter extends CustomPainter {
  _BridgePainter(this.states);

  final List<String> states;

  Color _pier(String state) {
    switch (state) {
      case 'done':
        return AppColors.primary;
      case 'current':
        return AppColors.accent;
      case 'rejected':
        return AppColors.danger;
      case 'skipped':
        return AppColors.pending;
      case 'blocked':
        return AppColors.pending;
      default:
        return AppColors.pending;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = states.length;
    if (n == 0) return;
    final midY = size.height * 0.45;
    final step = size.width / n;
    final centers = List.generate(n, (i) => step * i + step / 2);

    final deckPaint = Paint()
      ..color = AppColors.pending.withOpacity(0.5)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(centers.first, midY), Offset(centers.last, midY), deckPaint);

    for (var i = 0; i < n - 1; i++) {
      final a = states[i];
      final b = states[i + 1];
      final done = (a == 'done' || a == 'current') && (b == 'done' || b == 'current' || b == 'skipped');
      final p1 = Offset(centers[i], midY);
      final p2 = Offset(centers[i + 1], midY);
      final isSkippedSpan = a == 'skipped' || b == 'skipped';
      if (isSkippedSpan) continue; // no span drawn into/out of a skipped stage — it's a dot, not a pier
      final spanPaint = Paint()
        ..strokeWidth = done ? 4 : 2
        ..color = done ? AppColors.primary : AppColors.pending.withOpacity(0.6)
        ..strokeCap = StrokeCap.round;
      if (done) {
        canvas.drawLine(p1, p2, spanPaint);
      } else {
        _dashedLine(canvas, p1, p2, spanPaint);
      }
    }

    for (var i = 0; i < n; i++) {
      final state = states[i];
      final c = Offset(centers[i], midY);
      if (state == 'skipped') {
        canvas.drawCircle(c, 3.5, Paint()..color = _pier(state));
        continue;
      }
      final radius = state == 'current' ? 9.0 : 7.0;
      canvas.drawCircle(c, radius, Paint()..color = _pier(state));
      if (state == 'current') {
        canvas.drawCircle(
          c,
          radius + 4,
          Paint()
            ..color = AppColors.accent.withOpacity(0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      if (state == 'rejected') {
        final xPaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 2;
        canvas.drawLine(c + const Offset(-3, -3), c + const Offset(3, 3), xPaint);
        canvas.drawLine(c + const Offset(-3, 3), c + const Offset(3, -3), xPaint);
      }
    }
  }

  void _dashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 5.0, gapWidth = 4.0;
    final total = (p2 - p1).distance;
    final dir = (p2 - p1) / total;
    var travelled = 6.0; // leave a small gap around the pier
    while (travelled < total - 6.0) {
      final start = p1 + dir * travelled;
      final endDist = (travelled + dashWidth) < (total - 6.0) ? (travelled + dashWidth) : (total - 6.0);
      final end = p1 + dir * endDist;
      canvas.drawLine(start, end, paint);
      travelled += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(covariant _BridgePainter oldDelegate) => oldDelegate.states.join() != states.join();
}

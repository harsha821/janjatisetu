import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../state/student_state.dart';
import 'wallet_screen.dart';

/// Full-screen smart verification checklist for a single application.
///
/// Shows:
///  • A circular progress ring: "X / Y Verifications Completed"
///  • One stepper card per required document step
///  • A sticky "Run Verification" bottom bar
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    super.key,
    required this.applicationId,
    required this.schemeCode,
  });

  final int applicationId;
  final String schemeCode;

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _checklist;
  bool _loading = true;
  bool _verifying = false;
  String? _error;

  late final AnimationController _ringController;
  late Animation<double> _ringAnimation;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _ringAnimation = const AlwaysStoppedAnimation(0.0);
    _loadChecklist();
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  Future<void> _loadChecklist() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<StudentState>().api;
    try {
      final data = await api.getVerificationChecklist(widget.applicationId);
      final total = (data['total'] as int? ?? 0);
      final verified = (data['verified'] as int? ?? 0);
      final fraction = total > 0 ? verified / total : 0.0;

      _ringAnimation = Tween<double>(begin: 0.0, end: fraction).animate(
        CurvedAnimation(parent: _ringController, curve: Curves.easeOutCubic),
      );
      _ringController.forward(from: 0);

      setState(() {
        _checklist = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'Could not load checklist.';
      });
    }
  }

  Future<void> _runVerification() async {
    setState(() => _verifying = true);
    final api = context.read<StudentState>().api;
    try {
      await api.verifyProfile();
      await _loadChecklist();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Verification run completed'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _uploadForStep(Map<String, dynamic> step) async {
    final docType = step['doc_type'] as String? ?? '';
    final chosen = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => WalletScreen(pickDocType: docType)),
    );
    if (chosen == null) return;
    // After upload/selection, reload the checklist to reflect the new status.
    await _loadChecklist();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Verification Checklist'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    Expanded(child: _buildContent()),
                    _buildBottomBar(),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.pending),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadChecklist,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final steps = (_checklist?['steps'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final total = _checklist?['total'] as int? ?? 0;
    final verified = _checklist?['verified'] as int? ?? 0;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildProgressHeader(verified, total)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _buildStepCard(steps[i], i + 1),
              childCount: steps.length,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- header

  Widget _buildProgressHeader(int verified, int total) {
    final fraction = total > 0 ? verified / total : 0.0;
    final isComplete = verified == total && total > 0;
    final ringColor = isComplete
        ? AppColors.success
        : fraction > 0.5
            ? const Color(0xFFF59E0B) // amber
            : AppColors.accent;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF003D8F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // Circular ring
          AnimatedBuilder(
            animation: _ringAnimation,
            builder: (_, __) => SizedBox(
              width: 90,
              height: 90,
              child: CustomPaint(
                painter: _RingPainter(
                  fraction: _ringAnimation.value,
                  ringColor: ringColor,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$verified',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        'of $total',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isComplete
                      ? 'All Verifications Complete!'
                      : '$verified / $total Verifications Completed',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isComplete
                      ? 'Your application is fully verified and ready.'
                      : 'Upload missing documents or run verification to proceed.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                // Mini progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AnimatedBuilder(
                    animation: _ringAnimation,
                    builder: (_, __) => LinearProgressIndicator(
                      value: _ringAnimation.value,
                      minHeight: 6,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- step card

  Widget _buildStepCard(Map<String, dynamic> step, int index) {
    final status = step['status'] as String? ?? 'PENDING';
    final label = step['label'] as String? ?? '';
    final purpose = step['purpose'] as String? ?? '';
    final required = step['required'] as bool? ?? true;
    final applicable = step['applicable'] as bool? ?? true;
    final source = step['source'] as String? ?? '';

    final bool isVerified = status == 'VERIFIED';
    final bool isNa = status == 'NOT_APPLICABLE';
    final bool isPending = status == 'PENDING';

    Color badgeColor;
    IconData badgeIcon;
    if (isVerified) {
      badgeColor = AppColors.success;
      badgeIcon = Icons.check_rounded;
    } else if (isNa) {
      badgeColor = AppColors.pending;
      badgeIcon = Icons.remove_rounded;
    } else {
      badgeColor = const Color(0xFFF59E0B);
      badgeIcon = Icons.radio_button_unchecked_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isNa
            ? const Color(0xFFF8FAFC)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isVerified
              ? AppColors.success.withValues(alpha: 0.3)
              : isNa
                  ? const Color(0xFFE2EEF8)
                  : const Color(0xFFFEF3C7),
          width: 1.2,
        ),
        boxShadow: isNa
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: badgeColor, width: 1.5),
              ),
              child: Center(
                child: isVerified
                    ? Icon(badgeIcon, size: 18, color: badgeColor)
                    : Text(
                        isNa ? '—' : '$index',
                        style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: isNa ? Colors.black38 : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(status: status, required: required),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    purpose,
                    style: TextStyle(
                      fontSize: 12,
                      color: isNa ? Colors.black26 : Colors.black54,
                    ),
                  ),
                  if (!required && applicable) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Optional — attach if your state requires it',
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                  if (isPending && applicable) ...[
                    const SizedBox(height: 10),
                    _buildActionRow(step, source),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(Map<String, dynamic> step, String source) {
    final isDigiLockerSource =
        source == 'EDISTRICT' || source == 'APAAR' || source == 'AISHE' || source == 'UDISE';

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _ActionButton(
          label: 'Upload Document',
          icon: Icons.upload_file_rounded,
          color: AppColors.primary,
          onTap: () => _uploadForStep(step),
        ),
        if (isDigiLockerSource)
          _ActionButton(
            label: 'Verify via DigiLocker',
            icon: Icons.verified_user_rounded,
            color: const Color(0xFF0D9488),
            onTap: () => _uploadForStep(step), // opens wallet which has DigiLocker tab
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- bottom bar

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2EEF8))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _verifying ? null : _runVerification,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: _verifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.verified_rounded, size: 20),
            label: Text(
              _verifying ? 'Running verification…' : 'Run Verification',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================== helpers

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.required});

  final String status;
  final bool required;

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;
    bool dashed = false;

    switch (status) {
      case 'VERIFIED':
        bgColor = AppColors.success.withValues(alpha: 0.12);
        textColor = AppColors.success;
        label = 'Verified';
      case 'NOT_APPLICABLE':
        bgColor = Colors.transparent;
        textColor = AppColors.pending;
        label = 'Not Required';
        dashed = true;
      default: // PENDING
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFB45309);
        label = required ? 'Pending' : 'Optional';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: dashed
            ? Border.all(
                color: AppColors.pending.withValues(alpha: 0.5), width: 1)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for the circular progress ring.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.ringColor});

  final double fraction;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.shortestSide / 2) - 6;
    const strokeWidth = 7.0;

    // Track
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(cx, cy), radius, trackPaint);

    // Filled arc
    if (fraction > 0) {
      final arcPaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        -math.pi / 2,
        2 * math.pi * fraction,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.ringColor != ringColor;
}

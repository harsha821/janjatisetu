import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../state/student_state.dart';
import '../../widgets/bridge_progress.dart';
import '../../widgets/common.dart';
import 'application_screen.dart';
import 'schemes_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<StudentState>().loadAll());
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = Strings(session.language);
    final state = context.watch<StudentState>();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FD),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF002970),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.hub_outlined, color: Color(0xFF00BAF2), size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              s.appName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5),
            ),
          ],
        ),
        actions: [
          if (state.pendingSyncCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                backgroundColor: const Color(0xFF00BAF2).withValues(alpha: 0.2),
                side: BorderSide.none,
                avatar: const Icon(Icons.sync, color: Color(0xFF00BAF2), size: 16),
                label: Text(
                  '${state.pendingSyncCount} Sync',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  await state.flushOutbox();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Offline changes synced successfully')));
                  }
                },
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => context.read<StudentState>().loadAll(),
        child: _body(context, s, state, session),
      ),
    );
  }

  Widget _body(BuildContext context, Strings s, StudentState state, Session session) {
    if (state.loading && state.dashboard == null) return const LoadingView();
    if (state.error != null && state.dashboard == null) {
      return ListView(children: [
        const SizedBox(height: 80),
        ErrorView(message: state.error!, onRetry: () => context.read<StudentState>().loadAll()),
      ]);
    }
    final dash = state.dashboard;
    if (dash == null) return const LoadingView();
    final student = (dash['student'] as Map?) ?? {};
    final apps = (dash['applications'] as List?) ?? [];
    final nextStep = dash['next_step'] as Map?;
    final totals = (dash['totals'] as Map?) ?? {};

    final studentName = (student['name'] as String? ?? 'Student').trim();
    final initial = studentName.isNotEmpty ? studentName[0].toUpperCase() : 'S';
    final profilePercent = student['profile_percent'] ?? 0;
    final isVerified = student['verification'] == 'VERIFIED';

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        if (state.offline) Padding(padding: const EdgeInsets.only(bottom: 12), child: OfflineBanner(text: s.offline)),

        // Multilingual Language Bar
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2EEF8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF002970).withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.translate, size: 16, color: Color(0xFF002970)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: Strings.supportedLanguages.map((l) {
                      final isSelected = session.language == l['code'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => session.setLanguage(l['code']!),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF002970) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              l['native']!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Premium Hero Card
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF002970), Color(0xFF004B99), Color(0xFF00BAF2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF002970).withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(color: Color(0xFF002970), fontWeight: FontWeight.bold, fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${s.greeting}, $studentName',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                            ),
                            if (isVerified) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified, color: Color(0xFF00B97A), size: 18),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isVerified ? '✓ Identity & DBT Verified' : 'Ministry of Tribal Affairs Portal',
                          style: const TextStyle(color: Color(0xFFE0F2FE), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        Text('$profilePercent%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(s.profile, style: const TextStyle(color: Color(0xFFE0F7FF), fontSize: 9)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (profilePercent as num) / 100,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00B97A)),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Quick Action Grid (Paytm/BHIM style)
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.school_outlined,
                iconColor: const Color(0xFF002970),
                bgColor: const Color(0xFFE6F0FA),
                title: 'Schemes',
                subtitle: 'Find & Apply',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchemesScreen())),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.verified_user_outlined,
                iconColor: const Color(0xFF00897B),
                bgColor: const Color(0xFFE0F2F1),
                title: 'NSP OTR',
                subtitle: 'One Time Reg',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchemesScreen())),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: const Color(0xFFE65100),
                bgColor: const Color(0xFFFFF3E0),
                title: 'Wallet',
                subtitle: 'DigiLocker',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open the Wallet tab for stored certificates.'))),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Financial & Disbursement Cards
        if ((totals['sanctioned'] ?? 0) > 0 || (totals['paid'] ?? 0) > 0) ...[
          Row(
            children: [
              Expanded(
                child: _MoneyCard(
                  label: 'Total Sanctioned',
                  amount: totals['sanctioned'],
                  icon: Icons.assignment_turned_in_outlined,
                  color: const Color(0xFF002970),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MoneyCard(
                  label: 'Direct DBT Paid',
                  amount: totals['paid'],
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF00B97A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Action required card (if any)
        if (nextStep != null) ...[
          _NextStepCard(nextStep: nextStep, onTap: () => _openNextStep(context, nextStep)),
          const SizedBox(height: 14),
        ],

        // Applications Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              s.yourApplications,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchemesScreen())),
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text('New Application', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),

        if (apps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: EmptyView(message: s.noApplicationsYet, icon: Icons.description_outlined),
          )
        else
          ...apps.map((a) => _ApplicationCard(app: a as Map<String, dynamic>, s: s)),

        const SizedBox(height: 40),
      ],
    );
  }

  void _openNextStep(BuildContext context, Map nextStep) {
    final kind = nextStep['kind'];
    if (kind == 'DEFICIENCY' || kind == 'DRAFT') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApplicationScreen(applicationId: nextStep['application_id'] as int)));
    } else if (kind == 'APPLY') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchemesScreen()));
    } else if (kind == 'PROFILE') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open the Profile tab to add more details.')));
    }
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
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
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String label;
  final dynamic amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = (amount is num) ? amount as num : 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2EEF8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  '\u20b9${value.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({required this.nextStep, required this.onTap});

  final Map nextStep;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFED7AA)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEA580C).withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEA580C).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.priority_high_rounded, color: Color(0xFFEA580C), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${nextStep['title'] ?? 'Action Required'}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF9A3412)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${nextStep['body'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFC2410C)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFEA580C), size: 14),
          ],
        ),
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.app, required this.s});

  final Map<String, dynamic> app;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    final timeline = (app['timeline'] as List?) ?? [];
    final openDef = (app['open_deficiencies'] as List?) ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApplicationScreen(applicationId: app['id'] as int))),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2EEF8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${app['short_name'] ?? app['scheme_code']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                    ),
                  ),
                  StatusChip(label: s.statusLabel(app['status'] as String), status: app['status'] as String),
                  if (app['auto_verified'] == true) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified, color: AppColors.success, size: 16),
                  ]
                ],
              ),
              if (openDef.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.danger, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${openDef.first['message']}',
                          style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              BridgeProgress(timeline: timeline, stageLabel: s.stageLabel),
            ],
          ),
        ),
      ),
    );
  }
}

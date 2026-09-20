import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/session.dart';
import 'applications_screen.dart';
import 'audit_screen.dart';
import 'coverage_gap_screen.dart';
import 'exceptions_screen.dart';
import 'overview_screen.dart';

/// Bottom-nav shell for VERIFIER / ADMIN roles. Coverage-gap and audit are
/// ADMIN-only per the backend (`admin_only`); verifiers see three tabs.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<Session>().isAdmin;
    final screens = [
      const OverviewScreen(),
      const AdminApplicationsScreen(),
      const ExceptionsScreen(),
      if (isAdmin) const CoverageGapScreen(),
      if (isAdmin) const AuditScreen(),
    ];
    final items = [
      const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Overview'),
      const BottomNavigationBarItem(icon: Icon(Icons.folder_outlined), activeIcon: Icon(Icons.folder), label: 'Applications'),
      const BottomNavigationBarItem(icon: Icon(Icons.flag_outlined), activeIcon: Icon(Icons.flag), label: 'Exceptions'),
      if (isAdmin) const BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Coverage'),
      if (isAdmin) const BottomNavigationBarItem(icon: Icon(Icons.history), activeIcon: Icon(Icons.history), label: 'Audit'),
    ];
    final index = _index.clamp(0, screens.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('JanjatiSetu \u00b7 Ministry'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Log out?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
                  ],
                ),
              );
              if (ok == true) context.read<Session>().logout();
            },
          ),
        ],
      ),
      body: IndexedStack(index: index, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        items: items,
      ),
    );
  }
}

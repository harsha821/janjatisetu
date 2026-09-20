import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../state/session.dart';
import 'home_screen.dart';
import 'jago_screen.dart';
import 'profile_screen.dart';
import 'schemes_screen.dart';
import 'wallet_screen.dart';

class StudentShell extends StatefulWidget {
  const StudentShell({super.key});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _index = 0;

  static const _screens = [HomeScreen(), SchemesScreen(), WalletScreen(), JagoScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    final s = Strings(context.watch<Session>().language);
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home_outlined), activeIcon: const Icon(Icons.home), label: s.home),
          BottomNavigationBarItem(icon: const Icon(Icons.school_outlined), activeIcon: const Icon(Icons.school), label: s.schemes),
          BottomNavigationBarItem(icon: const Icon(Icons.folder_outlined), activeIcon: const Icon(Icons.folder), label: s.wallet),
          const BottomNavigationBarItem(icon: Icon(Icons.forum_outlined), activeIcon: Icon(Icons.forum), label: 'JAGO'),
          BottomNavigationBarItem(icon: const Icon(Icons.person_outline), activeIcon: const Icon(Icons.person), label: s.profile),
        ],
      ),
    );
  }
}

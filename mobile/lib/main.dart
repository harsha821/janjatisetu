import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/storage.dart';
import 'core/theme.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/student/login_screen.dart';
import 'screens/student/student_shell.dart';
import 'state/session.dart';
import 'state/student_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.instance();
  runApp(JanjatiSetuApp(store: store));
}

class JanjatiSetuApp extends StatelessWidget {
  const JanjatiSetuApp({super.key, required this.store});

  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<LocalStore>.value(value: store),
        ChangeNotifierProvider(create: (_) => Session(store)),
        ChangeNotifierProxyProvider<Session, StudentState>(
          create: (ctx) => StudentState(ctx.read<Session>().api, store),
          update: (ctx, session, previous) {
            if (previous == null || previous.api.token != session.api.token) {
              return StudentState(session.api, store);
            }
            return previous;
          },
        ),
      ],
      child: MaterialApp(
        title: 'JanjatiSetu',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const _Root(),
      ),
    );
  }
}

/// Routes to the login screen, the student shell, or the ministry shell
/// depending on who is signed in.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.isSignedIn) return const LoginScreen();
    if (session.isStaff) return const AdminShell();
    return const StudentShell();
  }
}

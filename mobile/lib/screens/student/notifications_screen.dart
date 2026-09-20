import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../state/student_state.dart';
import '../../widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<StudentState>().refreshNotifications());
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'DEFICIENCY':
        return Icons.error_outline;
      case 'PAYMENT':
        return Icons.payments_outlined;
      case 'OUTREACH':
        return Icons.campaign_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = Strings(session.language);
    final state = context.watch<StudentState>();
    final items = state.notifications;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.notifications),
        actions: [
          TextButton(
            onPressed: () async {
              await state.api.markAllRead();
              await state.refreshNotifications();
            },
            child: Text(s.markAllRead, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => state.refreshNotifications(),
        child: items.isEmpty
            ? ListView(children: [const SizedBox(height: 120), EmptyView(message: s.noNotifications, icon: Icons.notifications_none)])
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final n = items[i] as Map<String, dynamic>;
                  final unread = n['is_read'] == false;
                  return ListTile(
                    tileColor: unread ? AppColors.primary.withOpacity(0.05) : null,
                    leading: Icon(_iconFor(n['kind'] as String), color: unread ? AppColors.primary : Colors.grey),
                    title: Text('${n['title']}', style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text('${n['body']}'),
                    onTap: () async {
                      if (unread) {
                        await state.api.markNotificationRead(n['id'] as int);
                        await state.refreshNotifications();
                      }
                    },
                  );
                },
              ),
      ),
    );
  }
}

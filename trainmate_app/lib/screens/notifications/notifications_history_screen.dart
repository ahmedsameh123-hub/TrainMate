import 'package:flutter/material.dart';

import '../../services/notification_service.dart';

class NotificationsHistoryScreen extends StatefulWidget {
  const NotificationsHistoryScreen({super.key});

  @override
  State<NotificationsHistoryScreen> createState() =>
      _NotificationsHistoryScreenState();
}

class _NotificationsHistoryScreenState
    extends State<NotificationsHistoryScreen> {
  List<NotificationRecord> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await NotificationService.instance.getHistory();
    if (!mounted) return;
    setState(() {
      _items = records;
      _loading = false;
    });
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'daily':
        return 'Plan reminder';
      case 'feedback':
        return 'Feedback';
      default:
        return 'General';
    }
  }

  Color _kindColor(BuildContext context, String kind) {
    final cs = Theme.of(context).colorScheme;
    switch (kind) {
      case 'daily':
        return cs.primaryContainer;
      case 'feedback':
        return cs.secondaryContainer;
      default:
        return cs.surfaceContainerHighest;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications history'),
        actions: [
          TextButton(
            onPressed: _items.isEmpty
                ? null
                : () async {
                    await NotificationService.instance.clearHistory();
                    if (!mounted) return;
                    setState(() => _items = const []);
                  },
            child: const Text('Clear'),
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
              ),
            )
          : _items.isEmpty
          ? const Center(child: Text('No notifications yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final n = _items[i];
                return Card(
                  child: ListTile(
                    title: Text(n.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.body),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _kindColor(context, n.kind),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _kindLabel(n.kind),
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (!n.read)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    trailing: Text(
                      n.createdAtIso.substring(0, 16).replaceFirst('T', '\n'),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall,
                    ),
                    onTap: () async {
                      await NotificationService.instance.markAsRead(n.id);
                      await _load();
                    },
                  ),
                );
              },
            ),
    );
  }
}

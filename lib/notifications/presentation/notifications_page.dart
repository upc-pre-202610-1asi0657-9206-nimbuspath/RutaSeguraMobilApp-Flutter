import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../trip_execution/application/agenda_provider.dart';
import '../application/driver_push_controller.dart';
import '../application/notification_inbox.dart';
import '../domain/model/driver_notification.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({this.initialId, super.key});
  final String? initialId;
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  bool _loadingMore = false;
  @override
  void initState() {
    super.initState();
    if (widget.initialId != null)
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _open(widget.initialId!),
      );
  }

  void _error() {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo consultar el aviso. Revisa la conexion y tu acceso.',
          ),
        ),
      );
  }

  Future<void> _open(String id) async {
    try {
      final notice = await ref
          .read(notificationInboxProvider.notifier)
          .open(id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Text(notice.body),
                const SizedBox(height: 24),
                if (notice.tripId != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.route),
                    label: const Text('Consultar agenda actualizada'),
                    onPressed: () {
                      ref.invalidate(agendaProvider);
                      Navigator.pop(context);
                      this.context.go('/');
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      _error();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(notificationInboxProvider);
    final push = ref.watch(driverPushControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Revisa los avisos cuando estes detenido en un lugar seguro.',
            ),
          ),
          SwitchListTile(
            title: const Text('Avisos push en este celular'),
            value: push.enabled,
            subtitle: Text(
              push.message ??
                  'Viajes, inasistencias, SOS atendidos y comunicados.',
            ),
            onChanged: push.busy
                ? null
                : (enabled) async {
                    final controller = ref.read(
                      driverPushControllerProvider.notifier,
                    );
                    if (enabled) {
                      await controller.enable();
                    } else {
                      await controller.disable();
                    }
                  },
          ),
          const Divider(),
          Expanded(
            child: inbox.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () =>
                      ref.read(notificationInboxProvider.notifier).refresh(),
                  child: const Text('Reintentar cargar la bandeja'),
                ),
              ),
              data: (page) => RefreshIndicator(
                onRefresh: ref.read(notificationInboxProvider.notifier).refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (page.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Aun no tienes notificaciones.'),
                      ),
                    for (final notice in page.items) _tile(notice),
                    if (page.nextCursor != null)
                      TextButton(
                        onPressed: _loadingMore
                            ? null
                            : () async {
                                setState(() => _loadingMore = true);
                                try {
                                  await ref
                                      .read(notificationInboxProvider.notifier)
                                      .loadMore();
                                } catch (_) {
                                  _error();
                                } finally {
                                  if (mounted)
                                    setState(() => _loadingMore = false);
                                }
                              },
                        child: const Text('Cargar anteriores'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(DriverNotification notice) => ListTile(
    leading: Icon(switch (notice.category) {
      'TripAssigned' => Icons.event_available,
      'TripCancelled' => Icons.event_busy,
      'SosResolved' => Icons.health_and_safety_outlined,
      'StudentAbsent' => Icons.person_off_outlined,
      _ => Icons.campaign_outlined,
    }, color: AppColors.navy),
    title: Text(
      notice.title,
      style: TextStyle(
        fontWeight: notice.readAt == null ? FontWeight.bold : FontWeight.normal,
      ),
    ),
    subtitle: Text(notice.body, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: notice.readAt == null
        ? const Icon(Icons.circle, size: 10, color: AppColors.navy)
        : null,
    onTap: () => _open(notice.id),
  );
}

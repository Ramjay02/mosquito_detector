import 'package:flutter/material.dart';

import 'app_info.dart';
import 'auth/auth_config.dart';
import 'auth/auth_controller.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.controller});

  final AuthController? controller;

  String _initials(AuthUser? user) {
    final String name = user?.fullName.trim() ?? '';
    if (name.isEmpty) return '?';
    final List<String> parts = name
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  String _role(String role) {
    if (role == 'admin') return 'Administrator';
    if (role == 'field_worker') return 'Field worker';
    return role.isEmpty ? 'Unknown' : role;
  }

  String _date(DateTime? value) {
    if (value == null) return 'Unknown';
    final DateTime local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final AuthUser? user = controller?.currentUser;
    final DateTime? validUntil = controller?.lastOnlineVerifiedAt?.add(
      AuthConfig.offlineWindow,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      _initials(user),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.fullName.isNotEmpty == true
                        ? user!.fullName
                        : 'Not signed in',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (user != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(user.email),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        Chip(label: Text(_role(user.role))),
                        Chip(label: Text(user.status)),
                        if (controller?.isOfflineMode == true)
                          const Chip(
                            avatar: Icon(Icons.cloud_off, size: 18),
                            label: Text('Offline mode'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: const Text('Last online check'),
                  subtitle: Text(_date(controller?.lastOnlineVerifiedAt)),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Offline access valid until'),
                  subtitle: Text(_date(validUntil)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey<String>('profile-refresh-status'),
            onPressed: controller == null
                ? null
                : () async {
                    await controller!.refreshStatus();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Status refreshed')),
                      );
                    }
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh status'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey<String>('profile-sign-out'),
            onPressed: controller == null
                ? null
                : () async {
                    final bool? confirm = await showDialog<bool>(
                      context: context,
                      builder: (BuildContext dialogContext) {
                        return AlertDialog(
                          title: const Text('Sign out?'),
                          content: const Text(
                            'Your scan records and photos will stay on this device.',
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: const Text('Sign out'),
                            ),
                          ],
                        );
                      },
                    );
                    if (confirm == true) {
                      await controller!.signOut();
                    }
                  },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('About', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Waya-waya Scanner'),
                  Text('Version $kAppVersion'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Scan records and photos are stored on this device only. '
                'Location is not collected.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

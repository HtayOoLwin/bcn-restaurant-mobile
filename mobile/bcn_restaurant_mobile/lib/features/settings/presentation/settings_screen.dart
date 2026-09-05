import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/app_config.dart';
import '../../auth/presentation/auth_controller.dart';

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  final build = info.buildNumber.trim();
  return build.isEmpty ? 'v${info.version}' : 'v${info.version} ($build)';
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(authControllerProvider).asData?.value.bootstrap;
    final version = ref.watch(appVersionProvider);

    return SettingsView(
      fullName: bootstrap?.fullName ?? '',
      user: bootstrap?.user ?? '',
      serverUrl: AppConfig.baseUrl,
      appVersion: version.asData?.value ?? 'Loading…',
      showPrinterSetup: bootstrap?.permissions.canViewPrintStatus == true,
      onPrinterSetup: () => context.push('/printer-settings'),
      onLogout: () => ref.read(authControllerProvider.notifier).logout(),
    );
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.fullName,
    required this.user,
    required this.serverUrl,
    required this.appVersion,
    required this.showPrinterSetup,
    required this.onPrinterSetup,
    required this.onLogout,
  });

  final String fullName;
  final String user;
  final String serverUrl;
  final String appVersion;
  final bool showPrinterSetup;
  final VoidCallback onPrinterSetup;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Printer, server and account settings',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: colors.primaryContainer,
                          foregroundColor: colors.onPrimaryContainer,
                          child: const Icon(Icons.person),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fullName.isEmpty ? 'Logged In User' : fullName,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (user.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(user),
                              ],
                            ],
                          ),
                        ),
                        const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.link,
                        title: 'Server URL',
                        subtitle: serverUrl,
                      ),
                      if (showPrinterSetup) ...[
                        const Divider(height: 1, indent: 72),
                        _SettingsTile(
                          icon: Icons.print,
                          title: 'Windows Print Service',
                          subtitle: 'Server-managed printer jobs and status',
                          onTap: onPrinterSetup,
                        ),
                      ],
                      const Divider(height: 1, indent: 72),
                      _SettingsTile(
                        icon: Icons.info_outline,
                        title: 'App Version',
                        subtitle: appVersion,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Log Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                    side: BorderSide(color: colors.error),
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colors.onPrimaryContainer),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    );
  }
}

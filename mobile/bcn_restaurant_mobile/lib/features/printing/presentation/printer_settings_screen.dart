import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';

class PrinterSettingsScreen extends ConsumerWidget {
  const PrinterSettingsScreen({super.key, this.initialJobContext});

  // Retained only for route compatibility while the old mobile print-status
  // route payload is phased out. The polling queue no longer consumes it.
  final Object? initialJobContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref
        .watch(authControllerProvider)
        .asData
        ?.value
        .bootstrap
        ?.permissions;

    if (permissions?.canViewPrintStatus != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('Android Printer Worker')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You are not authorized to view printer information.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Android Printer Worker')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.print_outlined, size: 32),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Android Printer Worker',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        Text(
                          'The Android printer worker polls OurCity for pending print jobs and sends them to the configured Kitchen, Bar, or Service printer. Printed quantities are acknowledged back to ERPNext through the printer worker APIs.',
                        ),
                        SizedBox(height: 12),
                        Text('Kitchen ticket polling uses bcn_get_pending_print_jobs_printer and bcn_update_print_job_printer. Print and reprint bills can still be requested from the Cashier screen.'),
                      ],
                    ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../data/windows_print_repository.dart';
import '../domain/known_print_job_controller.dart';
import '../domain/windows_print_status.dart';

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key, this.initialJobContext});

  final KnownPrintJobContext? initialJobContext;

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  bool _retryPending = false;
  bool _testPrintPending = false;

  Future<void> _retryJob(KnownPrintJobContext jobContext) async {
    if (_retryPending) return;
    setState(() => _retryPending = true);
    final repository = ref.read(windowsPrintRepositoryProvider);
    try {
      await repository.retryJob(jobContext.jobId);
      if (!mounted) return;
      _show('Print job queued for retry.');
    } catch (error) {
      if (!mounted) return;
      _show(error.toString());
    } finally {
      if (mounted) {
        ref.invalidate(windowsPrintStatusProvider);
        setState(() => _retryPending = false);
      }
    }
  }

  Future<void> _testCashierPrint(KnownPrintJobContext jobContext) async {
    if (_testPrintPending || !jobContext.hasSubmittedInvoice) return;
    setState(() => _testPrintPending = true);
    final repository = ref.read(windowsPrintRepositoryProvider);
    try {
      final result = await repository.requestCashierBill(
        jobContext.invoiceName,
      );
      if (!mounted) return;
      ref
          .read(lastAcceptedPrintJobProvider.notifier)
          .retain(
            KnownPrintJobContext(
              invoiceName: jobContext.invoiceName,
              invoiceDocstatus: jobContext.invoiceDocstatus,
              request: result,
            ),
          );
      _show('Print job sent');
    } catch (error) {
      if (!mounted) return;
      _show(error.toString());
    } finally {
      if (mounted) {
        ref.invalidate(windowsPrintStatusProvider);
        setState(() => _testPrintPending = false);
      }
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref
        .watch(authControllerProvider)
        .asData
        ?.value
        .bootstrap
        ?.permissions;
    if (permissions?.canViewPrintStatus != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('Windows Print Service')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You are not authorized to view print status.'),
          ),
        ),
      );
    }

    final status = ref.watch(windowsPrintStatusProvider);
    final retainedJob = ref.watch(lastAcceptedPrintJobProvider);
    final knownJob = retainedJob ?? widget.initialJobContext;
    final failedCount = status.asData?.value.failed;
    final canRetry = permissions?.canRetryPrintJobs == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Windows Print Service'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(windowsPrintStatusProvider),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh print status',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                status.when(
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (error, _) => _StatusError(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(windowsPrintStatusProvider),
                  ),
                  data: (value) => Column(
                    children: [
                      _ServiceStatusCard(status: value),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _CountCard(
                              label: 'Pending',
                              count: value.pending,
                              icon: Icons.schedule,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _CountCard(
                              label: 'Failed',
                              count: value.failed,
                              icon: Icons.error_outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (knownJob != null) ...[
                  const SizedBox(height: 16),
                  _KnownJobCard(jobContext: knownJob),
                ],
                if (canRetry && knownJob != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _retryPending ? null : () => _retryJob(knownJob),
                    icon: _retryPending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_retryPending ? 'Retrying…' : 'Retry This Job'),
                  ),
                ],
                if (failedCount != null &&
                    failedCount > 0 &&
                    knownJob == null) ...[
                  const SizedBox(height: 16),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Ask an administrator to open Local Print Job in ERPNext to identify and retry failed jobs.',
                      ),
                    ),
                  ),
                ],
                if (knownJob?.hasSubmittedInvoice == true) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _testPrintPending
                        ? null
                        : () => _testCashierPrint(knownJob!),
                    icon: _testPrintPending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print),
                    label: Text(
                      _testPrintPending ? 'Sending…' : 'Test Cashier Print',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KnownJobCard extends StatelessWidget {
  const _KnownJobCard({required this.jobContext});

  final KnownPrintJobContext jobContext;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last accepted print job',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(jobContext.jobId),
            const SizedBox(height: 4),
            Text('Invoice: ${jobContext.invoiceName}'),
            Text('Accepted state: ${jobContext.request.status.rawValue}'),
          ],
        ),
      ),
    );
  }
}

class _ServiceStatusCard extends StatelessWidget {
  const _ServiceStatusCard({required this.status});

  final WindowsPrintStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = status.online ? Colors.green : colors.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              status.online ? Icons.cloud_done : Icons.cloud_off,
              color: color,
              size: 36,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.online ? 'Online' : 'Offline',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Last seen: ${status.lastSeen ?? 'Never'}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.label,
    required this.count,
    required this.icon,
  });

  final String label;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon),
            const SizedBox(height: 8),
            Text('$count', style: Theme.of(context).textTheme.headlineMedium),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _StatusError extends StatelessWidget {
  const _StatusError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry Status'),
            ),
          ],
        ),
      ),
    );
  }
}

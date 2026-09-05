import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../cashier/domain/cashier_models.dart';
import '../data/windows_print_repository.dart';
import '../domain/windows_print_status.dart';

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({
    super.key,
    this.invoice,
    this.canRetryPrintJobs,
  });

  final CashierInvoice? invoice;
  final bool? canRetryPrintJobs;

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  final _jobIdController = TextEditingController();
  bool _retryPending = false;
  bool _testPrintPending = false;

  bool get _hasSubmittedInvoice {
    final invoice = widget.invoice;
    return invoice != null &&
        invoice.docstatus == 1 &&
        invoice.name.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _jobIdController.dispose();
    super.dispose();
  }

  Future<void> _retryJob() async {
    if (_retryPending) return;
    final jobId = _jobIdController.text.trim();
    if (jobId.isEmpty) {
      _show('Enter the failed print job ID.');
      return;
    }

    setState(() => _retryPending = true);
    final repository = ref.read(windowsPrintRepositoryProvider);
    try {
      await repository.retryJob(jobId);
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

  Future<void> _testCashierPrint() async {
    if (_testPrintPending || !_hasSubmittedInvoice) return;
    setState(() => _testPrintPending = true);
    final repository = ref.read(windowsPrintRepositoryProvider);
    try {
      await repository.requestCashierBill(widget.invoice!.name);
      if (!mounted) return;
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(windowsPrintStatusProvider);
    final canRetry =
        widget.canRetryPrintJobs ??
        ref
                .watch(authControllerProvider)
                .asData
                ?.value
                .bootstrap
                ?.permissions
                .canRetryPrintJobs ==
            true;

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
            child: status.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _StatusError(
                message: error.toString(),
                onRetry: () => ref.invalidate(windowsPrintStatusProvider),
              ),
              data: (value) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                  if (canRetry && value.failed > 0) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Retry a failed job',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('failed-print-job-id'),
                              controller: _jobIdController,
                              enabled: !_retryPending,
                              decoration: const InputDecoration(
                                labelText: 'Failed print job ID',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _retryPending ? null : _retryJob,
                              icon: _retryPending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                              label: Text(
                                _retryPending
                                    ? 'Retrying…'
                                    : 'Retry Failed Jobs',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_hasSubmittedInvoice) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _testPrintPending ? null : _testCashierPrint,
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
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: color, fontWeight: FontWeight.w700),
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
    return Center(
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

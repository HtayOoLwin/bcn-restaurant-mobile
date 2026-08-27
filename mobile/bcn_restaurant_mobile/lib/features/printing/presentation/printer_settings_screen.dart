import 'package:flutter/material.dart';

import '../data/direct_printer_service.dart';
import '../data/printer_settings_repository.dart';
import '../domain/printer_config.dart';
import '../services/esc_pos_raster_builder.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final _repository = const PrinterSettingsRepository();
  final _printerService = const DirectPrinterService();
  final _ticketBuilder = const EscPosRasterBuilder();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9100');
  final _footerController = TextEditingController();

  PrinterConfig _config = const PrinterConfig.defaults();
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final value = await _repository.load();
    if (!mounted) return;
    setState(() {
      _config = value;
      _applyConfig(value);
      _loading = false;
    });
  }

  void _applyConfig(PrinterConfig value) {
    _nameController.text = value.printerName;
    _ipController.text = value.wifiIpAddress;
    _portController.text = value.wifiPort.toString();
    _footerController.text = value.footerRemark;
  }

  PrinterConfig _currentConfig() {
    return _config.copyWith(
      printerName: _nameController.text.trim(),
      wifiIpAddress: _ipController.text.trim(),
      wifiPort: int.tryParse(_portController.text.trim()) ?? 9100,
      footerRemark: _footerController.text.trim(),
    );
  }

  Future<void> _chooseBluetoothPrinter() async {
    setState(() => _busy = true);
    try {
      final printers = await _printerService.pairedBluetoothPrinters();
      if (!mounted) return;
      final selected = await showModalBottomSheet<PrinterDevice>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: printers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No paired Bluetooth printers found. Pair the printer in Android Settings first.',
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: printers
                      .map(
                        (printer) => ListTile(
                          leading: const Icon(Icons.print),
                          title: Text(
                            printer.name.isEmpty
                                ? 'Bluetooth Printer'
                                : printer.name,
                          ),
                          subtitle: Text(printer.address),
                          onTap: () => Navigator.of(context).pop(printer),
                        ),
                      )
                      .toList(),
                ),
        ),
      );
      if (selected != null && mounted) {
        setState(() {
          _nameController.text = selected.name;
          _config = _config.copyWith(
            printerName: selected.name,
            bluetoothMacAddress: selected.address,
          );
        });
      }
    } catch (error) {
      _show(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testPrint() async {
    final config = _currentConfig();
    if (!config.isConfigured) {
      _show('Complete the printer connection details first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await _ticketBuilder.buildTestTicket(
        config,
        DateTime.now(),
      );
      final result = await _printerService.printBytes(config, bytes);
      _show(result.message);
    } catch (error) {
      _show('Test print failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final config = _currentConfig();
    await _repository.save(config);
    if (!mounted) return;
    setState(() => _config = config);
    _show('Printer setup saved.');
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Setup'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.sync),
            tooltip: 'Reload',
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
                Text(
                  'Bluetooth or Wi-Fi receipt preferences',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                _SettingsCard(
                  title: 'Printer Interface',
                  child: SegmentedButton<PrinterConnectionType>(
                    segments: const [
                      ButtonSegment(
                        value: PrinterConnectionType.bluetooth,
                        label: Text('Bluetooth'),
                        icon: Icon(Icons.bluetooth),
                      ),
                      ButtonSegment(
                        value: PrinterConnectionType.wifi,
                        label: Text('Wi-Fi'),
                        icon: Icon(Icons.wifi),
                      ),
                    ],
                    selected: {_config.connectionType},
                    onSelectionChanged: _busy
                        ? null
                        : (value) => setState(
                            () => _config = _config.copyWith(
                              connectionType: value.first,
                            ),
                          ),
                  ),
                ),
                _SettingsCard(
                  title: 'Selected Printer',
                  child:
                      _config.connectionType == PrinterConnectionType.bluetooth
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _config.bluetoothMacAddress.isEmpty
                                  ? 'No Bluetooth printer selected'
                                  : '${_nameController.text}\n${_config.bluetoothMacAddress}',
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _chooseBluetoothPrinter,
                              icon: const Icon(Icons.bluetooth_searching),
                              label: const Text('Choose Bluetooth Printer'),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Printer Name (optional)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: _ipController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'IP Address',
                                      hintText: '192.168.1.100',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _portController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Port',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
                _SettingsCard(
                  title: 'Paper Size',
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 58, label: Text('58 mm')),
                      ButtonSegment(value: 80, label: Text('80 mm')),
                    ],
                    selected: {_config.paperWidthMm},
                    onSelectionChanged: (value) => setState(
                      () =>
                          _config = _config.copyWith(paperWidthMm: value.first),
                    ),
                  ),
                ),
                _SettingsCard(
                  title: 'Font Size',
                  child: Column(
                    children: [
                      Slider(
                        value: _config.fontSizePx,
                        min: 15,
                        max: 25,
                        divisions: 10,
                        label: '${_config.fontSizePx.round()}px',
                        onChanged: (value) => setState(
                          () => _config = _config.copyWith(fontSizePx: value),
                        ),
                      ),
                      Text(
                        '${_config.fontSizePx.round()}px',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Sample receipt text\nမြန်မာစာ စမ်းသပ်မှု',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: _config.fontSizePx),
                        ),
                      ),
                    ],
                  ),
                ),
                _SettingsCard(
                  title: 'Receipt Footer',
                  child: TextField(
                    controller: _footerController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Footer remark shown on the cashier bill',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto Cut'),
                  value: _config.autoCut,
                  onChanged: (value) => setState(
                    () => _config = _config.copyWith(autoCut: value),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _testPrint,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print),
                  label: Text(_busy ? 'Please wait…' : 'Test Print'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Printer Setup'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../data/services/system_info_service.dart';

class SystemInfoDialog extends StatefulWidget {
  const SystemInfoDialog({super.key});

  @override
  State<SystemInfoDialog> createState() => _SystemInfoDialogState();
}

class _SystemInfoDialogState extends State<SystemInfoDialog> {
  final SystemInfoService _systemInfoService = SystemInfoService();
  SystemInfo? _systemInfo;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSystemInfo();
  }

  Future<void> _loadSystemInfo() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final systemInfo = await _systemInfoService.getSystemInfo();
      
      if (mounted) {
        setState(() {
          _systemInfo = systemInfo;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.computer,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Expanded(child: Text('System Information')),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSystemInfo,
            tooltip: 'Refresh',
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: SizedBox(
          width: 350,
          child: _buildContent(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading system information...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading system info',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_systemInfo == null) {
      return const Center(
        child: Text('No system information available'),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoSection('Host Information', [
            _buildInfoRow('Hostname', _systemInfo!.hostname, Icons.dns),
            _buildInfoRow('OS', _systemInfo!.osInfo, Icons.computer),
            _buildInfoRow('Kernel', _systemInfo!.kernelInfo, Icons.settings),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection('Performance', [
            _buildInfoRow('Uptime', _systemInfo!.uptime, Icons.schedule),
            _buildInfoRow('Load Average', _systemInfo!.loadAverage, Icons.trending_up),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection('Hardware', [
            _buildInfoRow('CPU', _systemInfo!.cpuInfo, Icons.memory),
            _buildInfoRow('Memory', _systemInfo!.memoryInfo, Icons.storage),
            _buildInfoRow('Disk', _systemInfo!.diskInfo, Icons.storage),
          ]),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
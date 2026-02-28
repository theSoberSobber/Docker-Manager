import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../data/services/pairing_service.dart';
import '../../data/services/subscription_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/ssh_connection_service.dart';
import '../../data/services/docker_cli_path_service.dart';
import '../../data/repositories/server_repository_impl.dart';
import '../../domain/models/server.dart';

/// Screen for setting up Docker event notifications for a server.
///
/// Since the app already has SSH access, we auto-deploy the dm-notifier
/// container — no manual command copying needed!
class NotificationSetupScreen extends StatefulWidget {
  final Server server;

  const NotificationSetupScreen({super.key, required this.server});

  @override
  State<NotificationSetupScreen> createState() =>
      _NotificationSetupScreenState();
}

class _NotificationSetupScreenState extends State<NotificationSetupScreen> {
  final PairingService _pairingService = PairingService();
  final NotificationService _notificationService = NotificationService();
  final ServerRepositoryImpl _serverRepo = ServerRepositoryImpl();

  PairingStatus _status = PairingStatus.notSetup;
  bool _isDeploying = false;
  bool _isChecking = false;
  bool _isRemoving = false;
  String? _error;
  String? _logs;
  String _deployStep = '';

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<String?> _getDockerPath() async {
    // Use server-specific path, or fall back to global
    if (widget.server.dockerCliPath != null &&
        widget.server.dockerCliPath!.isNotEmpty) {
      return widget.server.dockerCliPath;
    }
    return await DockerCliPathService().getDockerCliPath();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isChecking = true;
      _error = null;
    });

    final dockerPath = await _getDockerPath();
    final status = await _pairingService.checkContainerStatus(
      dockerCliPath: dockerPath,
    );

    if (mounted) {
      setState(() {
        _status = status;
        _isChecking = false;
      });
    }
  }

  Future<void> _deployNotifier() async {
    setState(() {
      _isDeploying = true;
      _error = null;
      _deployStep = 'Requesting notification permission...';
    });

    // Request notification permission (only asked here, when user enables the feature)
    await _notificationService.requestPermissionAndToken();

    if (mounted) setState(() => _deployStep = 'Registering device...');
    await _notificationService.registerTokenWithBackend();

    if (mounted) setState(() => _deployStep = 'Generating security token...');
    final token = await _pairingService.generatePairingToken(widget.server.id);
    if (token == null) {
      if (mounted) {
        setState(() {
          _error = 'notifications.token_generation_failed'.tr();
          _isDeploying = false;
          _deployStep = '';
        });
      }
      return;
    }

    // Deploy via SSH with step-by-step progress
    final dockerPath = await _getDockerPath();
    final result = await _pairingService.deployNotifier(
      serverId: widget.server.id,
      pairingToken: token,
      dockerCliPath: dockerPath,
      onProgress: (step) {
        if (mounted) setState(() => _deployStep = step);
      },
    );

    if (mounted) {
      setState(() {
        _isDeploying = false;
        _deployStep = '';
        if (result.success) {
          _status = PairingStatus.running;
        } else {
          _error = result.error;
          _status = PairingStatus.error;
        }
      });

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  result.alreadyRunning
                      ? 'notifications.already_active'.tr()
                      : 'notifications.deploy_success'.tr(),
                )),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
        // Persist enabled flag
        final updated = widget.server.copyWith(notificationsEnabled: true);
        await _serverRepo.updateServer(updated);
      }
    }
  }

  Future<void> _removeNotifier() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('notifications.disable_title'.tr()),
        content: Text('notifications.disable_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text('notifications.disable'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isRemoving = true;
      _error = null;
    });

    final dockerPath = await _getDockerPath();
    final success = await _pairingService.removeNotifier(
      dockerCliPath: dockerPath,
    );

    if (mounted) {
      setState(() {
        _isRemoving = false;
        _status = success ? PairingStatus.notSetup : PairingStatus.error;
      });
      if (success) {
        // Persist disabled flag
        final updated = widget.server.copyWith(notificationsEnabled: false);
        await _serverRepo.updateServer(updated);
      }
    }
  }

  Future<void> _viewLogs() async {
    final dockerPath = await _getDockerPath();
    final logs = await _pairingService.getNotifierLogs(
      dockerCliPath: dockerPath,
    );

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('notifications.logs_title'.tr()),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                logs,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common.close'.tr()),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('notifications.setup_title'.tr()),
        backgroundColor: colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Server info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.dns, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.server.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${widget.server.ip}:${widget.server.port}',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // How it works
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'notifications.how_it_works_title'.tr(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'notifications.how_it_works_description'.tr(),
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Main action section
          if (_status == PairingStatus.running) ...[
            _buildRunningSection(),
          ] else if (_status == PairingStatus.stopped) ...[
            _buildStoppedSection(),
          ] else ...[
            _buildSetupSection(),
          ],

          // Error display
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    if (_isChecking) {
      return const SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final (color, text, icon) = switch (_status) {
      PairingStatus.running => (Colors.green, 'notifications.status_active'.tr(), Icons.check_circle),
      PairingStatus.stopped => (Colors.orange, 'notifications.status_stopped'.tr(), Icons.pause_circle),
      PairingStatus.deploying => (Colors.blue, 'notifications.status_deploying'.tr(), Icons.downloading),
      PairingStatus.error => (Colors.red, 'notifications.status_error'.tr(), Icons.error),
      PairingStatus.notSetup => (Colors.grey, 'notifications.status_not_setup'.tr(), Icons.notifications_off),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildRunningSection() {
    return Column(
      children: [
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'notifications.active_title'.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'notifications.active_description'.tr(),
                  style: TextStyle(color: Colors.green.shade900, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isChecking ? null : _checkStatus,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('notifications.refresh_status'.tr()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _viewLogs,
                icon: const Icon(Icons.article_outlined, size: 18),
                label: Text('notifications.view_logs'.tr()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isRemoving ? null : _removeNotifier,
            icon: _isRemoving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline, size: 18),
            label: Text('notifications.disable'.tr()),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
        ),
      ],
    );
  }

  Widget _buildStoppedSection() {
    return Column(
      children: [
        Card(
          color: Colors.orange.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.pause_circle, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'notifications.stopped_title'.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'notifications.stopped_description'.tr(),
                  style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isDeploying ? null : _deployNotifier,
            icon: _isDeploying
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.restart_alt, size: 18),
            label: Text('notifications.redeploy'.tr()),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _viewLogs,
                icon: const Icon(Icons.article_outlined, size: 18),
                label: Text('notifications.view_logs'.tr()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isRemoving ? null : _removeNotifier,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text('notifications.disable'.tr()),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSetupSection() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _isDeploying ? null : _deployNotifier,
            icon: _isDeploying
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.notifications_active, size: 20),
            label: Text(
              _isDeploying
                  ? (_deployStep.isNotEmpty ? _deployStep : 'notifications.deploying'.tr())
                  : 'notifications.enable'.tr(),
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'notifications.security_note'.tr(),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

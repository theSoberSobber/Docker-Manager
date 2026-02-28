import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';
import 'ssh_connection_service.dart';
import 'subscription_service.dart';

/// Pairing status of a server's dm-notifier connection.
enum PairingStatus {
  notSetup,
  deploying,
  running,
  stopped,
  error,
}

/// Handles deployment and management of the dm-notifier container
/// on the user's server via SSH.
///
/// Since the app already has SSH access to the user's server,
/// we auto-deploy the dm-notifier container — no manual steps needed!
class PairingService {
  static final PairingService _instance = PairingService._internal();
  factory PairingService() => _instance;
  PairingService._internal();

  /// Generate a pairing token for a given server from the backend.
  Future<String?> generatePairingToken(String serverId) async {
    final subscriptionService = SubscriptionService();

    if (subscriptionService.appUserId == null) {
      debugPrint('PairingService: No RevenueCat user ID');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/pairing/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'rc_user_id': subscriptionService.appUserId,
          'server_id': serverId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['token'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('PairingService: Failed to generate token: $e');
      return null;
    }
  }

  /// Deploy the dm-notifier container on the user's server via SSH.
  ///
  /// Smart deployment:
  /// 1. Check if dm-notifier is already running on this server
  /// 2. If running and healthy → skip, return alreadyRunning
  /// 3. If stopped → remove and redeploy
  /// 4. If not found → fresh deploy
  Future<DeployResult> deployNotifier({
    required String serverId,
    required String pairingToken,
    String? dockerCliPath,
    void Function(String status)? onProgress,
  }) async {
    final ssh = SSHConnectionService();
    final docker = dockerCliPath ?? 'docker';

    if (!ssh.isConnected) {
      return DeployResult(
        success: false,
        error: 'Not connected to server via SSH',
      );
    }

    try {
      // Step 1: Check if container already exists and is running
      onProgress?.call('Checking for existing notifier...');
      final existingStatus = await checkContainerStatus(dockerCliPath: dockerCliPath);

      if (existingStatus == PairingStatus.running) {
        debugPrint('PairingService: dm-notifier already running — skipping deploy');
        return DeployResult(success: true, alreadyRunning: true);
      }

      // Step 2: If stopped/exists, clean up first
      if (existingStatus == PairingStatus.stopped) {
        onProgress?.call('Removing stopped container...');
        await ssh.executeCommand('$docker stop ${AppConfig.notifierContainerName} 2>/dev/null || true');
        await ssh.executeCommand('$docker rm ${AppConfig.notifierContainerName} 2>/dev/null || true');
      }

      // Step 3: Pull the latest image
      onProgress?.call('Pulling dm-notifier image...');
      final pullResult = await ssh.executeCommand('$docker pull ${AppConfig.notifierImage}') ?? '';
      if (pullResult.contains('Error') && !pullResult.contains('Pulling from')) {
        return DeployResult(
          success: false,
          error: 'Failed to pull dm-notifier image: $pullResult',
        );
      }

      // Step 4: Run the container with resilient settings
      onProgress?.call('Starting notification agent...');
      final runCommand = '$docker run -d '
          '--name ${AppConfig.notifierContainerName} '
          '--restart unless-stopped '
          '-v /var/run/docker.sock:/var/run/docker.sock:ro '
          '-e PAIRING_TOKEN=$pairingToken '
          '-e BACKEND_URL=${AppConfig.backendBaseUrl} '
          '-e SERVER_ID=$serverId '
          '--memory=64m '
          '--cpus=0.1 '
          '${AppConfig.notifierImage}';

      await ssh.executeCommand(runCommand);

      // Step 5: Verify it's running
      onProgress?.call('Verifying container is healthy...');
      await Future.delayed(const Duration(seconds: 2));
      final statusResult = await ssh.executeCommand(
        '$docker inspect --format="{{.State.Running}}" ${AppConfig.notifierContainerName} 2>/dev/null',
      ) ?? '';

      if (statusResult.trim() == 'true') {
        return DeployResult(success: true);
      } else {
        final logs = await ssh.executeCommand(
          '$docker logs --tail 20 ${AppConfig.notifierContainerName} 2>&1',
        ) ?? 'No logs available';
        return DeployResult(
          success: false,
          error: 'Container started but is not running. Logs:\n$logs',
        );
      }
    } catch (e) {
      debugPrint('PairingService: Deploy failed: $e');
      return DeployResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Check the current status of the dm-notifier container via SSH.
  Future<PairingStatus> checkContainerStatus({String? dockerCliPath}) async {
    final ssh = SSHConnectionService();
    final docker = dockerCliPath ?? 'docker';

    if (!ssh.isConnected) return PairingStatus.error;

    try {
      final result = await ssh.executeCommand(
        '$docker inspect --format="{{.State.Status}}" ${AppConfig.notifierContainerName} 2>/dev/null',
      ) ?? '';

      final status = result.trim().toLowerCase();
      if (status == 'running') return PairingStatus.running;
      if (status == 'exited' || status == 'stopped') return PairingStatus.stopped;
      if (status.contains('error') || status.contains('no such')) {
        return PairingStatus.notSetup;
      }
      return PairingStatus.notSetup;
    } catch (e) {
      debugPrint('PairingService: Status check failed: $e');
      return PairingStatus.error;
    }
  }

  /// Remove the dm-notifier container from the server.
  Future<bool> removeNotifier({String? dockerCliPath}) async {
    final ssh = SSHConnectionService();
    final docker = dockerCliPath ?? 'docker';

    if (!ssh.isConnected) return false;

    try {
      await ssh.executeCommand('$docker stop ${AppConfig.notifierContainerName} 2>/dev/null || true');
      await ssh.executeCommand('$docker rm ${AppConfig.notifierContainerName} 2>/dev/null || true');
      return true;
    } catch (e) {
      debugPrint('PairingService: Remove failed: $e');
      return false;
    }
  }

  /// Get logs from the dm-notifier container.
  Future<String> getNotifierLogs({String? dockerCliPath, int tailLines = 50}) async {
    final ssh = SSHConnectionService();
    final docker = dockerCliPath ?? 'docker';

    if (!ssh.isConnected) return 'Not connected to server';

    try {
      return await ssh.executeCommand(
        '$docker logs --tail $tailLines ${AppConfig.notifierContainerName} 2>&1',
      ) ?? 'No logs available';
    } catch (e) {
      return 'Failed to get logs: $e';
    }
  }
}

class DeployResult {
  final bool success;
  final String? error;
  final bool alreadyRunning;

  DeployResult({required this.success, this.error, this.alreadyRunning = false});
}

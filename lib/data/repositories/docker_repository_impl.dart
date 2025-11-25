import '../../domain/models/docker_container.dart';
import '../../domain/models/docker_image.dart';
import '../../domain/models/docker_volume.dart';
import '../../domain/models/docker_network.dart';
import '../../domain/repositories/docker_repository.dart';
import '../../domain/models/server.dart';
import '../services/ssh_connection_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../main.dart';

class DockerRepositoryImpl implements DockerRepository {
  final SSHConnectionService _sshService = SSHConnectionService();

  /// Get the Docker CLI path: uses per-server path if set, otherwise falls back to global setting
  Future<String> _getDockerCliPath() async {
    // First try to get per-server docker path
    final Server? currentServer = _sshService.currentServer;
    if (currentServer?.dockerCliPath != null && currentServer!.dockerCliPath!.isNotEmpty) {
      return currentServer.dockerCliPath!;
    }
    
    // Fall back to global setting
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('dockerCliPath') ?? 'docker';
  }

  /// Parse Docker error and provide user-friendly message
  String _parseDockerError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    // Check for permission/socket access errors
    if (errorStr.contains('permission denied') || 
        errorStr.contains('docker.sock') ||
        errorStr.contains('connect: permission denied')) {
      return 'Permission denied: Your user cannot access Docker.\n\n'
             'Solution: Add your user to the docker group:\n'
             'sudo usermod -aG docker \$USER\n\n'
             'Then close and reopen this app.';
    }
    
    // Check for Docker not found/installed
    if (errorStr.contains('command not found') || 
        errorStr.contains('docker: not found') ||
        errorStr.contains('no such file or directory')) {
      return 'Docker not found: Docker CLI is not installed or not in PATH.\n\n'
             'Check your Docker installation or configure a custom Docker CLI path in Settings.';
    }
    
    // Check for Docker daemon not running
    if (errorStr.contains('cannot connect to the docker daemon') ||
        errorStr.contains('is the docker daemon running')) {
      return 'Docker daemon not running: The Docker service is not active.\n\n'
             'Start Docker with: sudo systemctl start docker';
    }
    
    // Return original error if no pattern matched
    return error.toString();
  }

  @override
  Future<List<DockerContainer>> getContainers() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      final dockerCli = await _getDockerCliPath();
      
      // Use --format to get structured output including compose labels
      // Using triple quotes and escaping for proper shell execution
      final command = '''$dockerCli ps -a --format '{{.ID}}|{{.Image}}|{{.Command}}|{{.CreatedAt}}|{{.Status}}|{{.Ports}}|{{.Names}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}' ''';
      final result = await _sshService.executeCommand(command);
      
      if (result == null) {
        throw Exception('Docker ps command returned no output');
      }

      // Check if the result contains error messages instead of container data
      if (result.toLowerCase().contains('permission denied') ||
          result.toLowerCase().contains('cannot connect to the docker daemon') ||
          result.toLowerCase().contains('docker: not found')) {
        throw Exception(result);
      }

      return DockerContainer.parseDockerPsOutput(result);
    } catch (e) {
      throw Exception(_parseDockerError(e));
    }
  }

  @override
  Future<Map<String, Map<String, String>>> getContainerStats() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      final dockerCli = await _getDockerCliPath();

      // Get stats for all running containers - use longer timeout as stats can take time
      final command = '''$dockerCli stats --no-stream --format '{{.Container}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}|{{.PIDs}}' ''';
      final result = await _sshService.executeCommand(
        command,
        timeout: const Duration(seconds: 30),
      );
      
      // DEBUG: Show actual command output
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('[STATS OUTPUT] ${result ?? "null"}'),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.orange,
        ),
      );
      
      if (result == null || result.trim().isEmpty) {
        return {}; // No running containers
      }

      // Parse stats into a map: containerId -> {stat_name: value}
      final statsMap = <String, Map<String, String>>{};
      final lines = result.split('\n').where((line) => line.trim().isNotEmpty);
      
      for (final line in lines) {
        final parts = line.split('|');
        if (parts.length >= 7) {
          statsMap[parts[0].trim()] = {
            'cpuPerc': parts[1].trim(),
            'memUsage': parts[2].trim(),
            'memPerc': parts[3].trim(),
            'netIO': parts[4].trim(),
            'blockIO': parts[5].trim(),
            'pids': parts[6].trim(),
          };
        }
      }
      
      return statsMap;
    } catch (e) {
      // DEBUG: Show error
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('[STATS ERROR] ${e.toString()}'),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.red,
        ),
      );
      throw Exception(_parseDockerError(e));
    }
  }

  @override
  Future<List<DockerImage>> getImages() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      final dockerCli = await _getDockerCliPath();
      final result = await _sshService.executeCommand('$dockerCli images');
      
      // DEBUG: Show actual command output
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('[IMAGES OUTPUT] ${result ?? "null"}'),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.orange,
        ),
      );
      
      if (result == null) {
        throw Exception('Docker images command returned no output');
      }

      return DockerImage.parseDockerImagesOutput(result);
    } catch (e) {
      // DEBUG: Show error
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('[IMAGES ERROR] ${e.toString()}'),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.red,
        ),
      );
      throw Exception(_parseDockerError(e));
    }
  }

  @override
  Future<List<DockerVolume>> getVolumes() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      final dockerCli = await _getDockerCliPath();
      final result = await _sshService.executeCommand('$dockerCli volume ls');
      
      if (result == null) {
        throw Exception('Docker volume ls command returned no output');
      }

      return DockerVolume.parseDockerVolumeLsOutput(result);
    } catch (e) {
      throw Exception(_parseDockerError(e));
    }
  }

  @override
  Future<List<DockerNetwork>> getNetworks() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      final dockerCli = await _getDockerCliPath();
      final result = await _sshService.executeCommand('$dockerCli network ls');
      
      if (result == null) {
        throw Exception('Docker network ls command returned no output');
      }

      return DockerNetwork.parseDockerNetworkLsOutput(result);
    } catch (e) {
      throw Exception(_parseDockerError(e));
    }
  }
}
import '../../domain/models/docker_container.dart';
import '../../domain/models/docker_image.dart';
import '../../domain/models/docker_volume.dart';
import '../../domain/models/docker_network.dart';
import '../../domain/repositories/docker_repository.dart';
import '../services/ssh_connection_service.dart';
import '../../core/utils/docker_cli_config.dart';

class DockerRepositoryImpl implements DockerRepository {
  final SSHConnectionService _sshService = SSHConnectionService();

  @override
  Future<List<DockerContainer>> getContainers() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      final dockerCli = await DockerCliConfig.getCliPath();
      
      // Use --format to get structured output including compose labels
      // Using triple quotes and escaping for proper shell execution
      final command = '''$dockerCli ps -a --format '{{.ID}}|{{.Image}}|{{.Command}}|{{.CreatedAt}}|{{.Status}}|{{.Ports}}|{{.Names}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}' ''';
      final result = await _sshService.executeCommand(command);
      
      if (result == null) {
        throw Exception('Docker ps command returned no output');
      }

      return DockerContainer.parseDockerPsOutput(result);
    } catch (e) {
      throw Exception('Failed to get containers: $e');
    }
  }

  @override
  Future<Map<String, Map<String, String>>> getContainerStats() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      final dockerCli = await DockerCliConfig.getCliPath();

      // Get stats for all running containers
      final command = '''$dockerCli stats --no-stream --format '{{.Container}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}|{{.PIDs}}' ''';
      final result = await _sshService.executeCommand(command);
      
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
      throw Exception('Failed to get container stats: $e');
    }
  }

  @override
  Future<List<DockerImage>> getImages() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      final dockerCli = await DockerCliConfig.getCliPath();
      final result = await _sshService.executeCommand('$dockerCli images');
      
      if (result == null) {
        throw Exception('Docker images command returned no output');
      }

      return DockerImage.parseDockerImagesOutput(result);
    } catch (e) {
      throw Exception('Failed to get images: $e');
    }
  }

  @override
  Future<List<DockerVolume>> getVolumes() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      final dockerCli = await DockerCliConfig.getCliPath();
      final result = await _sshService.executeCommand('$dockerCli volume ls');
      
      if (result == null) {
        throw Exception('Docker volume ls command returned no output');
      }

      return DockerVolume.parseDockerVolumeLsOutput(result);
    } catch (e) {
      throw Exception('Failed to get volumes: $e');
    }
  }

  @override
  Future<List<DockerNetwork>> getNetworks() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      final dockerCli = await DockerCliConfig.getCliPath();
      final result = await _sshService.executeCommand('$dockerCli network ls');
      
      if (result == null) {
        throw Exception('Docker network ls command returned no output');
      }

      return DockerNetwork.parseDockerNetworkLsOutput(result);
    } catch (e) {
      throw Exception('Failed to get networks: $e');
    }
  }
}
import '../../domain/models/docker_container.dart';
import '../../domain/models/docker_image.dart';
import '../../domain/models/docker_volume.dart';
import '../../domain/models/docker_network.dart';
import '../../domain/repositories/docker_repository.dart';
import '../services/ssh_connection_service.dart';

class DockerRepositoryImpl implements DockerRepository {
  final SSHConnectionService _sshService = SSHConnectionService();

  @override
  Future<List<DockerContainer>> getContainers() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      // Use --format to get structured output including compose labels
      const format = '{{.ID}}|{{.Image}}|{{.Command}}|{{.CreatedAt}}|{{.Status}}|{{.Ports}}|{{.Names}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}';
      final result = await _sshService.executeCommand('docker ps -a --format "$format"');
      
      if (result == null) {
        throw Exception('Docker ps command returned no output');
      }

      return DockerContainer.parseDockerPsOutput(result);
    } catch (e) {
      throw Exception('Failed to get containers: $e');
    }
  }

  @override
  Future<List<DockerImage>> getImages() async {
    try {
      if (!_sshService.isConnected) {
        throw Exception('No SSH connection available');
      }

      final result = await _sshService.executeCommand('docker images');
      
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

      final result = await _sshService.executeCommand('docker volume ls');
      
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

      final result = await _sshService.executeCommand('docker network ls');
      
      if (result == null) {
        throw Exception('Docker network ls command returned no output');
      }

      return DockerNetwork.parseDockerNetworkLsOutput(result);
    } catch (e) {
      throw Exception('Failed to get networks: $e');
    }
  }
}
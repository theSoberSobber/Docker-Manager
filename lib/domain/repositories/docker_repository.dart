import '../models/docker_container.dart';
import '../models/docker_image.dart';
import '../models/docker_volume.dart';
import '../models/docker_network.dart';

abstract class DockerRepository {
  /// Get all containers (running and stopped)
  Future<List<DockerContainer>> getContainers();
  
  /// Get container stats (CPU, memory, network, etc.)
  Future<Map<String, Map<String, String>>> getContainerStats();
  
  /// Get all images
  Future<List<DockerImage>> getImages();
  
  /// Get all volumes
  Future<List<DockerVolume>> getVolumes();
  
  /// Get all networks
  Future<List<DockerNetwork>> getNetworks();
}
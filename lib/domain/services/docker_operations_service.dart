/// Domain service for Docker resource operations (stop, start, remove, etc.)
/// This separates business logic from presentation layer
abstract class DockerOperationsService {
  // Container operations
  Future<String> getContainerLogsCommand(String containerId, {String logLines = '500'});
  Future<String> getInspectContainerCommand(String containerId);
  Future<void> stopContainer(String containerId);
  Future<void> startContainer(String containerId);
  Future<void> restartContainer(String containerId);
  Future<void> removeContainer(String containerId);

  // Image operations
  Future<String> getInspectImageCommand(String imageId);
  Future<void> removeImage(String imageId);

  // Volume operations
  Future<String> getInspectVolumeCommand(String volumeName);
  Future<void> removeVolume(String volumeName);

  // Network operations
  Future<String> getInspectNetworkCommand(String networkId);
  Future<void> removeNetwork(String networkId);
  Future<void> connectContainerToNetwork(String networkId, String containerId);
  Future<void> disconnectContainerFromNetwork(String networkId, String containerId);
}

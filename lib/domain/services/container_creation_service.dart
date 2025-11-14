/// Domain service for container creation operations
/// Handles building Docker run commands and creating containers
abstract class ContainerCreationService {
  /// Create a container with the given configuration
  Future<String> createContainer(ContainerCreationConfig config);
  
  /// Build a docker run command from configuration (for preview/debugging)
  String buildDockerRunCommand(ContainerCreationConfig config);
}

/// Configuration for creating a new container
class ContainerCreationConfig {
  final String imageName;
  final String imageTag;
  final String? containerName;
  final List<PortMapping> portMappings;
  final List<EnvironmentVariable> environmentVariables;
  final List<VolumeMount> volumeMounts;
  final String restartPolicy;
  final String? workingDirectory;
  final String? memoryLimit;
  final String? cpuLimit;
  final String networkMode;
  final bool privileged;
  final String? commandOverride;

  ContainerCreationConfig({
    required this.imageName,
    required this.imageTag,
    this.containerName,
    this.portMappings = const [],
    this.environmentVariables = const [],
    this.volumeMounts = const [],
    this.restartPolicy = 'no',
    this.workingDirectory,
    this.memoryLimit,
    this.cpuLimit,
    this.networkMode = 'default',
    this.privileged = false,
    this.commandOverride,
  });
}

class PortMapping {
  final String hostPort;
  final String containerPort;

  PortMapping({
    required this.hostPort,
    required this.containerPort,
  });
}

class EnvironmentVariable {
  final String key;
  final String value;

  EnvironmentVariable({
    required this.key,
    required this.value,
  });
}

class VolumeMount {
  final String hostPath;
  final String containerPath;

  VolumeMount({
    required this.hostPath,
    required this.containerPath,
  });
}

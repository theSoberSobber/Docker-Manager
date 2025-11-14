import '../../domain/services/container_creation_service.dart';
import '../../core/utils/docker_cli_config.dart';
import './ssh_connection_service.dart';

class ContainerCreationServiceImpl implements ContainerCreationService {
  final SSHConnectionService sshService;

  ContainerCreationServiceImpl({required this.sshService});

  @override
  String buildDockerRunCommand(ContainerCreationConfig config) {
    final buffer = StringBuffer('docker run -d');

    // Container name
    if (config.containerName != null && config.containerName!.isNotEmpty) {
      buffer.write(' --name ${config.containerName}');
    }

    // Port mappings
    for (final port in config.portMappings) {
      if (port.hostPort.isNotEmpty && port.containerPort.isNotEmpty) {
        buffer.write(' -p ${port.hostPort}:${port.containerPort}');
      }
    }

    // Environment variables
    for (final env in config.environmentVariables) {
      if (env.key.isNotEmpty && env.value.isNotEmpty) {
        buffer.write(' -e ${env.key}=${env.value}');
      }
    }

    // Volume mounts
    for (final volume in config.volumeMounts) {
      if (volume.hostPath.isNotEmpty && volume.containerPath.isNotEmpty) {
        buffer.write(' -v ${volume.hostPath}:${volume.containerPath}');
      }
    }

    // Restart policy
    if (config.restartPolicy != 'no') {
      buffer.write(' --restart=${config.restartPolicy}');
    }

    // Working directory
    if (config.workingDirectory != null && config.workingDirectory!.isNotEmpty) {
      buffer.write(' -w ${config.workingDirectory}');
    }

    // Memory limit
    if (config.memoryLimit != null && config.memoryLimit!.isNotEmpty) {
      buffer.write(' -m ${config.memoryLimit}');
    }

    // CPU limit
    if (config.cpuLimit != null && config.cpuLimit!.isNotEmpty) {
      buffer.write(' --cpus=${config.cpuLimit}');
    }

    // Network mode
    if (config.networkMode != 'default') {
      buffer.write(' --network=${config.networkMode}');
    }

    // Privileged
    if (config.privileged) {
      buffer.write(' --privileged');
    }

    // Image
    buffer.write(' ${config.imageName}:${config.imageTag}');

    // Command override
    if (config.commandOverride != null && config.commandOverride!.isNotEmpty) {
      buffer.write(' ${config.commandOverride}');
    }

    return buffer.toString();
  }

  @override
  Future<String> createContainer(ContainerCreationConfig config) async {
    final command = buildDockerRunCommand(config);
    
    // Get Docker CLI path and build full command
    final dockerCli = await DockerCliConfig.getCliPath();
    final fullCommand = command.replaceFirst('docker', dockerCli);
    
    // Execute command
    final result = await sshService.executeCommand(fullCommand);
    
    if (result == null || result.isEmpty) {
      throw Exception('Failed to create container - no output from command');
    }
    
    // Return the container ID
    return result.trim();
  }
}

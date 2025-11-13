import '../../domain/services/docker_operations_service.dart';
import '../../domain/repositories/docker_repository.dart';
import '../../core/utils/docker_cli_config.dart';
import './ssh_connection_service.dart';

class DockerOperationsServiceImpl implements DockerOperationsService {
  final DockerRepository dockerRepository;
  final SSHConnectionService sshService;

  DockerOperationsServiceImpl({
    required this.dockerRepository,
    required this.sshService,
  });

  @override
  Future<String> getContainerLogsCommand(String containerId, {String logLines = '500'}) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    return logLines == 'all' 
        ? '$dockerCli logs $containerId'
        : '$dockerCli logs --tail $logLines $containerId';
  }

  @override
  Future<String> getInspectContainerCommand(String containerId) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    return '$dockerCli inspect $containerId';
  }

  @override
  Future<void> stopContainer(String containerId) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    await sshService.executeCommand('$dockerCli stop $containerId');
  }

  @override
  Future<void> startContainer(String containerId) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    await sshService.executeCommand('$dockerCli start $containerId');
  }

  @override
  Future<void> restartContainer(String containerId) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    await sshService.executeCommand('$dockerCli restart $containerId');
  }

  @override
  Future<void> removeContainer(String containerId) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    await sshService.executeCommand('$dockerCli rm $containerId');
  }

  @override
  Future<String> getInspectImageCommand(String imageId) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    return '$dockerCli image inspect $imageId';
  }

  @override
  Future<void> removeImage(String imageId) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    await sshService.executeCommand('$dockerCli image rm $imageId');
  }

  @override
  Future<String> getInspectVolumeCommand(String volumeName) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    return '$dockerCli volume inspect $volumeName';
  }

  @override
  Future<void> removeVolume(String volumeName) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    await sshService.executeCommand('$dockerCli volume rm $volumeName');
  }

  @override
  Future<String> getInspectNetworkCommand(String networkId) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    return '$dockerCli network inspect $networkId';
  }

  @override
  Future<void> removeNetwork(String networkId) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    await sshService.executeCommand('$dockerCli network rm $networkId');
  }

  @override
  Future<void> connectContainerToNetwork(String networkId, String containerId) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    await sshService.executeCommand('$dockerCli network connect $networkId $containerId');
  }

  @override
  Future<void> disconnectContainerFromNetwork(String networkId, String containerId) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    await sshService.executeCommand('$dockerCli network disconnect $networkId $containerId');
  }
}

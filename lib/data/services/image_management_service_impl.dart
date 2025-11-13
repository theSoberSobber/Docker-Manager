import '../../domain/services/image_management_service.dart';
import '../../core/utils/docker_cli_config.dart';
import './ssh_connection_service.dart';

class ImageManagementServiceImpl implements ImageManagementService {
  final SSHConnectionService sshService;

  ImageManagementServiceImpl({required this.sshService});

  @override
  Future<void> pullImage(String imageName, {String? tag}) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    final fullImageName = tag != null ? '$imageName:$tag' : imageName;
    final command = '$dockerCli pull $fullImageName';
    
    final result = await sshService.executeCommand(command);
    
    if (result == null || result.isEmpty) {
      throw Exception('Failed to pull image $fullImageName');
    }
  }

  @override
  Future<String> buildImage(ImageBuildConfig config) async {
    final dockerCli = await DockerCliConfig.getCliPath();
    
    // Create a temporary directory for the build context
    final tempDir = '/tmp/docker_build_${DateTime.now().millisecondsSinceEpoch}';
    final dockerfilePath = '$tempDir/Dockerfile';

    try {
      // Create temp directory
      await sshService.executeCommand('mkdir -p $tempDir');

      // Write Dockerfile content
      // Escape single quotes in dockerfile content
      final escapedDockerfile = config.dockerfileContent.replaceAll("'", "'\\''");
      await sshService.executeCommand("echo '$escapedDockerfile' > $dockerfilePath");

      // Build the image
      final buildCommand = '$dockerCli build -t ${config.imageName}:${config.tag} -f $dockerfilePath $tempDir';
      final result = await sshService.executeCommand(buildCommand);

      // Clean up temporary directory
      await sshService.executeCommand('rm -rf $tempDir');

      if (result == null || result.isEmpty) {
        throw Exception('Failed to build image ${config.imageName}:${config.tag}');
      }

      return result;
    } catch (e) {
      // Clean up on error
      try {
        await sshService.executeCommand('rm -rf $tempDir');
      } catch (_) {
        // Ignore cleanup errors
      }
      rethrow;
    }
  }
}

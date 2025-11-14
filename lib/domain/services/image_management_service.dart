/// Domain service for image management operations
/// Handles pulling and building Docker images
abstract class ImageManagementService {
  /// Pull an image from a registry
  Future<void> pullImage(String imageName, {String? tag});
  
  /// Build an image from a Dockerfile
  Future<String> buildImage(ImageBuildConfig config);
}

/// Configuration for building a Docker image
class ImageBuildConfig {
  final String imageName;
  final String tag;
  final String dockerfileContent;

  ImageBuildConfig({
    required this.imageName,
    required this.tag,
    required this.dockerfileContent,
  });
}

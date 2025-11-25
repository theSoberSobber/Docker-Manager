class DockerImage {
  final String repository;
  final String tag;
  final String imageId;
  final String created;
  final String size;

  const DockerImage({
    required this.repository,
    required this.tag,
    required this.imageId,
    required this.created,
    required this.size,
  });

  factory DockerImage.fromDockerImagesLine(String line) {
    // Check if this is the new format (with ||| delimiter)
    if (line.contains('|||')) {
      final parts = line.split('|||');
      
      if (parts.length < 5) {
        throw FormatException('Invalid docker images line format: $line');
      }

      return DockerImage(
        repository: parts[0].trim(),
        tag: parts[1].trim(),
        imageId: parts[2].trim(),
        created: parts[3].trim(),
        size: parts[4].trim(),
      );
    }
    
    // Fallback to old format (split by 2+ spaces) for backwards compatibility
    final parts = line.split(RegExp(r'\s{2,}')); // Split by 2+ spaces
    
    if (parts.length < 5) {
      throw FormatException('Invalid docker images line format: $line');
    }

    return DockerImage(
      repository: parts[0].trim(),
      tag: parts[1].trim(),
      imageId: parts[2].trim(),
      created: parts[3].trim(),
      size: parts[4].trim(),
    );
  }

  static List<DockerImage> parseDockerImagesOutput(String output) {
    final lines = output.split('\n');
    if (lines.isEmpty) return [];

    // With --format, there's no header line. Just skip empty lines and warnings.
    final dataLines = lines.where((line) => 
      line.trim().isNotEmpty && 
      !line.toLowerCase().contains('warning:') &&
      !line.toLowerCase().contains('for machine')
    );
    
    return dataLines
        .map((line) {
          try {
            return DockerImage.fromDockerImagesLine(line);
          } catch (e) {
            // Skip invalid lines
            return null;
          }
        })
        .where((image) => image != null)
        .cast<DockerImage>()
        .toList();
  }

  String get fullName => '$repository:$tag';

  @override
  String toString() {
    return 'DockerImage(repository: $repository, tag: $tag, id: $imageId, size: $size)';
  }
}
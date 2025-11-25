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
      
      if (parts.length != 5) {
        throw FormatException('Invalid docker images line format (expected 5 parts, got ${parts.length}): $line');
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
    // Also detect and skip header if present (for backward compatibility)
    final dataLines = lines.where((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return false;
      if (trimmed.toLowerCase().contains('warning:')) return false;
      if (trimmed.toLowerCase().contains('for machine')) return false;
      // Skip header line (starts with REPOSITORY or contains IMAGE ID)
      if (trimmed.toUpperCase().startsWith('REPOSITORY') || 
          trimmed.toUpperCase().contains('IMAGE ID')) return false;
      return true;
    });
    
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
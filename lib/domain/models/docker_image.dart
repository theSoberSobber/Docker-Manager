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
    // Docker images output format: REPOSITORY   TAG       IMAGE ID       CREATED       SIZE
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

    // Skip header line and empty lines
    final dataLines = lines.skip(1).where((line) => line.trim().isNotEmpty);
    
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
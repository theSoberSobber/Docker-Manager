class DockerContainer {
  final String id;
  final String image;
  final String command;
  final String created;
  final String status;
  final List<String> ports;
  final String names;
  final String? composeProject;  // Docker Compose stack/project name
  final String? composeService;  // Service name within the stack

  const DockerContainer({
    required this.id,
    required this.image,
    required this.command,
    required this.created,
    required this.status,
    required this.ports,
    required this.names,
    this.composeProject,
    this.composeService,
  });

  /// Check if this container is part of a Docker Compose stack
  bool get isPartOfStack => composeProject != null && composeProject!.isNotEmpty;

  factory DockerContainer.fromDockerPsLine(String line) {
    // New format using --format flag with pipe separator:
    // {{.ID}}|{{.Image}}|{{.Command}}|{{.CreatedAt}}|{{.Status}}|{{.Ports}}|{{.Names}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}
    final parts = line.split('|');
    
    if (parts.length < 7) {
      throw FormatException('Invalid docker ps line format: $line');
    }

    return DockerContainer(
      id: parts[0].trim(),
      image: parts[1].trim(),
      command: parts[2].trim(),
      created: parts[3].trim(),
      status: parts[4].trim(),
      ports: parts[5].trim().isEmpty ? [] : [parts[5].trim()],
      names: parts[6].trim(),
      composeProject: parts.length > 7 && parts[7].trim().isNotEmpty ? parts[7].trim() : null,
      composeService: parts.length > 8 && parts[8].trim().isNotEmpty ? parts[8].trim() : null,
    );
  }

  static List<DockerContainer> parseDockerPsOutput(String output) {
    final lines = output.split('\n');
    if (lines.isEmpty) return [];

    // Skip empty lines (no header line with --format)
    final dataLines = lines.where((line) => line.trim().isNotEmpty);
    
    return dataLines
        .map((line) {
          try {
            return DockerContainer.fromDockerPsLine(line);
          } catch (e) {
            // Skip invalid lines
            return null;
          }
        })
        .where((container) => container != null)
        .cast<DockerContainer>()
        .toList();
  }

  @override
  String toString() {
    return 'DockerContainer(id: $id, image: $image, names: $names, status: $status, stack: $composeProject)';
  }
}
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
  final String? composeWorkingDir; // Docker Compose working directory
  final String? composeConfigFiles; // Compose config files used to start stack
  
  // Container stats (optional, fetched separately)
  final String? cpuPerc;
  final String? memUsage;
  final String? memPerc;
  final String? netIO;
  final String? blockIO;
  final String? pids;

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
    this.composeWorkingDir,
    this.composeConfigFiles,
    this.cpuPerc,
    this.memUsage,
    this.memPerc,
    this.netIO,
    this.blockIO,
    this.pids,
  });

  /// Check if this container is part of a Docker Compose stack
  bool get isPartOfStack => composeProject != null && composeProject!.isNotEmpty;
  
  /// Check if stats are available
  bool get hasStats => cpuPerc != null;
  
  /// Create a copy with stats added
  DockerContainer copyWithStats({
    String? cpuPerc,
    String? memUsage,
    String? memPerc,
    String? netIO,
    String? blockIO,
    String? pids,
  }) {
    return DockerContainer(
      id: id,
      image: image,
      command: command,
      created: created,
      status: status,
      ports: ports,
      names: names,
      composeProject: composeProject,
      composeService: composeService,
      composeWorkingDir: composeWorkingDir,
      composeConfigFiles: composeConfigFiles,
      cpuPerc: cpuPerc ?? this.cpuPerc,
      memUsage: memUsage ?? this.memUsage,
      memPerc: memPerc ?? this.memPerc,
      netIO: netIO ?? this.netIO,
      blockIO: blockIO ?? this.blockIO,
      pids: pids ?? this.pids,
    );
  }

  factory DockerContainer.fromDockerPsLine(String line) {
    // New format using --format flag with pipe separator:
    // {{.ID}}|{{.Image}}|{{.Command}}|{{.CreatedAt}}|{{.Status}}|{{.Ports}}|{{.Names}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}|{{.Label "com.docker.compose.project.working_dir"}}|{{.Label "com.docker.compose.project.config_files"}}
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
      composeWorkingDir: parts.length > 9 && parts[9].trim().isNotEmpty ? parts[9].trim() : null,
      composeConfigFiles: parts.length > 10 && parts[10].trim().isNotEmpty ? parts[10].trim() : null,
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

  /// Best-effort project path (working dir or config file folder).
  String? get composeProjectPath {
    if (composeWorkingDir != null && composeWorkingDir!.trim().isNotEmpty) {
      return composeWorkingDir!.trim();
    }

    final firstConfig = _firstComposeConfigFile;
    if (firstConfig == null) return null;

    final lastSlash = firstConfig.lastIndexOf('/');
    if (lastSlash > 0) {
      return firstConfig.substring(0, lastSlash);
    }

    return null;
  }

  /// First compose config file path if available.
  String? get _firstComposeConfigFile {
    if (composeConfigFiles == null || composeConfigFiles!.trim().isEmpty) {
      return null;
    }

    final candidates = composeConfigFiles!
        .split(RegExp(r'[;,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  @override
  String toString() {
    return 'DockerContainer(id: $id, image: $image, names: $names, status: $status, stack: $composeProject)';
  }
}

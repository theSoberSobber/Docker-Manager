class DockerContainer {
  final String id;
  final String image;
  final String command;
  final String created;
  final String status;
  final List<String> ports;
  final String names;

  const DockerContainer({
    required this.id,
    required this.image,
    required this.command,
    required this.created,
    required this.status,
    required this.ports,
    required this.names,
  });

  factory DockerContainer.fromDockerPsLine(String line) {
    // Docker ps output format: CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
    final parts = line.split(RegExp(r'\s{2,}')); // Split by 2+ spaces
    
    if (parts.length < 6) {
      throw FormatException('Invalid docker ps line format: $line');
    }

    // Handle cases where PORTS column might be empty (exited containers)
    String ports = '';
    String names = '';
    
    if (parts.length >= 7) {
      ports = parts[5].trim();
      names = parts[6].trim();
    } else if (parts.length == 6) {
      // No ports, names is in parts[5]
      names = parts[5].trim();
    }

    return DockerContainer(
      id: parts[0].trim(),
      image: parts[1].trim(),
      command: parts[2].trim(),
      created: parts[3].trim(),
      status: parts[4].trim(),
      ports: ports.isEmpty ? [] : [ports],
      names: names,
    );
  }

  static List<DockerContainer> parseDockerPsOutput(String output) {
    final lines = output.split('\n');
    if (lines.isEmpty) return [];

    // Skip header line and empty lines
    final dataLines = lines.skip(1).where((line) => line.trim().isNotEmpty);
    
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
    return 'DockerContainer(id: $id, image: $image, names: $names, status: $status)';
  }
}
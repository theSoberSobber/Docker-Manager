class DockerVolume {
  final String driver;
  final String volumeName;

  const DockerVolume({
    required this.driver,
    required this.volumeName,
  });

  factory DockerVolume.fromDockerVolumeLsLine(String line) {
    // Docker volume ls output format: DRIVER    VOLUME NAME
    final parts = line.split(RegExp(r'\s{2,}')); // Split by 2+ spaces
    
    if (parts.length < 2) {
      throw FormatException('Invalid docker volume ls line format: $line');
    }

    return DockerVolume(
      driver: parts[0].trim(),
      volumeName: parts[1].trim(),
    );
  }

  static List<DockerVolume> parseDockerVolumeLsOutput(String output) {
    final lines = output.split('\n');
    if (lines.isEmpty) return [];

    // Skip header line and empty lines
    final dataLines = lines.skip(1).where((line) => line.trim().isNotEmpty);
    
    return dataLines
        .map((line) {
          try {
            return DockerVolume.fromDockerVolumeLsLine(line);
          } catch (e) {
            // Skip invalid lines
            return null;
          }
        })
        .where((volume) => volume != null)
        .cast<DockerVolume>()
        .toList();
  }

  @override
  String toString() {
    return 'DockerVolume(driver: $driver, name: $volumeName)';
  }
}
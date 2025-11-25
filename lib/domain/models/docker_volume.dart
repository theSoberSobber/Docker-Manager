class DockerVolume {
  final String driver;
  final String volumeName;

  const DockerVolume({
    required this.driver,
    required this.volumeName,
  });

  factory DockerVolume.fromDockerVolumeLsLine(String line) {
    // Check if this is the new format (with ||| delimiter)
    if (line.contains('|||')) {
      final parts = line.split('|||');
      
      if (parts.length < 2) {
        throw FormatException('Invalid docker volume ls line format: $line');
      }

      return DockerVolume(
        driver: parts[0].trim(),
        volumeName: parts[1].trim(),
      );
    }
    
    // Fallback to old format (split by 2+ spaces) for backwards compatibility
    final parts = line.split(RegExp(r'\s{2,}'));
    
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

    // With --format, there's no header line. Just skip empty lines and warnings.
    final dataLines = lines.where((line) => 
      line.trim().isNotEmpty && 
      !line.toLowerCase().contains('warning:') &&
      !line.toLowerCase().contains('for machine')
    );
    
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
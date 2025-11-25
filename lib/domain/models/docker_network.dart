class DockerNetwork {
  final String networkId;
  final String name;
  final String driver;
  final String scope;

  const DockerNetwork({
    required this.networkId,
    required this.name,
    required this.driver,
    required this.scope,
  });

  factory DockerNetwork.fromDockerNetworkLsLine(String line) {
    // Check if this is the new format (with ||| delimiter)
    if (line.contains('|||')) {
      final parts = line.split('|||');
      
      if (parts.length < 4) {
        throw FormatException('Invalid docker network ls line format: $line');
      }

      return DockerNetwork(
        networkId: parts[0].trim(),
        name: parts[1].trim(),
        driver: parts[2].trim(),
        scope: parts[3].trim(),
      );
    }
    
    // Fallback to old format (split by 2+ spaces) for backwards compatibility
    final parts = line.split(RegExp(r'\s{2,}'));
    
    if (parts.length < 4) {
      throw FormatException('Invalid docker network ls line format: $line');
    }

    return DockerNetwork(
      networkId: parts[0].trim(),
      name: parts[1].trim(),
      driver: parts[2].trim(),
      scope: parts[3].trim(),
    );
  }

  static List<DockerNetwork> parseDockerNetworkLsOutput(String output) {
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
            return DockerNetwork.fromDockerNetworkLsLine(line);
          } catch (e) {
            // Skip invalid lines
            return null;
          }
        })
        .where((network) => network != null)
        .cast<DockerNetwork>()
        .toList();
  }

  @override
  String toString() {
    return 'DockerNetwork(id: $networkId, name: $name, driver: $driver, scope: $scope)';
  }
}
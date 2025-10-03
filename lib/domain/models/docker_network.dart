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
    // Docker network ls output format: NETWORK ID   NAME      DRIVER    SCOPE
    final parts = line.split(RegExp(r'\s{2,}')); // Split by 2+ spaces
    
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

    // Skip header line and empty lines
    final dataLines = lines.skip(1).where((line) => line.trim().isNotEmpty);
    
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
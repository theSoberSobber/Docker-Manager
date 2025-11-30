import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/server.dart';
import 'ssh_connection_service.dart';

/// Resolves the Docker CLI binary path, preferring the current server override.
class DockerCliPathService {
  DockerCliPathService._internal();
  static final DockerCliPathService _instance = DockerCliPathService._internal();
  factory DockerCliPathService() => _instance;

  final SSHConnectionService _sshService = SSHConnectionService();

  Future<String> getDockerCliPath() async {
    final Server? currentServer = _sshService.currentServer;
    if (currentServer?.dockerCliPath != null &&
        currentServer!.dockerCliPath!.isNotEmpty) {
      return currentServer.dockerCliPath!;
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('dockerCliPath') ?? 'docker';
  }
}

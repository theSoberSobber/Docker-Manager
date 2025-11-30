import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/server.dart';
import 'ssh_connection_service.dart';
import '../repositories/server_repository_impl.dart';

/// Resolves the Docker CLI binary path, preferring the current server override.
class DockerCliPathService {
  DockerCliPathService._internal();
  static final DockerCliPathService _instance = DockerCliPathService._internal();
  factory DockerCliPathService() => _instance;

  final SSHConnectionService _sshService = SSHConnectionService();
  final ServerRepositoryImpl _serverRepository = ServerRepositoryImpl();

  Future<String> getDockerCliPath() async {
    final Server? currentServer = _sshService.currentServer;
    if (currentServer != null) {
      // Refresh server from storage to pick up runtime edits (e.g., path changes)
      final servers = await _serverRepository.getServers();
      final updatedServer = servers.firstWhere(
        (s) => s.id == currentServer.id,
        orElse: () => currentServer,
      );

      if (updatedServer.dockerCliPath != null &&
          updatedServer.dockerCliPath!.isNotEmpty) {
        return updatedServer.dockerCliPath!;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('dockerCliPath') ?? 'docker';
  }
}

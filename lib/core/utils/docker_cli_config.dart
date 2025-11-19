import 'package:shared_preferences/shared_preferences.dart';

/// Utility class for managing Docker CLI configuration
/// Provides centralized access to Docker CLI path setting
class DockerCliConfig {
  static const String _key = 'dockerCliPath';
  static const String _defaultPath = 'docker';

  /// Get the configured Docker CLI path (e.g., 'docker', 'podman')
  static Future<String> getCliPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? _defaultPath;
  }

  /// Set the Docker CLI path
  static Future<void> setCliPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanPath = path.trim().isEmpty ? _defaultPath : path.trim();
    await prefs.setString(_key, cleanPath);
  }

  /// Build a Docker command with the configured CLI
  static Future<String> buildCommand(String command) async {
    final cliPath = await getCliPath();
    // Replace 'docker' at the start of the command with the configured CLI
    if (command.startsWith('docker ')) {
      return command.replaceFirst('docker', cliPath);
    } else if (command == 'docker') {
      return cliPath;
    }
    return '$cliPath $command';
  }
}

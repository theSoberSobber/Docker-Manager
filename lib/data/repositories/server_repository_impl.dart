import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/server.dart';
import '../../domain/repositories/server_repository.dart';

class ServerRepositoryImpl implements ServerRepository {
  static const String _serversKey = 'docker_servers';
  static const String _lastUsedServerKey = 'last_used_server_id';
  
  @override
  Future<List<Server>> getServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serversJson = prefs.getStringList(_serversKey) ?? [];
      
      return serversJson
          .map((serverString) => Server.fromJson(jsonDecode(serverString)))
          .toList();
    } catch (e) {
      // If there's any error, return empty list
      return [];
    }
  }

  @override
  Future<void> saveServer(Server server) async {
    try {
      final servers = await getServers();
      servers.add(server);
      await _saveServersList(servers);
    } catch (e) {
      throw Exception('Failed to save server: $e');
    }
  }

  @override
  Future<void> updateServer(Server server) async {
    try {
      final servers = await getServers();
      final index = servers.indexWhere((s) => s.id == server.id);
      
      if (index != -1) {
        servers[index] = server;
        await _saveServersList(servers);
      } else {
        throw Exception('Server not found');
      }
    } catch (e) {
      throw Exception('Failed to update server: $e');
    }
  }

  @override
  Future<void> deleteServer(String serverId) async {
    try {
      final servers = await getServers();
      servers.removeWhere((server) => server.id == serverId);
      await _saveServersList(servers);
    } catch (e) {
      throw Exception('Failed to delete server: $e');
    }
  }

  @override
  Future<void> clearServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_serversKey);
    } catch (e) {
      throw Exception('Failed to clear servers: $e');
    }
  }

  @override
  Future<String?> getLastUsedServerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastUsedServerKey);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> setLastUsedServerId(String serverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastUsedServerKey, serverId);
    } catch (e) {
      throw Exception('Failed to set last used server: $e');
    }
  }

  @override
  Future<Server?> getLastUsedServer() async {
    try {
      final lastUsedId = await getLastUsedServerId();
      if (lastUsedId == null) return null;
      
      final servers = await getServers();
      return servers.where((server) => server.id == lastUsedId).firstOrNull;
    } catch (e) {
      return null;
    }
  }

  /// Helper method to save the entire servers list
  Future<void> _saveServersList(List<Server> servers) async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = servers
        .map((server) => jsonEncode(server.toJson()))
        .toList();
    
    await prefs.setStringList(_serversKey, serversJson);
  }
}
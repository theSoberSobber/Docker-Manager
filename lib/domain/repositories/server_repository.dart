import '../models/server.dart';

abstract class ServerRepository {
  /// Get all servers from storage
  Future<List<Server>> getServers();
  
  /// Save a new server to storage
  Future<void> saveServer(Server server);
  
  /// Update an existing server in storage
  Future<void> updateServer(Server server);
  
  /// Delete a server from storage
  Future<void> deleteServer(String serverId);
  
  /// Clear all servers from storage
  Future<void> clearServers();
  
  /// Get the last used server ID
  Future<String?> getLastUsedServerId();
  
  /// Set the last used server ID
  Future<void> setLastUsedServerId(String serverId);
  
  /// Get the last used server object
  Future<Server?> getLastUsedServer();
}
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import '../../domain/models/server.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  failed,
}

class SSHConnectionResult {
  final bool success;
  final String? error;
  final ConnectionStatus status;

  SSHConnectionResult({
    required this.success,
    this.error,
    required this.status,
  });
}

class SSHConnectionService {
  static final SSHConnectionService _instance = SSHConnectionService._internal();
  factory SSHConnectionService() => _instance;
  SSHConnectionService._internal();

  SSHClient? _currentConnection;
  Server? _currentServer;
  ConnectionStatus _status = ConnectionStatus.disconnected;

  // Getters
  ConnectionStatus get status => _status;
  Server? get currentServer => _currentServer;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isConnecting => _status == ConnectionStatus.connecting;
  SSHClient? get currentConnection => _currentConnection;

  /// Connect to a server
  Future<SSHConnectionResult> connect(Server server) async {
    try {
      _status = ConnectionStatus.connecting;
      
      // Disconnect existing connection if any
      await disconnect();

      // Create new SSH client with proper authentication
      SSHClient client;
      
      if (server.password != null && server.password!.isNotEmpty) {
        // Password authentication
        client = SSHClient(
          await SSHSocket.connect(server.ip, server.port),
          username: server.username,
          onPasswordRequest: () => server.password!,
        );
      } else if (server.privateKey != null && server.privateKey!.isNotEmpty) {
        // Private key authentication
        client = SSHClient(
          await SSHSocket.connect(server.ip, server.port),
          username: server.username,
          identities: [
            ...SSHKeyPair.fromPem(server.privateKey!)
          ],
        );
      } else {
        throw Exception('No authentication method provided');
      }

      // Store successful connection
      _currentConnection = client;
      _currentServer = server;
      _status = ConnectionStatus.connected;

      return SSHConnectionResult(
        success: true,
        status: ConnectionStatus.connected,
      );
    } catch (e) {
      _status = ConnectionStatus.failed;
      _currentConnection = null;
      _currentServer = null;

      return SSHConnectionResult(
        success: false,
        error: e.toString(),
        status: ConnectionStatus.failed,
      );
    }
  }

  /// Disconnect current connection
  Future<void> disconnect() async {
    try {
      if (_currentConnection != null) {
        _currentConnection!.close();
        _currentConnection = null;
      }
    } catch (e) {
      // Ignore disconnect errors
    } finally {
      _currentServer = null;
      _status = ConnectionStatus.disconnected;
    }
  }

  /// Execute a command on the connected server
  Future<String?> executeCommand(String command) async {
    if (!isConnected || _currentConnection == null) {
      throw Exception('No active SSH connection');
    }

    try {
      final result = await _currentConnection!.run(command);
      return utf8.decode(result);
    } catch (e) {
      throw Exception('Failed to execute command: $e');
    }
  }

  /// Test if connection is still alive
  Future<bool> testConnection() async {
    if (!isConnected || _currentConnection == null) {
      return false;
    }

    try {
      // Execute a simple command to test connection
      await executeCommand('echo "connection_test"');
      return true;
    } catch (e) {
      _status = ConnectionStatus.failed;
      return false;
    }
  }

  /// Smart server switching - only reconnect if different server
  Future<SSHConnectionResult> switchToServer(Server newServer) async {
    // If same server, just return current status
    if (_currentServer?.id == newServer.id && isConnected) {
      return SSHConnectionResult(
        success: true,
        status: ConnectionStatus.connected,
      );
    }

    // Different server or not connected, establish new connection
    return await connect(newServer);
  }

  /// Get connection info string
  String getConnectionInfo() {
    if (_currentServer == null) return 'Not connected';
    
    switch (_status) {
      case ConnectionStatus.connecting:
        return 'Connecting to ${_currentServer!.name}...';
      case ConnectionStatus.connected:
        return 'Connected to ${_currentServer!.name}';
      case ConnectionStatus.failed:
        return 'Failed to connect to ${_currentServer!.name}';
      case ConnectionStatus.disconnected:
        return 'Disconnected from ${_currentServer!.name}';
    }
  }
}
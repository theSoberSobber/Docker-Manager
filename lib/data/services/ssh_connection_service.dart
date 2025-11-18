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
  bool _hasEverConnected = false; // Track if we've ever had a successful connection
  bool _isReconnecting = false; // Prevent concurrent reconnection attempts

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
      _hasEverConnected = true; // Mark that we've had at least one successful connection

      return SSHConnectionResult(
        success: true,
        status: ConnectionStatus.connected,
      );
    } catch (e) {
      _status = ConnectionStatus.failed;
      _currentConnection = null;
      _currentServer = null;
      _isReconnecting = false; // Clear reconnection flag on failure

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
      _isReconnecting = false; // Clear reconnection flag on disconnect
      // Note: We don't reset _hasEverConnected here as it tracks historical state
    }
  }

  /// Execute a command on the connected server
  /// Automatically reconnects and retries once if connection is stale
  Future<String?> executeCommand(String command, {bool isRetry = false}) async {
    if (!isConnected || _currentConnection == null) {
      throw Exception('No active SSH connection');
    }

    try {
      final result = await _currentConnection!.run(command);
      return utf8.decode(result);
    } catch (e) {
      // Check if this is a connection-related error
      final errorString = e.toString().toLowerCase();
      final isConnectionError = errorString.contains('socket') ||
          errorString.contains('connection') ||
          errorString.contains('closed') ||
          errorString.contains('timeout') ||
          errorString.contains('broken pipe') ||
          errorString.contains('session');

      // Only attempt auto-reconnect if:
      // 1. It's a connection error
      // 2. We haven't already retried
      // 3. We have a server to reconnect to
      // 4. We've had at least one successful connection before (not initial setup)
      // 5. We're not already in the middle of reconnecting
      if (isConnectionError && 
          !isRetry && 
          _currentServer != null && 
          _hasEverConnected && 
          !_isReconnecting) {
        try {
          _isReconnecting = true; // Prevent concurrent reconnection attempts
          
          // Mark as disconnected and clear stale connection
          _status = ConnectionStatus.disconnected;
          _currentConnection?.close();
          _currentConnection = null;

          // Attempt to reconnect to the same server
          final reconnectResult = await connect(_currentServer!);
          
          if (reconnectResult.success) {
            // Reconnection successful, retry the command once
            _isReconnecting = false;
            return await executeCommand(command, isRetry: true);
          } else {
            // Reconnection failed
            _isReconnecting = false;
            throw Exception('Connection lost and reconnection failed: ${reconnectResult.error}');
          }
        } catch (reconnectError) {
          _isReconnecting = false;
          throw Exception('Connection lost and reconnection failed: $reconnectError');
        }
      }

      // Either not a connection error, already retried, or no server to reconnect to
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
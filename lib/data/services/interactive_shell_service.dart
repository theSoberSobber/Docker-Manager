import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'ssh_connection_service.dart';

class InteractiveShellService {
  SSHSession? _session;
  StreamController<String>? _outputController;
  final SSHConnectionService _sshService = SSHConnectionService();
  bool _isActive = false;

  Stream<String>? get outputStream => _outputController?.stream;
  bool get isActive => _isActive;

  /// Start an interactive shell session
  Future<bool> startInteractiveShell({
    String? containerId,
    String? executable = '/bin/bash',
  }) async {
    try {
      if (!_sshService.isConnected || _sshService.currentConnection == null) {
        throw Exception('No active SSH connection');
      }

      // Close any existing session
      await closeShell();

      // Create new session with TTY allocation and timeout
      _session = await _sshService.currentConnection!.shell(
        pty: const SSHPtyConfig(
          width: 80,
          height: 24,
        ),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Shell creation timed out');
        },
      );
      _outputController = StreamController<String>.broadcast();
      
      // Set up the interactive shell command
      String shellCommand;
      if (containerId != null) {
        final executableName = executable ?? '/bin/bash';
        
        // Direct docker exec - keep it simple
        shellCommand = 'docker exec -it $containerId $executableName\n';
      } else {
        // Regular shell
        shellCommand = '${executable ?? '/bin/bash'}\n';
      }

      // Listen to output
      _session!.stdout.listen(
        (data) {
          final output = utf8.decode(data);
          _outputController?.add(output);
        },
        onError: (error) {
          _outputController?.addError(error);
        },
        onDone: () {
          _isActive = false;
        },
      );

      // Listen to stderr
      _session!.stderr.listen(
        (data) {
          final output = utf8.decode(data);
          _outputController?.add('[ERROR] $output');
        },
      );

      _isActive = true;

      // Wait a bit for the shell to initialize before sending the docker command
      await Future.delayed(const Duration(milliseconds: 500));

      // Start the shell command
      print('DEBUG: Sending command: $shellCommand');
      _session!.write(utf8.encode(shellCommand));

      return true;
    } catch (e) {
      await closeShell();
      return false;
    }
  }

  /// Send command to the interactive shell
  Future<void> sendCommand(String command) async {
    if (!_isActive || _session == null) {
      throw Exception('No active interactive shell session');
    }

    // Add newline to execute the command
    final commandWithNewline = command.endsWith('\n') ? command : '$command\n';
    _session!.write(utf8.encode(commandWithNewline));
  }

  /// Send raw input (for special keys, etc.)
  Future<void> sendRawInput(String input) async {
    if (!_isActive || _session == null) {
      throw Exception('No active interactive shell session');
    }

    _session!.write(utf8.encode(input));
  }

  /// Close the interactive shell
  Future<void> closeShell() async {
    try {
      _isActive = false;
      
      if (_session != null) {
        // Try to exit gracefully
        _session!.write(utf8.encode('exit\n'));
        await Future.delayed(const Duration(milliseconds: 500));
        _session!.close();
        _session = null;
      }

      if (_outputController != null) {
        await _outputController!.close();
        _outputController = null;
      }
    } catch (e) {
      // Ignore errors during cleanup
    }
  }

  /// Send Ctrl+C signal
  Future<void> sendInterrupt() async {
    if (!_isActive || _session == null) return;
    
    // Send Ctrl+C (ASCII 3)
    _session!.write(Uint8List.fromList([3]));
  }

  /// Send Ctrl+D signal (EOF)
  Future<void> sendEOF() async {
    if (!_isActive || _session == null) return;
    
    // Send Ctrl+D (ASCII 4)
    _session!.write(Uint8List.fromList([4]));
  }

  /// Resize terminal (if supported)
  Future<void> resizeTerminal(int width, int height) async {
    if (!_isActive || _session == null) return;
    
    try {
      // This may not be supported by all SSH implementations
      // _session!.resizeTerminal(width, height);
    } catch (e) {
      // Ignore resize errors
    }
  }
}
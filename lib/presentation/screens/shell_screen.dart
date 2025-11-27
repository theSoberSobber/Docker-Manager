import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart';
import '../../data/services/ssh_connection_service.dart';

class ShellScreen extends StatefulWidget {
  final String title;
  final String? command;
  final bool isInteractive;
  final Map<String, String>? containerInfo; // For container shells

  const ShellScreen({
    super.key,
    required this.title,
    this.command,
    this.isInteractive = false,
    this.containerInfo,
  });

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  final SSHConnectionService _sshService = SSHConnectionService();
  late final Terminal _terminal;
  final TerminalController _terminalController = TerminalController();
  bool _isLoading = true;
  bool _isConnected = false;
  bool _useInteractiveMode = true;
  SSHSession? _session;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 10000,
    );
    
    _initializeShell();
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }

  Future<void> _initializeShell() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (!_sshService.isConnected) {
        _terminal.write('Error: No SSH connection available\r\n');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // If there's a command, execute it (for logs, inspect, etc.)
      if (widget.command != null) {
        _terminal.write('Executing: ${widget.command}\r\n\r\n');
        final result = await _sshService.executeCommand(widget.command!);
        if (result != null && result.isNotEmpty) {
          // Check if this is JSON output from an inspect command
          if (_isInspectCommand() && _isValidJson(result)) {
            _terminal.write(_formatJson(result));
          } else {
            _terminal.write(result.replaceAll('\n', '\r\n'));
          }
        } else {
          _terminal.write('Command completed with no output\r\n');
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // For interactive shells, try true interactive mode first
      if (widget.isInteractive && _useInteractiveMode) {
        await _startInteractiveShell();
      } else if (widget.isInteractive) {
        await _initializeCommandMode();
      }
    } catch (e) {
      _terminal.write('Error: $e\r\n');
      if (widget.isInteractive) {
        await _initializeCommandMode();
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startInteractiveShell() async {
    try {
      _terminal.write('🔄 Connecting to shell...\r\n');
      
      // Create SSH session with PTY
      _session = await _sshService.currentConnection!.shell(
        pty: SSHPtyConfig(
          width: _terminal.viewWidth,
          height: _terminal.viewHeight,
        ),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Shell creation timed out');
        },
      );

      _terminal.write('🚀 Interactive shell mode enabled!\r\n');
      
      if (widget.containerInfo != null) {
        final containerId = widget.containerInfo!['containerId'];
        final executable = widget.containerInfo!['executable'] ?? '/bin/bash';
        
        _terminal.write('Container: $containerId\r\n');
        _terminal.write('Executable: $executable\r\n');
        
        // Get Docker CLI path
        final prefs = await SharedPreferences.getInstance();
        final dockerCli = prefs.getString('dockerCliPath') ?? 'docker';
        
        // Enter container shell
        _session!.write(utf8.encode('$dockerCli exec -it $containerId $executable\n'));
      }
      
      // Clear initial connection messages after a brief delay
      await Future.delayed(const Duration(milliseconds: 500));
      _terminal.buffer.clear();
      _terminal.buffer.setCursor(0, 0);
      
      // Set up terminal resize handler
      _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        _session?.resizeTerminal(width, height, pixelWidth, pixelHeight);
      };
      
      // Set up terminal output handler (user input -> SSH)
      _terminal.onOutput = (data) {
        _session?.write(utf8.encode(data));
      };
      
      // Set up SSH output handler (SSH -> terminal)
      _session!.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(_terminal.write);
      
      _session!.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(_terminal.write);
      
      _isConnected = true;
    } catch (e) {
      _terminal.write('❌ Interactive mode error: $e\r\n');
      _terminal.write('🔄 Falling back to command mode...\r\n');
      await _initializeCommandMode();
    }
  }

  Future<void> _reinitializeShell() async {
    // Close current session if active
    _session?.close();
    _session = null;
    
    // Clear terminal and reinitialize
    _terminal.buffer.clear();
    _terminal.buffer.setCursor(0, 0);
    
    setState(() {
      _isConnected = false;
      _isLoading = true;
    });
    
    await _initializeShell();
  }

  Future<void> _initializeCommandMode() async {
    try {
      if (widget.containerInfo != null) {
        _terminal.write('📦 Command-mode container shell ready.\r\n');
        _terminal.write('Container: ${widget.containerInfo!['containerId']}\r\n');
        _terminal.write('Executable: ${widget.containerInfo!['executable']}\r\n');
        _terminal.write('Note: Commands will execute one at a time (no persistent session).\r\n');
      } else {
        _terminal.write('💻 Command-mode shell ready.\r\n');
        _terminal.write('Note: Commands will execute one at a time (no persistent session).\r\n');
      }
      _isConnected = true;
    } catch (e) {
      _terminal.write('Error: $e\r\n');
    }
  }

  bool _isInspectCommand() {
    return widget.command != null && 
           (widget.command!.contains('inspect') || widget.title.toLowerCase().contains('inspect'));
  }

  bool _isValidJson(String text) {
    try {
      json.decode(text);
      return true;
    } catch (e) {
      return false;
    }
  }

  String _formatJson(String jsonString) {
    try {
      final dynamic jsonData = json.decode(jsonString);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(jsonData);
    } catch (e) {
      return jsonString;
    }
  }

  void _copyOutput() {
    final buffer = _terminal.buffer;
    final lines = <String>[];
    
    // Extract visible lines from terminal buffer
    for (int i = 0; i < buffer.lines.length; i++) {
      final line = buffer.lines[i];
      final lineText = line.toString();
      if (lineText.trim().isNotEmpty) {
        lines.add(lineText);
      }
    }
    
    final outputText = lines.join('\n');
    if (outputText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: outputText));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Text('shell.output_copied'.tr()),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('shell.no_output_to_copy'.tr()),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (widget.isInteractive) ...[
            // Mode toggle button
            IconButton(
              icon: Icon(_useInteractiveMode ? Icons.terminal : Icons.code),
              tooltip: _useInteractiveMode 
                  ? 'common.switch_to_command_mode'.tr() 
                  : 'common.switch_to_interactive_mode'.tr(),
              onPressed: () {
                setState(() {
                  _useInteractiveMode = !_useInteractiveMode;
                });
                _reinitializeShell();
              },
            ),
            // Interactive shell controls (only show when in interactive mode)
            if (_session != null) ...[
              IconButton(
                icon: const Icon(Icons.stop),
                tooltip: 'common.send_ctrl_c'.tr(),
                onPressed: () {
                  // Send Ctrl+C (ASCII 3)
                  _session?.write(utf8.encode('\x03'));
                },
              ),
              IconButton(
                icon: const Icon(Icons.exit_to_app),
                tooltip: 'common.send_ctrl_d'.tr(),
                onPressed: () {
                  // Send Ctrl+D (ASCII 4 - EOF)
                  _session?.write(utf8.encode('\x04'));
                },
              ),
            ],
            // Clear button
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: () {
                _terminal.buffer.clear();
                _terminal.buffer.setCursor(0, 0);
                setState(() {});
              },
              tooltip: 'Clear output',
            ),
          ],
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyOutput,
            tooltip: 'common.copy_output'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: isDark ? const Color(0xFFE6EDF3) : Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Initializing shell...',
                      style: TextStyle(
                        color: isDark ? const Color(0xFFE6EDF3) : Colors.grey,
                      ),
                    ),
                  ],
                ),
              )
            : TerminalView(
                _terminal,
                controller: _terminalController,
                autofocus: true,
                backgroundOpacity: 1.0,
                padding: const EdgeInsets.all(8),
                theme: TerminalTheme(
                  cursor: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF24292F),
                  selection: isDark 
                      ? const Color(0xFF3B5998).withOpacity(0.5)
                      : const Color(0xFFB3D8FF).withOpacity(0.5),
                  foreground: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF24292F),
                  background: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
                  black: isDark ? const Color(0xFF484F58) : const Color(0xFF24292F),
                  red: const Color(0xFFFF7B72),
                  green: const Color(0xFF3FB950),
                  yellow: const Color(0xFFD29922),
                  blue: const Color(0xFF58A6FF),
                  magenta: const Color(0xFFBC8CFF),
                  cyan: const Color(0xFF39C5CF),
                  white: isDark ? const Color(0xFFB1BAC4) : const Color(0xFF6E7781),
                  brightBlack: isDark ? const Color(0xFF6E7681) : const Color(0xFF57606A),
                  brightRed: const Color(0xFFFFA198),
                  brightGreen: const Color(0xFF56D364),
                  brightYellow: const Color(0xFFE3B341),
                  brightBlue: const Color(0xFF79C0FF),
                  brightMagenta: const Color(0xFFD2A8FF),
                  brightCyan: const Color(0xFF56D4DD),
                  brightWhite: isDark ? const Color(0xFFCDD9E5) : const Color(0xFF8C959F),
                  searchHitBackground: const Color(0xFFD29922).withOpacity(0.5),
                  searchHitBackgroundCurrent: const Color(0xFFD29922),
                  searchHitForeground: Colors.black,
                ),
              ),
      ),
    );
  }
}

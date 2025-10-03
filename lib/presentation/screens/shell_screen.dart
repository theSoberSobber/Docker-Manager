import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../data/services/ssh_connection_service.dart';
import '../../data/services/interactive_shell_service.dart';

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
  final InteractiveShellService _interactiveShell = InteractiveShellService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<String> _output = [];
  bool _isLoading = true;
  bool _isConnected = false;
  bool _useInteractiveMode = true; // Toggle for testing
  StreamSubscription<String>? _outputSubscription;

  @override
  void initState() {
    super.initState();
    _initializeShell();
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    _interactiveShell.closeShell();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeShell() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (!_sshService.isConnected) {
        _addOutput('Error: No SSH connection available');
        return;
      }

      // If there's a command, execute it (for logs, inspect, etc.)
      if (widget.command != null) {
        _addOutput('Executing: ${widget.command}');
        _addOutput(''); // Empty line for better readability
        final result = await _sshService.executeCommand(widget.command!);
        if (result != null && result.isNotEmpty) {
          _addOutput(result);
        } else {
          _addOutput('Command completed with no output');
        }
      }

      // For interactive shells, try true interactive mode first
      if (widget.isInteractive) {
        if (_useInteractiveMode) {
          // Try interactive mode first with timeout
          _addOutput('🔄 Attempting true interactive mode...');
          
          try {
            bool success = await _interactiveShell.startInteractiveShell(
              containerId: widget.containerInfo?['containerId'],
              executable: widget.containerInfo?['executable'] ?? '/bin/bash',
            ).timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                _addOutput('⏰ Interactive mode timed out, switching to command mode...');
                return false;
              },
            );

            if (success) {
              _addOutput('🚀 True interactive shell mode enabled!');
              if (widget.containerInfo != null) {
                _addOutput('Container: ${widget.containerInfo!['containerId']}');
                _addOutput('Executable: ${widget.containerInfo!['executable']}');
                _addOutput('✨ Real -it mode with persistent session!');
              } else {
                _addOutput('Host shell with true interactive mode.');
              }
              
              // Listen to interactive shell output
              _outputSubscription = _interactiveShell.outputStream?.listen(
                (output) {
                  // Process output in chunks to handle partial ANSI sequences
                  _processStreamOutput(output);
                },
                onError: (error) {
                  _addOutput('Shell error: $error');
                  // Fallback to command mode on error
                  _initializeCommandMode();
                },
              );
              
              _isConnected = true;
            } else {
              _addOutput('⚠️ Interactive mode failed, falling back to command mode...');
              await _initializeCommandMode();
            }
          } catch (e) {
            _addOutput('❌ Interactive mode error: $e');
            _addOutput('🔄 Falling back to command mode...');
            await _initializeCommandMode();
          }
        } else {
          await _initializeCommandMode();
        }
      }
    } catch (e) {
      _addOutput('Error: $e');
      if (widget.isInteractive) {
        await _initializeCommandMode();
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _reinitializeShell() async {
    // Close current interactive shell if active
    if (_interactiveShell.isActive) {
      await _interactiveShell.closeShell();
    }
    
    // Cancel subscription
    _outputSubscription?.cancel();
    _outputSubscription = null;
    
    // Clear output buffer and reinitialize
    setState(() {
      _output.clear();
      _outputBuffer = '';
      _isConnected = false;
      _isLoading = true;
    });
    
    await _initializeShell();
  }

  Future<void> _initializeCommandMode() async {
    try {
      if (widget.containerInfo != null) {
        _addOutput('📦 Command-mode container shell ready.');
        _addOutput('Container: ${widget.containerInfo!['containerId']}');
        _addOutput('Executable: ${widget.containerInfo!['executable']}');
        _addOutput('Commands will be executed inside the container.');
      } else {
        _addOutput('💻 Command-mode shell ready. Type commands below:');
      }
      _isConnected = true;
    } catch (e) {
      _addOutput('Error: $e');
    }
  }

  String _outputBuffer = '';

  void _processStreamOutput(String rawOutput) {
    // Add to buffer to handle partial sequences
    _outputBuffer += rawOutput;
    
    // Process complete lines
    List<String> lines = _outputBuffer.split('\n');
    
    // Keep the last potentially incomplete line in buffer
    _outputBuffer = lines.removeLast();
    
    // Process complete lines
    for (String line in lines) {
      if (line.trim().isNotEmpty) {
        String cleanLine = _cleanAnsiEscapes(line);
        if (cleanLine.trim().isNotEmpty) {
          setState(() {
            _output.add(cleanLine);
          });
        }
      }
    }
    
    // Auto-scroll after processing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addOutput(String text) {
    // Clean ANSI escape sequences and control characters
    String cleanText = _cleanAnsiEscapes(text);
    
    setState(() {
      _output.add(cleanText);
    });
    
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _cleanAnsiEscapes(String text) {
    // Remove ANSI escape sequences - comprehensive pattern
    String cleaned = text;
    
    // Remove CSI (Control Sequence Introducer) sequences: ESC[...
    cleaned = cleaned.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
    
    // Remove OSC (Operating System Command) sequences: ESC]...BEL or ESC]...ST
    cleaned = cleaned.replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(\x07|\x1B\\)'), '');
    
    // Remove DCS (Device Control String) sequences: ESC P...ESC\
    cleaned = cleaned.replaceAll(RegExp(r'\x1BP[^\x1B]*\x1B\\'), '');
    
    // Remove specific terminal control sequences
    cleaned = cleaned.replaceAll(RegExp(r'\x1B\[[\?]?[0-9]*[hl]'), ''); // Mode setting
    cleaned = cleaned.replaceAll(RegExp(r'\x1B\[[0-9]*[ABCD]'), ''); // Cursor movement
    cleaned = cleaned.replaceAll(RegExp(r'\x1B\[[0-9]*[JK]'), ''); // Clear sequences
    cleaned = cleaned.replaceAll(RegExp(r'\x1B\[[0-9;]*[mK]'), ''); // SGR and clear
    cleaned = cleaned.replaceAll(RegExp(r'\x1B\[\?[0-9]*[hl]'), ''); // Private modes
    
    // Remove bracketed paste mode sequences
    cleaned = cleaned.replaceAll(RegExp(r'\x1B\[\?2004[hl]'), '');
    
    // Remove cursor position reports and other responses
    cleaned = cleaned.replaceAll(RegExp(r'\x1B\[[0-9;]*R'), '');
    
    // Remove bell characters
    cleaned = cleaned.replaceAll('\x07', '');
    
    // Remove carriage returns that create overwriting
    cleaned = cleaned.replaceAll(RegExp(r'\r+'), '');
    
    // Remove excessive whitespace but preserve structure
    cleaned = cleaned.replaceAll(RegExp(r' {3,}'), '  ');
    
    // Remove non-printable characters except newlines and tabs
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'), '');
    
    return cleaned;
  }

  Future<void> _executeCommand(String command) async {
    if (command.trim().isEmpty) return;

    _addOutput('\$ $command');
    
    try {
      // Use interactive shell if available
      if (_interactiveShell.isActive) {
        await _interactiveShell.sendCommand(command);
        _inputController.clear(); // Clear input in interactive mode too!
        return; // Output will come through the stream
      }
      
      // Fallback to command mode
      String actualCommand = command;
      
      // If we're in a container shell, wrap the command with docker exec
      if (widget.containerInfo != null) {
        final containerId = widget.containerInfo!['containerId'];
        final executable = widget.containerInfo!['executable'];
        
        // For container shells, we need to execute commands inside the container
        // We'll use docker exec for each command
        actualCommand = 'docker exec $containerId $executable -c "$command"';
        
        // Show the actual command being executed for transparency
        _addOutput('Executing in container: $actualCommand');
        _addOutput(''); // Empty line for better readability
      }
      
      final result = await _sshService.executeCommand(actualCommand);
      if (result != null && result.isNotEmpty) {
        _addOutput(result);
      } else {
        _addOutput('Command completed');
      }
    } catch (e) {
      _addOutput('Error: $e');
    }

    _inputController.clear();
  }

  void _copyOutput() {
    final outputText = _output.join('\n');
    if (outputText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: outputText));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              const Text('Output copied to clipboard'),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No output to copy'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (widget.isInteractive) ...[
            // Mode toggle button
            IconButton(
              icon: Icon(_useInteractiveMode ? Icons.terminal : Icons.code),
              tooltip: _useInteractiveMode ? 'Switch to Command Mode' : 'Switch to Interactive Mode',
              onPressed: () {
                setState(() {
                  _useInteractiveMode = !_useInteractiveMode;
                });
                _reinitializeShell();
              },
            ),
            // Interactive shell controls (only show when in interactive mode)
            if (_interactiveShell.isActive) ...[
              IconButton(
                icon: const Icon(Icons.stop),
                tooltip: 'Send Ctrl+C',
                onPressed: () => _interactiveShell.sendInterrupt(),
              ),
              IconButton(
                icon: const Icon(Icons.exit_to_app),
                tooltip: 'Send Ctrl+D (EOF)',
                onPressed: () => _interactiveShell.sendEOF(),
              ),
            ],
            // Clear button
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: () {
                setState(() {
                  _output.clear();
                });
              },
              tooltip: 'Clear output',
            ),
          ],
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              _copyOutput();
            },
            tooltip: 'Copy output',
          ),
        ],
      ),
      body: Column(
        children: [
          // Output area
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Initializing shell...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Container(
                        width: double.infinity,
                        child: SelectableText(
                          _output.join('\n'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          // Input area (only for interactive shells)
          if (widget.isInteractive && _isConnected)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    '\$ ',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        hintText: 'Enter command...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onSubmitted: _executeCommand,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _executeCommand(_inputController.text),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
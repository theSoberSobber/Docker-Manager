import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<String> _output = [];
  bool _isLoading = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initializeShell();
  }

  @override
  void dispose() {
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

      // For interactive shells, show prompt
      if (widget.isInteractive) {
        if (widget.containerInfo != null) {
          _addOutput('Interactive container shell ready.');
          _addOutput('Container: ${widget.containerInfo!['containerId']}');
          _addOutput('Executable: ${widget.containerInfo!['executable']}');
          _addOutput('Commands will be executed inside the container.');
        } else {
          _addOutput('Interactive shell ready. Type commands below:');
        }
        _isConnected = true;
      }
    } catch (e) {
      _addOutput('Error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addOutput(String text) {
    setState(() {
      _output.add(text);
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

  Future<void> _executeCommand(String command) async {
    if (command.trim().isEmpty) return;

    _addOutput('\$ $command');
    
    try {
      String actualCommand = command;
      
      // If we're in a container shell, wrap the command with docker exec
      if (widget.containerInfo != null) {
        final containerId = widget.containerInfo!['containerId'];
        final executable = widget.containerInfo!['executable'];
        
        // For container shells, we need to execute commands inside the container
        // We'll use docker exec for each command
        actualCommand = 'docker exec ${containerId} $executable -c "$command"';
        
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
      
      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.copy, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text('Output copied to clipboard'),
            ],
          ),
          duration: Duration(seconds: 2),
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
          if (widget.isInteractive)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: () {
                setState(() {
                  _output.clear();
                });
              },
              tooltip: 'Clear output',
            ),
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
              color: Colors.black87,
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Loading...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _output.join('\n'),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          color: Colors.grey,
                          height: 1.4,
                        ),
                      ),
                    ),
            ),
          ),
          
          // Input area (only for interactive shells)
          if (widget.isInteractive && _isConnected)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
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
                      autofocus: true,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        hintText: 'Enter command...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
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
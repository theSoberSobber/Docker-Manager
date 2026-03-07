import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../domain/models/server.dart';
import '../../data/services/ssh_connection_service.dart';

class CommandPromptScreen extends StatefulWidget {
  final Server server;
  final String title;
  final String bodyText;
  final String command;

  const CommandPromptScreen({
    super.key,
    required this.server,
    required this.title,
    required this.bodyText,
    required this.command,
  });

  @override
  State<CommandPromptScreen> createState() => _CommandPromptScreenState();
}

class _CommandPromptScreenState extends State<CommandPromptScreen> {
  final SSHConnectionService _sshService = SSHConnectionService();
  final ScrollController _logScrollController = ScrollController();
  
  bool _isExecuting = false;
  bool _hasExecuted = false;
  String _output = '';
  String? _error;

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_logScrollController.hasClients) {
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _executeCommand() async {
    setState(() {
      _isExecuting = true;
      _hasExecuted = true;
      _output = 'Connecting to ${widget.server.name}...\n';
      _error = null;
    });

    try {
      // 1. Connect or switch server
      final connectResult = await _sshService.switchToServer(widget.server);
      if (!connectResult.success) {
        throw Exception(connectResult.error ?? 'Failed to connect to server');
      }

      setState(() {
        _output += 'Connected successfully. Executing command...\n\n\$ ${widget.command}\n\n';
      });

      // 2. Execute command
      final result = await _sshService.executeCommand(widget.command);
      
      if (mounted) {
        setState(() {
          _output += result ?? '';
          if (result == null || result.isEmpty) {
            _output += '[Command completed with no output]';
          }
          _isExecuting = false;
        });
        // Scroll after build
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _output += '\n\nERROR: $_error';
          _isExecuting = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Server Info & Description
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.dns, color: colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                widget.server.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Text(
                            widget.bodyText,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // The Command Block
                  Card(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.black87 
                        : Colors.grey.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.terminal, size: 16, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Command to Execute',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            widget.command,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Output Area (if executed)
                  if (_hasExecuted) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Execution Output',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 250,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _error != null ? Colors.red.shade400 : Colors.grey.shade800,
                        ),
                      ),
                      child: SingleChildScrollView(
                        controller: _logScrollController,
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _output,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: _error != null ? Colors.red.shade300 : Colors.green.shade400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Bottom Action Area
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, -4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: _hasExecuted && !_isExecuting && _error == null
                      // Finished successfully
                      ? FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.check),
                          label: const Text('Done'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                        )
                      // Execute or Retrying
                      : FilledButton.icon(
                          onPressed: _isExecuting ? null : _executeCommand,
                          icon: _isExecuting 
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(
                            _isExecuting 
                                ? 'Executing...' 
                                : (_error != null ? 'Retry Command' : 'Execute Command')
                          ),
                          style: _error != null 
                              ? FilledButton.styleFrom(backgroundColor: Colors.orange)
                              : null,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

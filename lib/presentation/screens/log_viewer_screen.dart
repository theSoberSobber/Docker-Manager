import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../data/services/ssh_connection_service.dart';
import '../widgets/search_bar.dart';

class LogViewerScreen extends StatefulWidget {
  final String title;
  final String command;

  const LogViewerScreen({
    super.key,
    required this.title,
    required this.command,
  });

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final SSHConnectionService _sshService = SSHConnectionService();
  final ScrollController _scrollController = ScrollController();
  final List<String> _output = [];
  List<String> _filteredOutput = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _filteredOutput = _output;
    _executeCommand();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _executeCommand() async {
    setState(() => _isLoading = true);

    try {
      if (!_sshService.isConnected) {
        _addOutput('Error: No SSH connection available');
        setState(() => _isLoading = false);
        return;
      }

      _addOutput('Executing: ${widget.command}');
      _addOutput(''); // Empty line for better readability
      
      final result = await _sshService.executeCommand(widget.command);
      if (result != null && result.isNotEmpty) {
        _addOutput(result);
      } else {
        _addOutput('Command completed with no output');
      }
    } catch (e) {
      _addOutput('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addOutput(String text) {
    // Clean ANSI escape sequences and control characters
    String cleanText = _cleanAnsiEscapes(text);
    
    // Check if this is JSON output from an inspect command
    if (_isInspectCommand() && _isValidJson(cleanText)) {
      cleanText = _formatJson(cleanText);
    }
    
    // Format timestamps if present
    cleanText = _formatTimestamps(cleanText);
    
    setState(() {
      final lines = cleanText.split('\n').where((line) => line.isNotEmpty).toList();
      _output.addAll(lines);
      _filterOutput();
      
      // Auto-scroll to bottom after adding new output
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  String _formatTimestamps(String text) {
    // Match Docker timestamp format: 2025-11-27T07:52:36.262558834Z
    // and convert to: [2025-11-27 07:52:36]
    final timestampRegex = RegExp(
      r'(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})\.\d+Z\s',
    );
    
    return text.replaceAllMapped(timestampRegex, (match) {
      final date = match.group(1);
      final time = match.group(2);
      return '[$date $time] ';
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

  bool _isInspectCommand() {
    return widget.command.contains('inspect');
  }

  bool _isValidJson(String text) {
    try {
      jsonDecode(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _formatJson(String jsonText) {
    try {
      final dynamic jsonObj = jsonDecode(jsonText);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(jsonObj);
    } catch (_) {
      return jsonText;
    }
  }

  void _filterOutput() {
    if (_searchQuery.isEmpty) {
      _filteredOutput = _output;
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredOutput = _output.where((line) => line.toLowerCase().contains(query)).toList();
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _isSearching = query.isNotEmpty;
      _filterOutput();
    });
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _isSearching = false;
      _filterOutput();
    });
  }

  void _copyOutput() {
    final outputToCopy = _isSearching ? _filteredOutput : _output;
    if (outputToCopy.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: outputToCopy.join('\n')));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isSearching ? 'shell.filtered_output_copied'.tr() : 'shell.output_copied'.tr()),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isSearching ? 'shell.no_matching_lines'.tr() : 'shell.no_output_to_copy'.tr()),
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
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyOutput,
            tooltip: 'common.copy_output'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // Search bar
            if (!_isLoading)
              Column(
                children: [
                  CustomSearchBar(
                    hintText: 'common.search_in_output'.tr(),
                    onSearchChanged: _onSearchChanged,
                    onClear: _clearSearch,
                  ),
                  if (_isSearching)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      child: Text(
                        'common.showing_lines'.tr(args: [
                          _filteredOutput.length.toString(),
                          _output.length.toString(),
                        ]),
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            // Output area
            Expanded(
              child: Container(
                width: double.infinity,
                color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
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
                              'Loading...',
                              style: TextStyle(
                                color: isDark ? const Color(0xFFE6EDF3) : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _filteredOutput.isEmpty && _isSearching
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'shell.no_matching_lines'.tr(),
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF6E7681),
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'shell.try_different_search'.tr(),
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF6E7681),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(8),
                            child: SelectionArea(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: _filteredOutput.map((line) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12.0),
                                    child: Text(
                                      line,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 14,
                                        color: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF24292F),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
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

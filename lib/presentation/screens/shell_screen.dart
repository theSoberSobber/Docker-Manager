import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart';
import '../../data/services/ssh_connection_service.dart';

class ShellScreen extends StatefulWidget {
  final String title;
  final bool isInteractive;
  final Map<String, String>? containerInfo;

  const ShellScreen({
    super.key,
    required this.title,
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
  SSHSession? _session;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _initializeShell();
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }

  Future<void> _initializeShell() async {
    setState(() => _isLoading = true);

    try {
      if (!_sshService.isConnected) {
        _terminal.write('Error: No SSH connection available\r\n');
        setState(() => _isLoading = false);
        return;
      }

      // Start interactive shell
      if (widget.isInteractive) {
        await _startInteractiveShell();
      }
    } catch (e) {
      _terminal.write('Error: $e\r\n');
    } finally {
      setState(() => _isLoading = false);
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
      ).timeout(const Duration(seconds: 15));

      // For container shells, enter the container
      if (widget.containerInfo != null) {
        final containerId = widget.containerInfo!['containerId'];
        final executable = widget.containerInfo!['executable'] ?? '/bin/bash';
        
        final prefs = await SharedPreferences.getInstance();
        final dockerCli = prefs.getString('dockerCliPath') ?? 'docker';
        
        _session!.write(utf8.encode('$dockerCli exec -it $containerId $executable\n'));
      }
      
      // Clear connection messages
      await Future.delayed(const Duration(milliseconds: 500));
      _terminal.buffer.clear();
      _terminal.buffer.setCursor(0, 0);
      
      // Wire up terminal ↔ SSH
      _terminal.onResize = (w, h, pw, ph) => _session?.resizeTerminal(w, h, pw, ph);
      _terminal.onOutput = (data) => _session?.write(utf8.encode(data));
      
      _session!.stdout.cast<List<int>>().transform(const Utf8Decoder()).listen(_terminal.write);
      _session!.stderr.cast<List<int>>().transform(const Utf8Decoder()).listen(_terminal.write);
      
    } catch (e) {
      _terminal.write('❌ Failed to start shell: $e\r\n');
    }
  }

  void _copyOutput() {
    final lines = <String>[];
    // Use buffer.height to get the number of lines in the buffer
    for (var i = 0; i < _terminal.buffer.height; i++) {
      final line = _terminal.buffer.lines[i];
      final text = line.toString().trim();
      if (text.isNotEmpty) lines.add(text);
    }
    
    if (lines.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: lines.join('\n')));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
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
          if (widget.isInteractive && _session != null) ...[
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: 'common.send_ctrl_c'.tr(),
              onPressed: () => _session?.write(utf8.encode('\x03')),
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: 'common.send_ctrl_d'.tr(),
              onPressed: () => _session?.write(utf8.encode('\x04')),
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

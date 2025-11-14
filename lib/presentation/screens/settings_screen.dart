import 'package:flutter/material.dart';
import '../widgets/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/ssh_connection_service.dart';
import '../../core/utils/docker_cli_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _defaultLogLines = '500';
  String _dockerCliPath = 'docker';
  final TextEditingController _dockerPathController = TextEditingController();
  bool _isLoading = true;
  bool _isPruning = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _dockerPathController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final dockerPath = await DockerCliConfig.getCliPath();
    
    setState(() {
      _defaultLogLines = prefs.getString('defaultLogLines') ?? '500';
      _dockerCliPath = dockerPath;
      _dockerPathController.text = _dockerCliPath;
      _isLoading = false;
    });
  }

  Future<void> _saveDefaultLogLines(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('defaultLogLines', value);
    setState(() {
      _defaultLogLines = value;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _saveDockerCliPath(String value) async {
    final path = value.trim().isEmpty ? 'docker' : value.trim();
    await DockerCliConfig.setCliPath(path);
    
    setState(() {
      _dockerCliPath = path;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Docker CLI path saved'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _showSystemPruneDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Text('System Prune'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will remove:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('• All stopped containers'),
            Text('• All dangling images'),
            Text('• All unused networks'),
            Text('• All unused volumes'),
            Text('• All build cache'),
            SizedBox(height: 16),
            Text(
              'This action cannot be undone!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Prune System'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _executeSystemPrune();
    }
  }

  Future<void> _executeSystemPrune() async {
    setState(() {
      _isPruning = true;
    });

    try {
      final sshService = SSHConnectionService();
      
      // Get the configured Docker CLI path
      final dockerCmd = await DockerCliConfig.getCliPath();
      
      final result = await sshService.executeCommand('$dockerCmd system prune -af --volumes');
      
      if (mounted) {
        setState(() {
          _isPruning = false;
        });

        // Show result dialog
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Prune Complete'),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(
                (result?.isNotEmpty ?? false) ? result! : 'System prune completed successfully',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPruning = false;
        });

        // Show error dialog
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Prune Failed'),
              ],
            ),
            content: Text(
              e.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Appearance Section
                _buildSectionHeader('Appearance'),
                _buildThemeOption(
                  context,
                  'Light',
                  Icons.light_mode,
                  ThemeMode.light,
                ),
                _buildThemeOption(
                  context,
                  'Dark',
                  Icons.dark_mode,
                  ThemeMode.dark,
                ),
                _buildThemeOption(
                  context,
                  'System',
                  Icons.brightness_auto,
                  ThemeMode.system,
                ),
                
                const Divider(height: 32),
                
                // Docker Configuration Section
                _buildSectionHeader('Docker Configuration'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Docker CLI Path',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Path to Docker CLI binary. Supports Docker, Podman, or custom installations.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _dockerPathController,
                        decoration: InputDecoration(
                          hintText: 'docker (default)',
                          helperText: 'Examples: docker, /usr/bin/docker, /usr/local/bin/podman',
                          helperMaxLines: 2,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.save),
                            onPressed: () {
                              _saveDockerCliPath(_dockerPathController.text);
                            },
                            tooltip: 'Save',
                          ),
                        ),
                        onSubmitted: _saveDockerCliPath,
                      ),
                    ],
                  ),
                ),
                
                const Divider(height: 32),
                
                // Logs Section
                _buildSectionHeader('Logs'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Default log lines to display',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Limiting log output prevents crashes on containers with large logs',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildLogLinesOption('100', '100 lines (fast)'),
                      _buildLogLinesOption('500', '500 lines (recommended)'),
                      _buildLogLinesOption('1000', '1000 lines (detailed)'),
                      _buildLogLinesOption('5000', '5000 lines (may be slow)'),
                      _buildLogLinesOption('all', 'All logs (risky)'),
                    ],
                  ),
                ),
                
                const Divider(height: 32),
                
                // System Maintenance Section
                _buildSectionHeader('System Maintenance'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Clean up Docker resources',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Remove unused containers, images, networks, volumes, and build cache',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _isPruning ? null : _showSystemPruneDialog,
                          icon: _isPruning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.delete_sweep),
                          label: Text(_isPruning ? 'Pruning...' : 'System Prune'),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    String label,
    IconData icon,
    ThemeMode mode,
  ) {
    final themeManager = ThemeManager();
    final isSelected = themeManager.themeMode == mode;

    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      selected: isSelected,
      onTap: () {
        themeManager.setThemeMode(mode);
        setState(() {});
      },
    );
  }

  Widget _buildLogLinesOption(String value, String label) {
    final isSelected = _defaultLogLines == value;
    final isRisky = value == 'all' || value == '5000';

    return RadioListTile<String>(
      value: value,
      groupValue: _defaultLogLines,
      onChanged: (newValue) {
        if (newValue != null) {
          _saveDefaultLogLines(newValue);
        }
      },
      title: Row(
        children: [
          Text(label),
          if (isRisky) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.warning_amber,
              size: 16,
              color: Colors.orange[700],
            ),
          ],
        ],
      ),
      selected: isSelected,
    );
  }
}

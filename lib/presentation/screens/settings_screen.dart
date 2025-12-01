import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../widgets/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/ssh_connection_service.dart';
import '../../data/services/docker_cli_path_service.dart';
import '../../data/services/analytics_service.dart';

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
  final DockerCliPathService _dockerCliPathService = DockerCliPathService();
  final AnalyticsService _analytics = AnalyticsService();

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
    setState(() {
      _defaultLogLines = prefs.getString('defaultLogLines') ?? '500';
      _dockerCliPath = prefs.getString('dockerCliPath') ?? 'docker';
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
    _analytics.trackEvent('settings.logs_default_changed', properties: {
      'value': value,
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('settings.saved'.tr()),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _saveDockerCliPath(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final path = value.trim().isEmpty ? 'docker' : value.trim();
    await prefs.setString('dockerCliPath', path);
    setState(() {
      _dockerCliPath = path;
    });
    _analytics.trackEvent('settings.docker_path_saved', properties: {
      'usesDefault': path == 'docker',
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('settings.docker_cli_saved'.tr()),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _showSystemPruneDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange),
            const SizedBox(width: 8),
            Text('settings.prune_title'.tr()),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.prune_warning'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('settings.prune_stopped_containers'.tr()),
            Text('settings.prune_dangling_images'.tr()),
            Text('settings.prune_unused_networks'.tr()),
            Text('settings.prune_unused_volumes'.tr()),
            Text('settings.prune_build_cache'.tr()),
            const SizedBox(height: 16),
            Text(
              'settings.prune_cannot_undo'.tr(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('settings.prune_system'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _analytics.trackEvent('settings.prune_confirmed');
      await _executeSystemPrune();
    }
  }

  Future<void> _executeSystemPrune() async {
    setState(() {
      _isPruning = true;
    });

    try {
      final sshService = SSHConnectionService();
      
      // Get the configured Docker CLI path (server-specific if set)
      final dockerCmd = await _dockerCliPathService.getDockerCliPath();
      
      final result = await sshService.executeCommand('$dockerCmd system prune -af --volumes');
      await _analytics.trackEvent('settings.prune_started');
      
      if (mounted) {
        setState(() {
          _isPruning = false;
        });
        await _analytics.trackEvent('settings.prune_completed', properties: {
          'resultLength': result?.length ?? 0,
        });

        // Show result dialog
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text('settings.prune_complete'.tr()),
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
                child: Text('common.ok'.tr()),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      await _analytics.trackException('settings.prune_failed', e);
      if (mounted) {
        setState(() {
          _isPruning = false;
        });

        // Show error dialog
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                Text('settings.prune_failed'.tr()),
              ],
            ),
            content: Text(
              e.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('common.ok'.tr()),
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
        title: Text('settings.title'.tr()),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Appearance Section
                _buildSectionHeader('settings.appearance'.tr()),
                _buildThemeOption(
                  context,
                  'settings.theme_light'.tr(),
                  Icons.light_mode,
                  ThemeMode.light,
                ),
                _buildThemeOption(
                  context,
                  'settings.theme_dark'.tr(),
                  Icons.dark_mode,
                  ThemeMode.dark,
                ),
                _buildThemeOption(
                  context,
                  'settings.theme_system'.tr(),
                  Icons.brightness_auto,
                  ThemeMode.system,
                ),
                
                const Divider(height: 32),
                
                // Language Section
                _buildSectionHeader('settings.language'.tr()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: DropdownButtonFormField<Locale>(
                    value: context.locale,
                    decoration: InputDecoration(
                      labelText: 'settings.select_language'.tr(),
                      prefixIcon: const Icon(Icons.language),
                      border: const OutlineInputBorder(),
                    ),
                    items: context.supportedLocales.map((locale) {
                      String displayName;
                      switch (locale.languageCode) {
                        case 'es':
                          displayName = 'Español';
                          break;
                        case 'fr':
                          displayName = 'Français';
                          break;
                        case 'en':
                        default:
                          displayName = 'English';
                          break;
                      }
                      return DropdownMenuItem<Locale>(
                        value: locale,
                        child: Text(displayName),
                      );
                    }).toList(),
                    onChanged: (Locale? locale) async {
                      if (locale != null) {
                        await context.setLocale(locale);
                        setState(() {});
                        _analytics.trackEvent('settings.language_changed', properties: {
                          'language': locale.languageCode,
                        });
                        if (mounted) {
                          String label;
                          switch (locale.languageCode) {
                            case 'es':
                              label = 'Español';
                              break;
                            case 'fr':
                              label = 'Français';
                              break;
                            case 'en':
                            default:
                              label = 'English';
                              break;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('settings.language_changed'.tr(args: [label])),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                
                const Divider(height: 32),
                
                // Docker Configuration Section
                _buildSectionHeader('settings.docker_config'.tr()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'settings.docker_cli_path'.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'settings.docker_cli_description'.tr(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _dockerPathController,
                        decoration: InputDecoration(
                          hintText: 'settings.docker_cli_hint'.tr(),
                          helperText: 'settings.docker_cli_help'.tr(),
                          helperMaxLines: 2,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.save),
                            onPressed: () {
                              _saveDockerCliPath(_dockerPathController.text);
                            },
                            tooltip: 'common.save'.tr(),
                          ),
                        ),
                        onSubmitted: _saveDockerCliPath,
                      ),
                    ],
                  ),
                ),
                
                const Divider(height: 32),
                
                // Logs Section
                _buildSectionHeader('settings.logs'.tr()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'settings.default_log_lines'.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'settings.log_lines_description'.tr(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildLogLinesOption('100', 'settings.log_100'.tr()),
                      _buildLogLinesOption('500', 'settings.log_500'.tr()),
                      _buildLogLinesOption('1000', 'settings.log_1000'.tr()),
                      _buildLogLinesOption('5000', 'settings.log_5000'.tr()),
                      _buildLogLinesOption('all', 'settings.log_all'.tr()),
                    ],
                  ),
                ),
                
                const Divider(height: 32),
                
                // System Maintenance Section
                _buildSectionHeader('settings.system_maintenance'.tr()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'settings.clean_resources'.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'settings.clean_description'.tr(),
                        style: const TextStyle(
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
                          label: Text(_isPruning ? 'settings.pruning'.tr() : 'settings.prune_system'.tr()),
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
        _analytics.trackEvent('settings.theme_changed', properties: {
          'mode': mode.name,
        });
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

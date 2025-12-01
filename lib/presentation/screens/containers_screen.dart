import 'package:flutter/material.dart';
import '../../domain/models/docker_container.dart';
import '../../domain/repositories/docker_repository.dart';
import '../../data/repositories/docker_repository_impl.dart';
import '../../data/services/ssh_connection_service.dart';
import '../../data/services/docker_cli_path_service.dart';
import '../../domain/models/server.dart';
import '../widgets/docker_resource_actions.dart';
import '../widgets/search_bar_with_settings.dart';
import 'shell_screen.dart';
import 'log_viewer_screen.dart';
import 'settings_screen.dart';
import 'file_system_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends State<ContainersScreen> 
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final DockerRepository _dockerRepository = DockerRepositoryImpl();
  final SSHConnectionService _sshService = SSHConnectionService();
  final DockerCliPathService _dockerCliPathService = DockerCliPathService();
  List<DockerContainer> _containers = [];
  List<DockerContainer> _filteredContainers = [];
  final Map<String, String> _stackActionsInProgress = {}; // stackName -> action
  bool _showStackCards = true;
  bool _isLoading = false;
  String? _error;
  bool _hasTriedLoading = false;
  Server? _lastKnownServer;
  String? _lastLoadedServerId; // Track which server we loaded data for
  String _searchQuery = '';
  String? _selectedStack; // null means "All", "no-stack" means containers without stack

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize with current server to avoid false detection of server change
    _lastKnownServer = _sshService.currentServer;
    _loadUserPreferences();
    // If no connection exists on init, mark as tried to avoid showing "initializing"
    if (!_sshService.isConnected && !_sshService.isConnecting) {
      _hasTriedLoading = true;
      _error = 'connection.please_connect';
    }
    // Start a periodic check to detect server changes
    _startServerChangeDetection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startServerChangeDetection() {
    Future.delayed(const Duration(seconds: 1), () async {
      if (!mounted) return;
      
      final currentServer = _sshService.currentServer;
      
      if (_lastKnownServer?.id != currentServer?.id) {
        _lastKnownServer = currentServer;
        _lastLoadedServerId = null; // Clear loaded server to trigger reload
        _hasTriedLoading = false;
        _checkConnectionAndLoad();
      }

      // Refresh user preferences periodically so settings apply without restart
      await _loadUserPreferences();
      
      // Continue checking
      _startServerChangeDetection();
    });
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final showCards = prefs.getBool('showComposeStackCards') ?? true;
    if (showCards != _showStackCards) {
      setState(() {
        _showStackCards = showCards;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadUserPreferences();
    // This gets called when the tab becomes visible
    // Only load if we haven't loaded for the current server yet
    final currentServerId = _sshService.currentServer?.id;
    if (!_hasTriedLoading && mounted && _lastLoadedServerId != currentServerId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkConnectionAndLoad();
        }
      });
    }
  }

  /// Check if SSH is connected before loading
  Future<void> _checkConnectionAndLoad() async {
    if (!mounted) return;
    
    // Check connection status first before setting loading state
    if (!_sshService.isConnected && !_sshService.isConnecting) {
      // No connection at all - show error immediately without loading state
      setState(() {
        _hasTriedLoading = true;
        _isLoading = false;
        _error = 'connection.please_connect';
      });
      return;
    }
    
    setState(() {
      _hasTriedLoading = true;
      _isLoading = true;
      _error = null;
    });

    if (_sshService.isConnected) {
      // Connection is ready, load immediately
      await _loadContainers();
    } else if (_sshService.isConnecting) {
      // Connection is in progress, wait and try again
      // Wait up to 10 seconds for connection
      bool connectionSucceeded = false;
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        
        if (_sshService.isConnected) {
          connectionSucceeded = true;
          await _loadContainers();
          return;
        }
        if (_sshService.status == ConnectionStatus.failed || 
            _sshService.status == ConnectionStatus.disconnected) {
          break;
        }
      }
      
      if (!connectionSucceeded && mounted) {
        setState(() {
          _isLoading = false;
          _error = 'connection.timeout';
        });
      }
    } else {
      // No connection
      setState(() {
        _isLoading = false;
        _error = 'connection.no_connection';
      });
    }
  }

  Future<void> _loadContainers() async {
    final loadingForServerId = _sshService.currentServer?.id;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final containers = await _dockerRepository.getContainers();
      
      // Only update if still on the same server
      if (!mounted || _sshService.currentServer?.id != loadingForServerId) {
        return;
      }
      
      // Show containers immediately without stats
      setState(() {
        _containers = containers;
        _filteredContainers = _filterContainers(containers, _searchQuery);
        _isLoading = false;
        _lastLoadedServerId = loadingForServerId; // Mark that we loaded data for this server
      });
      
      // Fetch stats asynchronously in the background
      _loadContainerStats();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadContainerStats() async {
    try {
      final statsMap = await _dockerRepository.getContainerStats();
      
      if (!mounted) return;
      
      // Merge stats into containers
      final containersWithStats = _containers.map((container) {
        final stats = statsMap[container.id];
        if (stats != null) {
          return container.copyWithStats(
            cpuPerc: stats['cpuPerc'],
            memUsage: stats['memUsage'],
            memPerc: stats['memPerc'],
            netIO: stats['netIO'],
            blockIO: stats['blockIO'],
            pids: stats['pids'],
          );
        }
        return container;
      }).toList();
      
      setState(() {
        _containers = containersWithStats;
        _filteredContainers = _filterContainers(containersWithStats, _searchQuery);
      });
    } catch (e) {
      // Stats fetch failed, but containers are already displayed
      debugPrint('Failed to fetch container stats: $e');
    }
  }

  Future<void> _refreshContainers() async {
    _hasTriedLoading = false; // Reset the flag to allow reload
    await _checkConnectionAndLoad();
  }

  /// Get unique stack names from containers
  List<String> _getAvailableStacks() {
    final stacks = _containers
        .where((c) => c.isPartOfStack)
        .map((c) => c.composeProject!)
        .toSet()
        .toList()
      ..sort();
    return stacks;
  }

  /// Filter containers by search query and selected stack
  List<DockerContainer> _filterContainers(List<DockerContainer> containers, String query) {
    var filtered = containers;

    // Filter by stack first
    if (_selectedStack != null) {
      if (_selectedStack == 'no-stack') {
        filtered = filtered.where((c) => !c.isPartOfStack).toList();
      } else {
        filtered = filtered.where((c) => c.composeProject == _selectedStack).toList();
      }
    }

    // Then filter by search query
    if (query.isEmpty) return filtered;
    
    final lowercaseQuery = query.toLowerCase();
    return filtered.where((container) {
      return container.names.toLowerCase().contains(lowercaseQuery) ||
             container.image.toLowerCase().contains(lowercaseQuery) ||
             container.status.toLowerCase().contains(lowercaseQuery) ||
             container.id.toLowerCase().contains(lowercaseQuery) ||
             (container.composeProject?.toLowerCase().contains(lowercaseQuery) ?? false);
    }).toList();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _filteredContainers = _filterContainers(_containers, query);
    });
  }

  void _onStackFilterChanged(String? stack) {
    setState(() {
      _selectedStack = stack;
      _filteredContainers = _filterContainers(_containers, _searchQuery);
    });
  }

  List<_ComposeStackInfo> _buildStackInfos() {
    final Map<String, List<DockerContainer>> stacks = {};
    for (final container in _containers.where((c) => c.isPartOfStack)) {
      stacks.putIfAbsent(container.composeProject!, () => []).add(container);
    }

    final infos = stacks.entries.map((entry) {
      final containers = entry.value;
      final workingDir = containers
          .map((c) => c.composeWorkingDir)
          .firstWhere((dir) => dir != null && dir.trim().isNotEmpty, orElse: () => null);
      final configFiles = containers
          .map((c) => c.composeConfigFiles)
          .firstWhere((files) => files != null && files.trim().isNotEmpty, orElse: () => null);
      final fallbackPath = containers
          .map((c) => c.composeProjectPath)
          .firstWhere((path) => path != null && path.trim().isNotEmpty, orElse: () => null);

      return _ComposeStackInfo(
        name: entry.key,
        containers: containers,
        workingDir: workingDir,
        configFiles: configFiles,
        fallbackPath: fallbackPath,
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return infos;
  }

  Future<void> _handleStackAction(
    String stack,
    _ComposeStackInfo info,
    String action,
  ) async {
    setState(() {
      _stackActionsInProgress[stack] = action;
    });

    try {
      final dockerCli = await _dockerCliPathService.getDockerCliPath();
      String command;

      if (info.canUseComposeCli) {
        final projectDir = info.projectDirectory ?? info.filesPath;
        final buffer = StringBuffer('$dockerCli compose ');
        if (projectDir != null && projectDir.isNotEmpty) {
          buffer.write('--project-directory ${_shellQuote(projectDir)} ');
        }
        buffer.write('--project-name ${_shellQuote(stack)} ');
        for (final file in info.configFileList) {
          buffer.write('-f ${_shellQuote(file)} ');
        }
        final composeAction = action == 'start' ? 'up -d' : action;
        buffer.write(composeAction);
        command = buffer.toString();
      } else {
        final ids = info.containers.map((c) => c.id).join(' ');
        if (ids.trim().isEmpty) {
          throw Exception('No containers found for stack $stack');
        }
        final directAction = action == 'start' ? 'start' : action;
        command = '$dockerCli $directAction $ids';
      }

      await _sshService.executeCommand(command);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'containers.stack_action_success'
                        .tr(args: [stack, _stackActionLabel(action)]),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        await _refreshContainers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('containers.stack_action_failed'.tr(args: [e.toString()])),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _stackActionsInProgress.remove(stack);
        });
      }
    }
  }

  void _openStackFiles(_ComposeStackInfo info) {
    final path = info.filesPath;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('containers.stack_missing_path'.tr())),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FileSystemScreen(
          initialPath: path,
          title: 'file_manager.title'.tr(),
        ),
      ),
    );
  }

  String _shellQuote(String input) {
    final escaped = input.replaceAll("'", "'\"'\"'");
    return "'$escaped'";
  }

  String _stackActionLabel(String action) {
    switch (action) {
      case 'start':
        return 'containers.stack_started'.tr();
      case 'stop':
        return 'containers.stack_stopped'.tr();
      case 'restart':
        return 'containers.stack_restarted'.tr();
      default:
        return action;
    }
  }

  Future<void> _handleContainerAction(DockerAction action, DockerContainer container) async {
    try {
      String command;
      final dockerCli = await _dockerCliPathService.getDockerCliPath();
      
      // Build the complete Docker command based on the action
      switch (action.command) {
        case 'docker logs':
          // Get settings
          final prefs = await SharedPreferences.getInstance();
          final logLines = prefs.getString('defaultLogLines') ?? '500';
          
          // Build command with timestamps enabled by default
          if (logLines == 'all') {
            command = '$dockerCli logs --timestamps ${container.id}';
          } else {
            command = '$dockerCli logs --timestamps --tail $logLines ${container.id}';
          }
          
          // Navigate to log viewer for logs
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => LogViewerScreen(
                title: '${('common.logs').tr()} - ${container.names}',
                command: command,
              ),
            ),
          );
          return;
          
        case 'docker inspect':
          command = '$dockerCli inspect ${container.id}';
          // Navigate to log viewer for inspect
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => LogViewerScreen(
                title: '${'actions.inspect'.tr()} - ${container.names}',
                command: command,
              ),
            ),
          );
          return;
          
        case 'docker exec -it':
          // Show dialog to choose shell executable
          _showShellExecutableDialog(container);
          return;
          
        case 'docker stop':
          command = '$dockerCli stop ${container.id}';
          break;
        case 'docker start':
          command = '$dockerCli start ${container.id}';
          break;
        case 'docker restart':
          command = '$dockerCli restart ${container.id}';
          break;
        case 'docker rm':
          command = '$dockerCli rm ${container.id}';
          break;
        default:
          command = '${action.command.replaceFirst('docker', dockerCli)} ${container.id}';
      }

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text('containers.action_in_progress'.tr(args: [action.label])),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Execute the command
      final result = await _sshService.executeCommand(command);
      
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        
        if (result != null && result.isNotEmpty) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Text('containers.action_success'.tr(args: [action.label])),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          
          // Refresh container list for state-changing operations
          if (action.command.contains('stop') || 
              action.command.contains('start') || 
              action.command.contains('restart') ||
              action.command.contains('rm')) {
            await _refreshContainers();
          }
        } else {
          // Command executed but no output
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('containers.action_completed'.tr(args: [action.label])),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('containers.action_failed'.tr(args: [action.label, e.toString()]))),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _showShellExecutableDialog(DockerContainer container) {
    final TextEditingController executableController = TextEditingController(text: '/bin/bash');
    
    final commonExecutables = [
      '/bin/bash',
      '/bin/sh',
      '/bin/ash',
      '/bin/zsh',
      '/bin/fish',
      'redis-cli',
      'mysql',
      'psql',
      'mongo',
      'python',
      'node',
    ];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('containers.choose_shell'.tr(args: [container.names])),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: executableController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Executable',
                  hintText: 'Enter executable path or command',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.of(context).pop();
                    _openInteractiveShell(container, value.trim());
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Common executables:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: commonExecutables.map((executable) {
                      return ActionChip(
                        label: Text(executable),
                        onPressed: () {
                          executableController.text = executable;
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('common.cancel'.tr()),
            ),
            ElevatedButton(
              onPressed: () {
                final executable = executableController.text.trim();
                if (executable.isNotEmpty) {
                  Navigator.of(context).pop();
                  _openInteractiveShell(container, executable);
                }
              },
              child: Text('common.connect'.tr()),
            ),
          ],
        );
      },
    );
  }

  void _openInteractiveShell(DockerContainer container, String executable) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ShellScreen(
          title: 'Shell - ${container.names}',
          isInteractive: true,
          containerInfo: {
            'containerId': container.id,
            'executable': executable,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    if (!_hasTriedLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('containers.initializing'.tr()),
          ],
        ),
      );
    }
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('containers.loading'.tr()),
          ],
        ),
      );
    }

    if (_error != null) {
      // Check for connection-related errors using both English text (for exceptions)
      // and translation keys (for user-set errors)
      final isConnectionError = _error!.contains('No SSH connection') || 
                                _error!.contains('Connection timeout') ||
                                _error == 'connection.timeout' ||
                                _error == 'connection.no_connection' ||
                                _error == 'connection.please_connect' ||
                                _error!.contains('Failed to get containers: Exception: No SSH connection');
      final isPermissionError = _error!.contains('Permission denied') || 
                                _error!.contains('docker group');
      
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isConnectionError ? Icons.cloud_off : 
              isPermissionError ? Icons.lock_outline : 
              Icons.error_outline,
              size: 64,
              color: isConnectionError ? Colors.orange[400] : 
                     isPermissionError ? Colors.amber[600] :
                     Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              isConnectionError ? 'connection.no_server_connection'.tr() : 
              isPermissionError ? 'connection.permission_issue'.tr() :
              'containers.failed_to_load'.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                isConnectionError 
                  ? 'connection.please_connect'.tr()
                  : _error!.startsWith('connection.') || _error!.startsWith('containers.') ? _error!.tr() : _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isConnectionError) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('connection.tap_server_icon'.tr()),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                    icon: const Icon(Icons.dns),
                    label: Text('connection.connect_to_server'.tr()),
                  ),
                  const SizedBox(width: 12),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: _refreshContainers,
                    icon: const Icon(Icons.refresh),
                    label: Text('common.retry'.tr()),
                  ),
                  const SizedBox(width: 12),
                ],
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: Text('common.settings'.tr()),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_containers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'containers.no_containers'.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'containers.pull_to_refresh'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _refreshContainers,
                  icon: const Icon(Icons.refresh),
                  label: Text('common.refresh'.tr()),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: Text('common.settings'.tr()),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_filteredContainers.isEmpty && _searchQuery.isNotEmpty) {
      return Column(
        children: [
          SearchBarWithSettings(
            hintText: 'common.search_containers_hint'.tr(),
            onSearchChanged: _onSearchChanged,
          ),
          Expanded(
            child: Center(
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
                    'containers.no_search_results'.tr(),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'common.try_different_search'.tr(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final stackInfos = _buildStackInfos();

    return Column(
      children: [
        SearchBarWithSettings(
          hintText: 'common.search_containers_hint'.tr(),
          onSearchChanged: _onSearchChanged,
        ),
        _buildStackFilterChips(),
        if (_showStackCards && stackInfos.isNotEmpty) _buildStackManagementRow(stackInfos),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshContainers,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filteredContainers.length,
              itemBuilder: (context, index) {
                final container = _filteredContainers[index];
                return _buildContainerCard(container);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStackFilterChips() {
    final availableStacks = _getAvailableStacks();
    final hasStandaloneContainers = _containers.any((c) => !c.isPartOfStack);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // "All" chip
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('containers.all_count'.tr(args: [_containers.length.toString()])),
                selected: _selectedStack == null,
                onSelected: (selected) {
                  if (selected) _onStackFilterChanged(null);
                },
              ),
            ),
            // Stack chips
            ...availableStacks.map((stack) {
              final count = _containers.where((c) => c.composeProject == stack).length;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.layers, size: 16),
                      const SizedBox(width: 4),
                      Text('containers.stack_count'.tr(args: [stack, count.toString()])),
                    ],
                  ),
                  selected: _selectedStack == stack,
                  onSelected: (selected) {
                    _onStackFilterChanged(selected ? stack : null);
                  },
                ),
              );
            }),
            // "No Stack" chip
            if (hasStandaloneContainers)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text('containers.no_stack_count'.tr(args: [_containers.where((c) => !c.isPartOfStack).length.toString()])),
                  selected: _selectedStack == 'no-stack',
                  onSelected: (selected) {
                    _onStackFilterChanged(selected ? 'no-stack' : null);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStackManagementRow(List<_ComposeStackInfo> stackInfos) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_outlined, size: 18),
              const SizedBox(width: 6),
              Text(
                'containers.stack_actions'.tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: stackInfos.map(_buildStackCard).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackCard(_ComposeStackInfo info) {
    final actionInProgress = _stackActionsInProgress[info.name];
    final isBusy = actionInProgress != null;
    final runningLabel = 'containers.stack_running_status'
        .tr(args: [info.runningCount.toString(), info.totalCount.toString()]);
    final canOpenFiles = info.filesPath != null && info.filesPath!.isNotEmpty;

    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.7),
        ),
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      runningLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[700],
                          ),
                    ),
                  ],
                ),
              ),
              if (isBusy)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          if (info.filesPath != null) ...[
            const SizedBox(height: 4),
            Text(
              info.filesPath!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text('containers.stack_start'.tr()),
                onPressed: isBusy ? null : () => _handleStackAction(info.name, info, 'start'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.stop, size: 18),
                label: Text('containers.stack_stop'.tr()),
                onPressed: isBusy ? null : () => _handleStackAction(info.name, info, 'stop'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('containers.stack_restart'.tr()),
                onPressed: isBusy ? null : () => _handleStackAction(info.name, info, 'restart'),
              ),
              TextButton.icon(
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text('containers.stack_files'.tr()),
                onPressed: isBusy || !canOpenFiles ? null : () => _openStackFiles(info),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContainerCard(DockerContainer container) {
    final isRunning = container.status.toLowerCase().startsWith('up');
    final statusColor = isRunning ? Colors.green : Colors.orange;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with name, status, and actions
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              container.names,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (container.isPartOfStack) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.layers,
                                    size: 14,
                                    color: Colors.blue[700],
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${container.composeProject}${container.composeService != null ? ' / ${container.composeService}' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isRunning ? Icons.play_circle : Icons.pause_circle,
                              size: 16,
                              color: statusColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isRunning ? 'common.running'.tr() : 'common.stopped'.tr(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Action menu
                DockerResourceActions(
                  actions: ContainerActions.getActions(isRunning),
                  onActionSelected: (action) => _handleContainerAction(action, container),
                  resourceName: container.names,
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Container details
            _buildDetailRow('common.id'.tr(), container.id.length > 12 
                ? '${container.id.substring(0, 12)}...' 
                : container.id),
            _buildDetailRow('common.image'.tr(), container.image),
            _buildDetailRow('common.command'.tr(), container.command),
            _buildDetailRow('common.created'.tr(), container.created),
            _buildDetailRow('common.status'.tr(), container.status),
            if (container.ports.isNotEmpty)
              _buildDetailRow('common.ports'.tr(), container.ports.join(', ')),
            
            // Container stats (show for running containers)
            if (isRunning) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: container.hasStats
                    ? Row(
                        children: [
                          Expanded(
                            child: _buildStatColumn(
                              icon: Icons.speed,
                              label: 'containers.stats.cpu'.tr(),
                              value: container.cpuPerc ?? 'N/A',
                            ),
                          ),
                          Expanded(
                            child: _buildStatColumn(
                              icon: Icons.memory,
                              label: 'containers.stats.memory'.tr(),
                              value: container.memPerc ?? 'N/A',
                            ),
                          ),
                          Expanded(
                            child: _buildStatColumn(
                              icon: Icons.cloud_queue,
                              label: 'containers.stats.network'.tr(),
                              value: container.netIO ?? 'N/A',
                            ),
                          ),
                          Expanded(
                            child: _buildStatColumn(
                              icon: Icons.format_list_numbered,
                              label: 'containers.stats.pids'.tr(),
                              value: container.pids ?? 'N/A',
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.blue[700]!,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Loading stats...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.blue[700],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ComposeStackInfo {
  final String name;
  final List<DockerContainer> containers;
  final String? workingDir;
  final String? configFiles;
  final String? fallbackPath;

  const _ComposeStackInfo({
    required this.name,
    required this.containers,
    this.workingDir,
    this.configFiles,
    this.fallbackPath,
  });

  int get totalCount => containers.length;

  int get runningCount =>
      containers.where((c) => c.status.toLowerCase().startsWith('up')).length;

  String? get projectDirectory {
    if (workingDir != null && workingDir!.trim().isNotEmpty) {
      return workingDir!.trim();
    }
    if (fallbackPath != null && fallbackPath!.trim().isNotEmpty) {
      return fallbackPath!.trim();
    }
    return null;
  }

  List<String> get configFileList {
    if (configFiles == null || configFiles!.trim().isEmpty) return [];
    return configFiles!
        .split(RegExp(r'[;,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool get canUseComposeCli {
    if (projectDirectory != null && projectDirectory!.isNotEmpty) {
      return true;
    }
    return configFileList.any((file) => file.contains('/'));
  }

  String? get filesPath {
    if (projectDirectory != null && projectDirectory!.isNotEmpty) {
      return projectDirectory;
    }
    if (fallbackPath != null && fallbackPath!.trim().isNotEmpty) {
      return fallbackPath;
    }
    if (configFileList.isEmpty) return null;

    final config = configFileList.first;
    final lastSlash = config.lastIndexOf('/');
    if (lastSlash > 0) {
      return config.substring(0, lastSlash);
    }
    return null;
  }
}

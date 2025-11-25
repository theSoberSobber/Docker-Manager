import 'package:flutter/material.dart';
import '../../domain/models/docker_container.dart';
import '../../domain/repositories/docker_repository.dart';
import '../../data/repositories/docker_repository_impl.dart';
import '../../data/services/ssh_connection_service.dart';
import '../../domain/models/server.dart';
import '../widgets/docker_resource_actions.dart';
import '../widgets/search_bar_with_settings.dart';
import 'shell_screen.dart';
import 'settings_screen.dart';
import 'server_list_screen.dart';
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
  List<DockerContainer> _containers = [];
  List<DockerContainer> _filteredContainers = [];
  bool _isLoading = false;
  String? _error;
  bool _hasTriedLoading = false;
  Server? _lastKnownServer;
  String _searchQuery = '';
  String? _selectedStack; // null means "All", "no-stack" means containers without stack

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start a periodic check to detect server changes
    _startServerChangeDetection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Start a timer to detect when server changes
  void _startServerChangeDetection() {
    // Check every second if the server changed
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      
      final currentServer = _sshService.currentServer;
      
      // Only reload if server actually changed (not just checking connection status)
      if (_lastKnownServer?.id != currentServer?.id) {
        _lastKnownServer = currentServer;
        _hasTriedLoading = false; // Reset to allow reload
        _checkConnectionAndLoad();
      }
      
      // Continue checking
      _startServerChangeDetection();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This gets called when the tab becomes visible
    if (!_hasTriedLoading && mounted) {
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
          _error = 'Connection timeout. Please try again or check your server connection.';
        });
      }
    } else {
      // No connection
      setState(() {
        _isLoading = false;
        _error = 'No SSH connection available. Please connect to a server first.';
      });
    }
  }

  Future<void> _loadContainers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final containers = await _dockerRepository.getContainers();
      
      // Show containers immediately without stats
      setState(() {
        _containers = containers;
        _filteredContainers = _filterContainers(containers, _searchQuery);
        _isLoading = false;
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

  Future<void> _handleContainerAction(DockerAction action, DockerContainer container) async {
    try {
      String command;
      
      // Build the complete Docker command based on the action
      switch (action.command) {
        case 'docker logs':
          // Get settings
          final prefs = await SharedPreferences.getInstance();
          final logLines = prefs.getString('defaultLogLines') ?? '500';
          final dockerCli = prefs.getString('dockerCliPath') ?? 'docker';
          
          // Build command based on setting
          if (logLines == 'all') {
            command = '$dockerCli logs ${container.id}';
          } else {
            command = '$dockerCli logs --tail $logLines ${container.id}';
          }
          
          // Navigate to shell screen for logs
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ShellScreen(
                title: '${('common.logs').tr()} - ${container.names}',
                command: command,
              ),
            ),
          );
          return;
          
        case 'docker inspect':
          final prefs = await SharedPreferences.getInstance();
          final dockerCli = prefs.getString('dockerCliPath') ?? 'docker';
          command = '$dockerCli inspect ${container.id}';
          // Navigate to shell screen for inspect
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ShellScreen(
                title: 'Inspect - ${container.names}',
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
          final prefs1 = await SharedPreferences.getInstance();
          final dockerCli1 = prefs1.getString('dockerCliPath') ?? 'docker';
          command = '$dockerCli1 stop ${container.id}';
          break;
        case 'docker start':
          final prefs2 = await SharedPreferences.getInstance();
          final dockerCli2 = prefs2.getString('dockerCliPath') ?? 'docker';
          command = '$dockerCli2 start ${container.id}';
          break;
        case 'docker restart':
          final prefs3 = await SharedPreferences.getInstance();
          final dockerCli3 = prefs3.getString('dockerCliPath') ?? 'docker';
          command = '$dockerCli3 restart ${container.id}';
          break;
        case 'docker rm':
          final prefs4 = await SharedPreferences.getInstance();
          final dockerCli4 = prefs4.getString('dockerCliPath') ?? 'docker';
          command = '$dockerCli4 rm ${container.id}';
          break;
        default:
          final prefsDefault = await SharedPreferences.getInstance();
          final dockerCliDefault = prefsDefault.getString('dockerCliPath') ?? 'docker';
          command = '${action.command.replaceFirst('docker', dockerCliDefault)} ${container.id}';
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
      final isConnectionError = _error!.contains('No SSH connection') || 
                                _error!.contains('Connection timeout') ||
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
              isConnectionError ? 'No Server Connection' : 
              isPermissionError ? 'Permission Issue' :
              'Failed to load containers',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                isConnectionError 
                  ? 'Please connect to a server to view containers'
                  : _error!,
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ServerListScreen(
                            onServerSelected: (server) {
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.dns),
                    label: Text('connection.connect_to_server'.tr()),
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
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: _refreshContainers,
                    icon: const Icon(Icons.refresh),
                    label: Text('common.retry'.tr()),
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
              'No containers found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'No Docker containers are available on this server.',
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
                    'No containers match your search',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try a different search term',
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

    return Column(
      children: [
        SearchBarWithSettings(
          hintText: 'common.search_containers_hint'.tr(),
          onSearchChanged: _onSearchChanged,
        ),
        _buildStackFilterChips(),
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
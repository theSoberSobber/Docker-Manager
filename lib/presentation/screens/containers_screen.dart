import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/docker_container.dart';
import '../../domain/repositories/docker_repository.dart';
import '../../data/repositories/docker_repository_impl.dart';
import '../../core/utils/docker_cli_config.dart';
import '../widgets/search_bar_with_settings.dart';
import '../widgets/docker_resource_actions.dart';
import 'settings_screen.dart';
import 'shell_screen.dart';
import 'base/base_resource_screen.dart';

class ContainersScreen extends BaseResourceScreen<DockerContainer> {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends BaseResourceScreenState<DockerContainer, ContainersScreen> {
  final DockerRepository _dockerRepository = DockerRepositoryImpl();
  String? _selectedStack;

  @override
  Future<List<DockerContainer>> fetchItems() async {
    final containers = await _dockerRepository.getContainers();
    
    // Fetch stats asynchronously in the background after showing containers
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _loadContainerStats();
      }
    });
    
    return containers;
  }

  Future<void> _loadContainerStats() async {
    try {
      final statsMap = await _dockerRepository.getContainerStats();
      
      if (!mounted) return;
      
      // Merge stats into containers
      final containersWithStats = items.map((container) {
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
        items = containersWithStats;
        filteredItems = filterItems(containersWithStats, searchQuery);
      });
    } catch (e) {
      // Stats fetch failed, but containers are already displayed
      debugPrint('Failed to fetch container stats: $e');
    }
  }

  @override
  List<DockerContainer> filterItems(List<DockerContainer> containers, String query) {
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

  void _onStackFilterChanged(String? stack) {
    setState(() {
      _selectedStack = stack;
      filteredItems = filterItems(items, searchQuery);
    });
  }

  /// Get unique stack names from containers
  List<String> _getAvailableStacks() {
    final stacks = items
        .where((c) => c.isPartOfStack)
        .map((c) => c.composeProject!)
        .toSet()
        .toList()
      ..sort();
    return stacks;
  }

  @override
  String getResourceName() => 'containers';

  @override
  IconData getEmptyIcon() => Icons.view_in_ar;

  @override
  Widget buildItemCard(DockerContainer container) {
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
                              isRunning ? 'Running' : 'Stopped',
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
            _buildDetailRow('ID', container.id.length > 12 
                ? '${container.id.substring(0, 12)}...' 
                : container.id),
            _buildDetailRow('Image', container.image),
            _buildDetailRow('Command', container.command),
            _buildDetailRow('Created', container.created),
            _buildDetailRow('Status', container.status),
            if (container.ports.isNotEmpty)
              _buildDetailRow('Ports', container.ports.join(', ')),
            
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
                              label: 'CPU',
                              value: container.cpuPerc ?? 'N/A',
                            ),
                          ),
                          Expanded(
                            child: _buildStatColumn(
                              icon: Icons.memory,
                              label: 'Memory',
                              value: container.memPerc ?? 'N/A',
                            ),
                          ),
                          Expanded(
                            child: _buildStatColumn(
                              icon: Icons.cloud_queue,
                              label: 'Network',
                              value: container.netIO ?? 'N/A',
                            ),
                          ),
                          Expanded(
                            child: _buildStatColumn(
                              icon: Icons.format_list_numbered,
                              label: 'PIDs',
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

  @override
  Widget buildErrorState(BuildContext context) {
    final isConnectionError = error!.contains('No SSH connection') || 
                              error!.contains('Connection timeout') ||
                              error!.contains('Failed to get containers: Exception: No SSH connection');
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isConnectionError ? Icons.cloud_off : Icons.error_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            isConnectionError ? 'Not Connected' : 'Error',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isConnectionError) ...[
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
                  label: const Text('Settings'),
                ),
                const SizedBox(width: 12),
              ],
              ElevatedButton.icon(
                onPressed: loadItems,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.view_in_ar,
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
            'Start a container to see it here',
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
                onPressed: loadItems,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
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
                label: const Text('Settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget buildNoSearchResultsState(BuildContext context) {
    return Column(
      children: [
        SearchBarWithSettings(
          hintText: 'Search containers by name, image, status, or ID...',
          onSearchChanged: onSearchChanged,
        ),
        _buildStackFilterChips(),
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

  @override
  Widget buildItemList(BuildContext context) {
    return Column(
      children: [
        SearchBarWithSettings(
          hintText: 'Search containers by name, image, status, or ID...',
          onSearchChanged: onSearchChanged,
        ),
        _buildStackFilterChips(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: loadItems,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                final container = filteredItems[index];
                return buildItemCard(container);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStackFilterChips() {
    final availableStacks = _getAvailableStacks();
    final hasStandaloneContainers = items.any((c) => !c.isPartOfStack);

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
                label: Text('All (${items.length})'),
                selected: _selectedStack == null,
                onSelected: (selected) {
                  if (selected) _onStackFilterChanged(null);
                },
              ),
            ),
            // Stack chips
            ...availableStacks.map((stack) {
              final count = items.where((c) => c.composeProject == stack).length;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.layers, size: 16),
                      const SizedBox(width: 4),
                      Text('$stack ($count)'),
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
                  label: Text('No Stack (${items.where((c) => !c.isPartOfStack).length})'),
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

  Future<void> _handleContainerAction(DockerAction action, DockerContainer container) async {
    try {
      String command;
      
      // Build the complete Docker command based on the action
      switch (action.command) {
        case 'docker logs':
          // Get settings
          final prefs = await SharedPreferences.getInstance();
          final logLines = prefs.getString('defaultLogLines') ?? '500';
          final dockerCli = await DockerCliConfig.getCliPath();
          
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
                title: 'Logs - ${container.names}',
                command: command,
              ),
            ),
          );
          return;
          
        case 'docker inspect':
          final dockerCli = await DockerCliConfig.getCliPath();
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
          final dockerCli1 = await DockerCliConfig.getCliPath();
          command = '$dockerCli1 stop ${container.id}';
          break;
        case 'docker start':
          final dockerCli2 = await DockerCliConfig.getCliPath();
          command = '$dockerCli2 start ${container.id}';
          break;
        case 'docker restart':
          final dockerCli3 = await DockerCliConfig.getCliPath();
          command = '$dockerCli3 restart ${container.id}';
          break;
        case 'docker rm':
          final dockerCli4 = await DockerCliConfig.getCliPath();
          command = '$dockerCli4 rm ${container.id}';
          break;
        default:
          final dockerCliDefault = await DockerCliConfig.getCliPath();
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
                Text('${action.label}...'),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Execute the command
      final result = await sshService.executeCommand(command);
      
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
                  Text('${action.label} completed successfully'),
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
            await loadItems();
          }
        } else {
          // Command executed but no output
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${action.label} completed'),
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
                Expanded(child: Text('${action.label} failed: $e')),
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
          title: Text('Choose Shell - ${container.names}'),
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
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final executable = executableController.text.trim();
                if (executable.isNotEmpty) {
                  Navigator.of(context).pop();
                  _openInteractiveShell(container, executable);
                }
              },
              child: const Text('Connect'),
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
}

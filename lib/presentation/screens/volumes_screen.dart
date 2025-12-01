import 'package:flutter/material.dart';
import '../../domain/models/docker_volume.dart';
import '../../domain/repositories/docker_repository.dart';
import '../../data/repositories/docker_repository_impl.dart';
import '../../data/services/ssh_connection_service.dart';
import '../../data/services/docker_cli_path_service.dart';
import '../../domain/models/server.dart';
import '../widgets/docker_resource_actions.dart';
import '../widgets/search_bar_with_settings.dart';
import '../../data/services/analytics_service.dart';
import 'log_viewer_screen.dart';
import 'package:easy_localization/easy_localization.dart';

class VolumesScreen extends StatefulWidget {
  const VolumesScreen({super.key});

  @override
  State<VolumesScreen> createState() => _VolumesScreenState();
}

class _VolumesScreenState extends State<VolumesScreen> 
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final DockerRepository _dockerRepository = DockerRepositoryImpl();
  final SSHConnectionService _sshService = SSHConnectionService();
  final DockerCliPathService _dockerCliPathService = DockerCliPathService();
  final AnalyticsService _analytics = AnalyticsService();
  List<DockerVolume> _volumes = [];
  List<DockerVolume> _filteredVolumes = [];
  bool _isLoading = false;
  String? _error;
  bool _hasTriedLoading = false;
  Server? _lastKnownServer;
  String _searchQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startServerChangeDetection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startServerChangeDetection() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      
      final currentServer = _sshService.currentServer;
      
      if (currentServer != _lastKnownServer) {
        _lastKnownServer = currentServer;
        if (currentServer != null && 
            (!_hasTriedLoading && _sshService.isConnected)) {
          // Reset flag when server changes
          _hasTriedLoading = false; // Reset to allow reload
        }
      }
      
      _startServerChangeDetection();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Only load if we've tried loading before (user has seen this tab)
      if (_hasTriedLoading) {
        _loadVolumes();
      }
    }
  }

  Future<void> _loadVolumes() async {
    if (!_sshService.isConnected) {
      setState(() {
        _error = 'connection.no_connection';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _hasTriedLoading = true;
    });

    try {
      final volumes = await _dockerRepository.getVolumes();
      if (mounted) {
        setState(() {
          _volumes = volumes;
          _filteredVolumes = _filterVolumes(volumes, _searchQuery);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshVolumes() {
    _analytics.trackEvent('volumes.refresh');
    return _loadVolumes();
  }

  List<DockerVolume> _filterVolumes(List<DockerVolume> volumes, String query) {
    if (query.isEmpty) return volumes;
    
    final lowercaseQuery = query.toLowerCase();
    return volumes.where((volume) {
      return volume.volumeName.toLowerCase().contains(lowercaseQuery) ||
             volume.driver.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _filteredVolumes = _filterVolumes(_volumes, query);
    });
    _analytics.trackEvent('volumes.search', properties: {
      'queryLength': query.length,
    });
  }

  Future<void> _handleVolumeAction(DockerAction action, DockerVolume volume) async {
    try {
      String command;
      final dockerCli = await _dockerCliPathService.getDockerCliPath();
      await _analytics.trackEvent('volumes.action_selected', properties: {
        'action': action.command,
        'volume': volume.volumeName,
      });
      
      switch (action.command) {
        case 'docker volume inspect':
          command = '$dockerCli volume inspect ${volume.volumeName}';
          Navigator.of(context).push(
            MaterialPageRoute(
              settings: const RouteSettings(name: 'VolumeInspect'),
              builder: (context) => LogViewerScreen(
                title: 'volumes.inspect_title'.tr(args: [volume.volumeName]),
                command: command,
              ),
            ),
          );
          return;
          
        case 'docker volume rm':
          // Show confirmation dialog
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('volumes.delete_title'.tr()),
              content: Text('volumes.delete_confirmation'.tr(args: [volume.volumeName])),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('common.cancel'.tr()),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: Text('common.delete'.tr()),
                ),
              ],
            ),
          );

          if (confirmed == true) {
            command = '$dockerCli volume rm ${volume.volumeName}';
          } else {
            return;
          }
          break;
          
        default:
          command = '${action.command.replaceFirst('docker', dockerCli)} ${volume.volumeName}';
      }

      // Execute the command
      final result = await _sshService.executeCommand(command);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result?.isNotEmpty == true ? result! : 'operations.executed_successfully'.tr()),
            backgroundColor: Colors.green,
          ),
        );
        await _analytics.trackEvent('volumes.action_completed', properties: {
          'action': action.command,
          'volume': volume.volumeName,
          'status': 'success',
        });
        
        // Refresh the list after action
        _loadVolumes();
      }
    } catch (e) {
      await _analytics.trackException(
        'volumes.action_failed',
        e,
        properties: {
          'action': action.command,
          'volume': volume.volumeName,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('common.error'.tr() + ': $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshVolumes,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // Show loading on first load or when explicitly loading
    if (!_hasTriedLoading) {
      // Auto-load when tab becomes visible for the first time
      if (!_hasTriedLoading && mounted) {
        // Use a post-frame callback to avoid calling setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _sshService.isConnected) {
            _loadVolumes();
          }
        });
      }
      
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('volumes.loading'.tr()),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              'volumes.failed_to_load'.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _error!.startsWith('connection.') || _error!.startsWith('volumes.') ? _error!.tr() : _error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshVolumes,
              icon: const Icon(Icons.refresh),
              label: Text('common.retry'.tr()),
            ),
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
            Text('volumes.loading'.tr()),
          ],
        ),
      );
    }

    if (_volumes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.storage_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'volumes.no_volumes'.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('volumes.pull_to_refresh'.tr()),
          ],
        ),
      );
    }

    if (_filteredVolumes.isEmpty && _searchQuery.isNotEmpty) {
      return Column(
        children: [
          SearchBarWithSettings(
            hintText: 'common.search_volumes_hint'.tr(),
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
                    'volumes.no_search_results'.tr(),
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

    return Column(
      children: [
        SearchBarWithSettings(
          hintText: 'common.search_volumes_hint'.tr(),
          onSearchChanged: _onSearchChanged,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filteredVolumes.length,
            itemBuilder: (context, index) {
              final volume = _filteredVolumes[index];
              return _buildVolumeCard(volume);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeCard(DockerVolume volume) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.storage,
                        color: Colors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          volume.volumeName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                DockerResourceActions(
                  actions: [
                    DockerAction(
                      label: 'actions.inspect',
                      icon: Icons.info_outline,
                      command: 'docker volume inspect',
                    ),
                    DockerAction(
                      label: 'common.delete',
                      icon: Icons.delete_outline,
                      command: 'docker volume rm',
                      isDestructive: true,
                    ),
                  ],
                  onActionSelected: (action) => _handleVolumeAction(action, volume),
                  resourceName: volume.volumeName,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.settings,
                        size: 12,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        volume.driver,
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../domain/models/docker_image.dart';
import '../../domain/repositories/docker_repository.dart';
import '../../data/repositories/docker_repository_impl.dart';
import '../../data/services/ssh_connection_service.dart';
import '../../data/services/docker_cli_path_service.dart';
import '../../domain/models/server.dart';
import '../widgets/docker_resource_actions.dart';
import '../widgets/search_bar_with_settings.dart';
import 'log_viewer_screen.dart';
import 'package:easy_localization/easy_localization.dart';

class ImagesScreen extends StatefulWidget {
  const ImagesScreen({super.key});

  @override
  State<ImagesScreen> createState() => _ImagesScreenState();
}

class _ImagesScreenState extends State<ImagesScreen> 
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final DockerRepository _dockerRepository = DockerRepositoryImpl();
  final SSHConnectionService _sshService = SSHConnectionService();
  final DockerCliPathService _dockerCliPathService = DockerCliPathService();
  List<DockerImage> _images = [];
  List<DockerImage> _filteredImages = [];
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
        _loadImages();
      }
    }
  }

  Future<void> _loadImages() async {
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
      final images = await _dockerRepository.getImages();
      if (mounted) {
        setState(() {
          _images = images;
          _filteredImages = _filterImages(images, _searchQuery);
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

  List<DockerImage> _filterImages(List<DockerImage> images, String query) {
    if (query.isEmpty) return images;
    
    final lowercaseQuery = query.toLowerCase();
    return images.where((image) {
      return image.repository.toLowerCase().contains(lowercaseQuery) ||
             image.tag.toLowerCase().contains(lowercaseQuery) ||
             image.imageId.toLowerCase().contains(lowercaseQuery) ||
             image.size.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _filteredImages = _filterImages(_images, query);
    });
  }

  Future<void> _handleImageAction(DockerAction action, DockerImage image) async {
    try {
      String command;
      final dockerCli = await _dockerCliPathService.getDockerCliPath();
      
      switch (action.command) {
        case 'docker image inspect':
          command = '$dockerCli image inspect ${image.imageId}';
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => LogViewerScreen(
                title: 'images.inspect_title'.tr(args: ['${image.repository}:${image.tag}']),
                command: command,
              ),
            ),
          );
          return;
          
        case 'docker image rm':
          // Show confirmation dialog
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('images.delete_title'.tr()),
              content: Text('images.delete_confirmation'.tr(args: [image.repository, image.tag])),
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
            command = '$dockerCli image rm ${image.imageId}';
          } else {
            return;
          }
          break;
          
        default:
          command = '${action.command.replaceFirst('docker', dockerCli)} ${image.imageId}';
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
        
        // Refresh the list after action
        _loadImages();
      }
    } catch (e) {
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
        onRefresh: _loadImages,
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
            _loadImages();
          }
        });
      }
      
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('images.loading'.tr()),
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
              'images.failed_to_load'.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _error!.startsWith('connection.') || _error!.startsWith('images.') ? _error!.tr() : _error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadImages,
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
            Text('images.loading'.tr()),
          ],
        ),
      );
    }

    if (_filteredImages.isEmpty && _searchQuery.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.layers_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'images.no_images'.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('images.pull_to_refresh'.tr()),
          ],
        ),
      );
    }

    if (_filteredImages.isEmpty && _searchQuery.isNotEmpty) {
      return Column(
        children: [
          SearchBarWithSettings(
            hintText: 'common.search_images_hint'.tr(),
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
                    'images.no_search_results'.tr(),
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
          hintText: 'common.search_images_hint'.tr(),
          onSearchChanged: _onSearchChanged,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filteredImages.length,
            itemBuilder: (context, index) {
              final image = _filteredImages[index];
              return _buildImageCard(image);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildImageCard(DockerImage image) {
    final isBaseImage = ['alpine', 'ubuntu', 'debian', 'centos', 'fedora', 'postgres', 'redis', 'mysql', 'nginx', 'node', 'python', 'java'].any(
      (base) => image.repository.toLowerCase().contains(base)
    );
    final hasTag = image.tag != '<none>';
    
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
                        Icons.layers,
                        color: isBaseImage ? Colors.blue : Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              image.repository == '<none>' ? 'Unnamed Image' : image.repository,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (hasTag) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Tag: ${image.tag}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
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
                      command: 'docker image inspect',
                    ),
                    DockerAction(
                      label: 'common.delete',
                      icon: Icons.delete_outline,
                      command: 'docker image rm',
                      isDestructive: true,
                    ),
                  ],
                  onActionSelected: (action) => _handleImageAction(action, image),
                  resourceName: image.repository == '<none>' ? 'Unnamed Image' : '${image.repository}:${image.tag}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'ID: ${image.imageId.substring(0, 12)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.storage,
                        size: 12,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        image.size,
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
                        Icons.schedule,
                        size: 12,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        image.created,
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isBaseImage) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purple.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified,
                          size: 12,
                          color: Colors.purple,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Official',
                          style: TextStyle(
                            color: Colors.purple,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

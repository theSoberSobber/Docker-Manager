import 'package:flutter/material.dart';
import '../../domain/models/docker_volume.dart';
import '../widgets/docker_resource_actions.dart';
import '../widgets/search_bar_with_settings.dart';
import 'shell_screen.dart';
import 'base/base_resource_screen.dart';

class VolumesScreen extends BaseResourceScreen<DockerVolume> {
  const VolumesScreen({super.key});

  @override
  State<VolumesScreen> createState() => _VolumesScreenState();
}

class _VolumesScreenState extends BaseResourceScreenState<DockerVolume, VolumesScreen> {

  @override
  Future<List<DockerVolume>> fetchItems() async {
    return await dockerRepository.getVolumes();
  }

  @override
  List<DockerVolume> filterItems(List<DockerVolume> items, String query) {
    if (query.isEmpty) return items;
    
    final lowercaseQuery = query.toLowerCase();
    return items.where((volume) {
      return volume.volumeName.toLowerCase().contains(lowercaseQuery) ||
             volume.driver.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  @override
  String getResourceName() => 'volumes';

  @override
  IconData getEmptyIcon() => Icons.storage_outlined;

  @override
  Widget buildItemCard(DockerVolume volume) {
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
                      const Icon(
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
                      label: 'Inspect',
                      icon: Icons.info_outline,
                      command: 'docker volume inspect',
                    ),
                    DockerAction(
                      label: 'Delete',
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
                      const Icon(
                        Icons.settings,
                        size: 12,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        volume.driver,
                        style: const TextStyle(
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

  @override
  Widget buildErrorState(BuildContext context) {
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
            'Failed to load volumes',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            error!,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: loadItems,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
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
            Icons.storage_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No volumes found',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Pull down to refresh'),
        ],
      ),
    );
  }

  @override
  Widget buildNoSearchResultsState(BuildContext context) {
    return Column(
      children: [
        SearchBarWithSettings(
          hintText: 'Search volumes by name or driver...',
          onSearchChanged: onSearchChanged,
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
                  'No volumes match your search',
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
          hintText: 'Search volumes by name or driver...',
          onSearchChanged: onSearchChanged,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              final volume = filteredItems[index];
              return buildItemCard(volume);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _handleVolumeAction(DockerAction action, DockerVolume volume) async {
    try {
      switch (action.command) {
        case 'docker volume inspect':
          // Get inspect command from operations service
          final command = await operationsService.getInspectVolumeCommand(volume.volumeName);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ShellScreen(
                title: 'Inspect Volume - ${volume.volumeName}',
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
              title: const Text('Delete Volume'),
              content: Text('Are you sure you want to delete volume "${volume.volumeName}"?\n\nThis action cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );

          if (confirmed == true) {
            // Use operations service to remove volume
            await operationsService.removeVolume(volume.volumeName);
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Volume deleted successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              
              // Refresh the list after deletion
              loadItems();
            }
          }
          return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
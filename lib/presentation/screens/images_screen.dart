import 'package:flutter/material.dart';
import '../../domain/models/docker_image.dart';
import '../widgets/docker_resource_actions.dart';
import '../widgets/search_bar_with_settings.dart';
import 'shell_screen.dart';
import 'base/base_resource_screen.dart';

class ImagesScreen extends BaseResourceScreen<DockerImage> {
  const ImagesScreen({super.key});

  @override
  State<ImagesScreen> createState() => _ImagesScreenState();
}

class _ImagesScreenState extends BaseResourceScreenState<DockerImage, ImagesScreen> {

  @override
  Future<List<DockerImage>> fetchItems() async {
    return await dockerRepository.getImages();
  }

  @override
  List<DockerImage> filterItems(List<DockerImage> items, String query) {
    if (query.isEmpty) return items;
    
    final lowercaseQuery = query.toLowerCase();
    return items.where((image) {
      return image.repository.toLowerCase().contains(lowercaseQuery) ||
             image.tag.toLowerCase().contains(lowercaseQuery) ||
             image.imageId.toLowerCase().contains(lowercaseQuery) ||
             image.size.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  @override
  String getResourceName() => 'images';

  @override
  IconData getEmptyIcon() => Icons.image_outlined;

  @override
  Widget buildItemCard(DockerImage image) {
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
                      label: 'Inspect',
                      icon: Icons.info_outline,
                      command: 'docker image inspect',
                    ),
                    DockerAction(
                      label: 'Delete',
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
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purple.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.data_usage,
                        size: 12,
                        color: Colors.purple,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        image.size,
                        style: const TextStyle(
                          color: Colors.purple,
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
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 12,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        image.created,
                        style: const TextStyle(
                          color: Colors.grey,
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
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.verified,
                          size: 12,
                          color: Colors.blue,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Base',
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
              ],
            ),
          ],
        ),
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
            Icons.image_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No images found',
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
          hintText: 'Search images by repository, tag, ID, or size...',
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
                  'No images match your search',
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
          hintText: 'Search images by repository, tag, ID, or size...',
          onSearchChanged: onSearchChanged,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              final image = filteredItems[index];
              return buildItemCard(image);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _handleImageAction(DockerAction action, DockerImage image) async {
    try {
      switch (action.command) {
        case 'docker image inspect':
          // Get inspect command from operations service
          final command = await operationsService.getInspectImageCommand(image.imageId);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ShellScreen(
                title: 'Inspect Image - ${image.repository}:${image.tag}',
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
              title: const Text('Delete Image'),
              content: Text(
                'Are you sure you want to delete image "${image.repository}:${image.tag}"?\n\n'
                'Size: ${image.size}\n'
                'This action cannot be undone.'
              ),
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
            // Use operations service to remove image
            await operationsService.removeImage(image.imageId);
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Image deleted successfully'),
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

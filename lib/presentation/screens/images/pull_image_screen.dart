import 'package:flutter/material.dart';
import '../../../data/services/docker_registry_service.dart';
import '../../../data/services/ssh_connection_service.dart';

class PullImageScreen extends StatefulWidget {
  const PullImageScreen({super.key});

  @override
  State<PullImageScreen> createState() => _PullImageScreenState();
}

class _PullImageScreenState extends State<PullImageScreen> {
  final _registryService = DockerRegistryService();
  final _sshService = SSHConnectionService();
  final _searchController = TextEditingController();
  final _registryController = TextEditingController(text: 'hub.docker.com');

  List<ImageSearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    _registryController.dispose();
    super.dispose();
  }

  Future<void> _searchImages() async {
    if (_searchController.text.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _searchError = 'Please enter a search term';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isSearching = true;
        _hasSearched = true;
        _searchError = null;
        _searchResults = [];
      });
    }

    try {
      final results = await _registryService.searchImages(
        _searchController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = e.toString();
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _showTagSelectionDialog(ImageSearchResult image) async {
    // Show loading dialog while fetching tags
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading tags...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final tags = await _registryService.getImageTags(image.name);

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      if (tags.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tags found for this image')),
        );
        return;
      }

      // Show tag selection dialog
      final selectedTag = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select Tag for ${image.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: tags.length,
              itemBuilder: (context, index) {
                final tag = tags[index];
                return ListTile(
                  title: Text(tag),
                  trailing: tag == 'latest'
                      ? Chip(
                          label: const Text('Latest'),
                          backgroundColor: Colors.blue.withOpacity(0.2),
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(tag),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selectedTag != null) {
        _pullImage(image.name, selectedTag);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load tags: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pullImage(String imageName, String tag) async {
    final fullImageName = '$imageName:$tag';

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Pulling Image'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Pulling $fullImageName...'),
            const SizedBox(height: 8),
            const Text(
              'This may take a while depending on the image size.',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    try {
      final result =
          await _sshService.executeCommand('docker pull $fullImageName');

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      if (result != null && result.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully pulled $fullImageName'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Return to images screen
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to pull image'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pull Image'),
      ),
      body: Column(
        children: [
          // Registry URL and Search Input
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Registry URL
                TextFormField(
                  controller: _registryController,
                  decoration: const InputDecoration(
                    labelText: 'Registry URL',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.cloud),
                  ),
                  readOnly: true, // For now, only support docker.io
                ),
                const SizedBox(height: 12),
                // Search input
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search images',
                    hintText: 'e.g., ubuntu, nginx, postgres',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = [];
                                _hasSearched = false;
                                _searchError = null;
                              });
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _searchImages(),
                  onChanged: (value) {
                    setState(() {}); // To update clear button visibility
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSearching ? null : _searchImages,
                    icon: _isSearching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(_isSearching ? 'Searching...' : 'Search'),
                  ),
                ),
              ],
            ),
          ),

          // Search Results
          Expanded(
            child: _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            const Text(
              'Search Failed',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _searchError!,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _searchImages,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Search Docker Images',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Enter an image name to search Docker Hub',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No Results Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Try a different search term'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final image = _searchResults[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.image, size: 40),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    image.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (image.isOfficial)
                  Chip(
                    label: const Text('Official', style: TextStyle(fontSize: 10)),
                    backgroundColor: Colors.blue.withOpacity(0.2),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  image.description.isEmpty
                      ? 'No description available'
                      : image.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.star, size: 14, color: Colors.amber[700]),
                    const SizedBox(width: 4),
                    Text('${image.starCount}'),
                    if (image.isAutomated) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.settings, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      const Text('Automated'),
                    ],
                  ],
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => _showTagSelectionDialog(image),
              tooltip: 'Pull Image',
            ),
            onTap: () => _showTagSelectionDialog(image),
          ),
        );
      },
    );
  }
}

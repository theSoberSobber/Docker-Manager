import 'package:flutter/material.dart';
import '../../../data/services/docker_registry_service.dart';
import '../../../data/services/ssh_connection_service.dart';
import 'package:easy_localization/easy_localization.dart';

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
          _searchError = 'images.please_enter_search_term'.tr();
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
      builder: (context) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('images.loading_tags'.tr()),
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
          SnackBar(content: Text('images.no_tags_found'.tr())),
        );
        return;
      }

      // Show tag selection dialog
      final selectedTag = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('images.select_tag'.tr(args: [image.name])),
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
                          label: Text('images.tag_latest'.tr()),
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
              child: Text('common.cancel'.tr()),
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
          content: Text('images.failed_to_load_tags'.tr(args: [e.toString()])),
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
        title: Text('images.pulling'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('images.pulling_progress'.tr(args: [fullImageName])),
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
            content: Text('images.pull_success'.tr(args: [fullImageName])),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Return to images screen
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('images.pull_failed'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('common.error'.tr() + ': $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('images.pull'.tr()),
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
                  decoration: InputDecoration(
                    labelText: 'images.registry_url'.tr(),
                    hintText: 'images.registry_hint'.tr(),
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(Icons.cloud),
                  ),
                ),
                const SizedBox(height: 12),
                // Search input
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'images.search_images'.tr(),
                    hintText: 'images.search_hint'.tr(),
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
                    label: Text(_isSearching ? 'common.searching'.tr() : 'common.search'.tr()),
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
            Text(
              'images.search_failed'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              label: Text('common.retry'.tr()),
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
            Text(
              'images.search_docker_images'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'images.enter_image_name'.tr(),
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
            Text(
              'images.no_results_found'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('images.try_different_search'.tr()),
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
                    label: Text('images.official_label'.tr(), style: const TextStyle(fontSize: 10)),
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
                      Text('images.automated_label'.tr()),
                    ],
                  ],
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => _showTagSelectionDialog(image),
              tooltip: 'common.pull_image'.tr(),
            ),
            onTap: () => _showTagSelectionDialog(image),
          ),
        );
      },
    );
  }
}

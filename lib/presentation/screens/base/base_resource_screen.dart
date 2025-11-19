import 'package:flutter/material.dart';
import '../../../data/services/ssh_connection_service.dart';
import '../../../domain/models/server.dart';
import '../../../domain/repositories/docker_repository.dart';
import '../../../domain/services/docker_operations_service.dart';
import '../../../core/di/service_locator.dart';
import '../settings_screen.dart';

/// Base class for all Docker resource screens (containers, images, volumes, networks)
/// Provides common functionality: loading, error handling, search, server change detection
abstract class BaseResourceScreen<T> extends StatefulWidget {
  const BaseResourceScreen({super.key});
}

abstract class BaseResourceScreenState<T, W extends BaseResourceScreen<T>> 
    extends State<W> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  
  // Injected dependencies from service locator
  late final SSHConnectionService sshService = getIt<SSHConnectionService>();
  late final DockerRepository dockerRepository = getIt<DockerRepository>();
  late final DockerOperationsService operationsService = getIt<DockerOperationsService>();
  
  // State
  List<T> items = [];
  List<T> filteredItems = [];
  bool isLoading = false;
  String? error;
  bool hasTriedLoading = false;
  Server? lastKnownServer;
  String searchQuery = '';

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

  // Abstract methods to be implemented by subclasses
  Future<List<T>> fetchItems();
  List<T> filterItems(List<T> items, String query);
  String getResourceName(); // e.g., "containers", "images"
  IconData getEmptyIcon();
  Widget buildItemCard(T item);

  // Common loading logic
  Future<void> loadItems() async {
    if (!sshService.isConnected) {
      setState(() {
        error = 'No SSH connection available';
        isLoading = false;
      });
      return;
    }

    setState(() {
      isLoading = true;
      error = null;
      hasTriedLoading = true;
    });

    try {
      final fetchedItems = await fetchItems();
      if (mounted) {
        setState(() {
          items = fetchedItems;
          filteredItems = filterItems(fetchedItems, searchQuery);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          isLoading = false;
        });
      }
    }
  }

  // Common refresh logic
  Future<void> refreshItems() async {
    await loadItems();
  }

  // Common search logic
  void onSearchChanged(String query) {
    setState(() {
      searchQuery = query;
      filteredItems = filterItems(items, query);
    });
  }

  // Server change detection
  void _startServerChangeDetection() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      
      final currentServer = sshService.currentServer;
      
      if (currentServer != lastKnownServer) {
        lastKnownServer = currentServer;
        
        // If server changed and we're connected, trigger a reload
        if (currentServer != null && sshService.isConnected) {
          if (!hasTriedLoading) {
            // First time we detected a connection, load items
            loadItems();
          } else {
            // Server switched, reload items
            loadItems();
          }
        }
      }
      
      _startServerChangeDetection();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (hasTriedLoading) {
        loadItems();
      }
    }
  }

  // Common UI building
  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refreshItems,
        child: buildBody(context),
      ),
    );
  }

  Widget buildBody(BuildContext context) {
    // Initial loading check
    if (!hasTriedLoading) {
      // Check if we can load immediately
      if (mounted && sshService.isConnected) {
        // Connection is ready, trigger load on next frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !hasTriedLoading) {
            loadItems();
          }
        });
      }
      // If connection not ready, _startServerChangeDetection will trigger load when it becomes ready
      
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      );
    }

    // Error state
    if (error != null) {
      return buildErrorState(context);
    }

    // Loading state
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading ${getResourceName()}...'),
          ],
        ),
      );
    }

    // Empty state
    if (items.isEmpty) {
      return buildEmptyState(context);
    }

    // No search results
    if (filteredItems.isEmpty && searchQuery.isNotEmpty) {
      return buildNoSearchResultsState(context);
    }

    // Success - show list
    return buildItemList(context);
  }

  // Provide default error state with permission handling
  Widget buildErrorState(BuildContext context) {
    final isConnectionError = error!.contains('No SSH connection') || 
                              error!.contains('Connection timeout');
    final isPermissionError = error!.contains('Permission denied') || 
                              error!.contains('docker group');
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isConnectionError ? Icons.cloud_off : 
            isPermissionError ? Icons.lock_outline :
            Icons.error_outline,
            size: 64,
            color: isConnectionError || isPermissionError ? Colors.orange[400] : Colors.red[300],
          ),
          const SizedBox(height: 16),
          Text(
            isConnectionError ? 'Not Connected' : 
            isPermissionError ? 'Permission Issue' :
            'Error Loading ${getResourceName()}',
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

  Widget buildEmptyState(BuildContext context);
  Widget buildNoSearchResultsState(BuildContext context);
  Widget buildItemList(BuildContext context);
}

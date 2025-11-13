import 'package:flutter/material.dart';
import '../../../data/services/ssh_connection_service.dart';
import '../../../domain/models/server.dart';

/// Base class for all Docker resource screens (containers, images, volumes, networks)
/// Provides common functionality: loading, error handling, search, server change detection
abstract class BaseResourceScreen<T> extends StatefulWidget {
  const BaseResourceScreen({super.key});
}

abstract class BaseResourceScreenState<T, W extends BaseResourceScreen<T>> 
    extends State<W> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  
  final SSHConnectionService sshService = SSHConnectionService();
  
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
        if (currentServer != null && 
            (!hasTriedLoading && sshService.isConnected)) {
          hasTriedLoading = false; // Reset to allow reload
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
      if (!hasTriedLoading && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && sshService.isConnected) {
            loadItems();
          }
        });
      }
      
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

  Widget buildErrorState(BuildContext context);
  Widget buildEmptyState(BuildContext context);
  Widget buildNoSearchResultsState(BuildContext context);
  Widget buildItemList(BuildContext context);
}

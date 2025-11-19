import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';
import '../../../data/services/ssh_connection_service.dart';
import '../../../domain/models/server.dart';
import '../../../domain/repositories/docker_repository.dart';
import '../../../domain/repositories/server_repository.dart';
import '../../../domain/services/docker_operations_service.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/error_state.dart';

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
  late final ServerRepository serverRepository = getIt<ServerRepository>();
  
  // State
  List<T> items = [];
  List<T> filteredItems = [];
  bool isLoading = false;
  ErrorState? errorState;
  bool hasTriedConnecting = false;  // Track if we've attempted connection to prevent infinite retry loops
  bool hasTriedLoading = false;
  Server? lastKnownServer;
  String searchQuery = '';

  @override
  bool get wantKeepAlive => false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // _startServerChangeDetection();
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

  // Helper method to load items from Docker
  // Returns ErrorState if failed, null if successful
  // Does NOT modify isLoading state - caller handles that
  Future<ErrorState?> _loadItems() async {
    if (kDebugMode) {
      print('[CHECK 2] Loading ${getResourceName()}...');
    }
    
    try {
      final fetchedItems = await fetchItems();
      
      if (kDebugMode) {
        print('[CHECK 2] Loaded ${fetchedItems.length} ${getResourceName()}');
      }
      
      if (mounted) {
        items = fetchedItems;
        filteredItems = filterItems(fetchedItems, searchQuery);
        hasTriedLoading = true;
      }
      
      return null; // Success
    } catch (e) {
      if (kDebugMode) {
        print('[CHECK 2] Error loading ${getResourceName()}: $e');
      }
      
      final errorMessage = e.toString();
      
      // Check if it's a connection error
      if (_isConnectionError(errorMessage)) {
        if (kDebugMode) {
          print('[CHECK 2.1] Connection error detected - forcing reconnection');
        }
        
        // Force reconnection by resetting flag AND keeping isLoading true
        // Caller will call setState which triggers CHECK 1 on next build
        if (mounted) {
          hasTriedConnecting = false;
          // Return special marker so caller knows to keep loading
          return ErrorState.connection(
            message: '__RECONNECT__', // Special marker
            onRetry: null,
          );
        }
      }
      
      // Check if it's a permission error
      if (_isPermissionError(errorMessage)) {
        if (kDebugMode) {
          print('[CHECK 2.2] Permission error detected');
        }
        
        if (mounted) {
          hasTriedLoading = true; // Mark as tried to prevent infinite loop
        }
        
        return ErrorState.permission(
          message: errorMessage,
          onRetry: () {
            // For permission errors, just retry loading (don't reconnect)
            setState(() {
              errorState = null;
              isLoading = true;
            });
            
            // Reset flag and load again
            hasTriedLoading = false;
            _loadItems().then((error) {
              if (mounted) {
                // Check if it's a reconnect signal
                if (error?.message == '__RECONNECT__') {
                  setState(() {
                    isLoading = false;
                  });
                } else {
                  setState(() {
                    isLoading = false;
                    errorState = error;
                  });
                }
              }
            });
          },
        );
      }
      
      // Other error - return error state
      if (mounted) {
        hasTriedLoading = true; // Mark as tried to prevent infinite loop
      }
      
      return ErrorState.general(
        message: errorMessage,
        onRetry: () {
          // For general errors, retry loading directly
          setState(() {
            errorState = null;
            isLoading = true;
          });
          
          hasTriedLoading = false;
          _loadItems().then((error) {
            if (mounted) {
              // Check if it's a reconnect signal
              if (error?.message == '__RECONNECT__') {
                setState(() {
                  isLoading = false;
                });
              } else {
                setState(() {
                  isLoading = false;
                  errorState = error;
                });
              }
            }
          });
        },
      );
    }
  }
  
  // Helper to detect connection errors
  bool _isConnectionError(String error) {
    final lowerError = error.toLowerCase();
    return lowerError.contains('connection') ||
           lowerError.contains('ssh') ||
           lowerError.contains('timeout') ||
           lowerError.contains('refused') ||
           lowerError.contains('closed');
  }

  // Helper to detect permission errors
  bool _isPermissionError(String error) {
    final lowerError = error.toLowerCase();
    return lowerError.contains('permission denied') ||
           lowerError.contains('docker group') ||
           lowerError.contains('dial unix') ||
           lowerError.contains('cannot connect to docker daemon') ||
           lowerError.contains('access denied');
  }

  // Common loading logic (deprecated - use _loadItems instead)
  Future<void> loadItems() async {
    // COMMENTED OUT ALL LOGIC
    /*
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
    */
  }

  // Common refresh logic
  Future<void> refreshItems() async {
    // await loadItems();
  }

  // Common search logic
  void onSearchChanged(String query) {
    setState(() {
      searchQuery = query;
      filteredItems = filterItems(items, query);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // COMMENTED OUT
    /*
    if (state == AppLifecycleState.resumed) {
      if (hasTriedLoading) {
        loadItems();
      }
    }
    */
  }

  // Common UI building
  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // Debug toast with random number
    if (kDebugMode) {
      final randomNum = Random().nextInt(10000);
      final serverName = sshService.currentServer?.name ?? 'NULL';
      final isConnected = sshService.isConnected;
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('[DEBUG] ${getResourceName()} - Random: $randomNum | Server: $serverName | Connected: $isConnected | Loading: $isLoading'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    }
    
    // CHECK 1: Server changed OR not connected - need to connect/load
    final needsConnection = sshService.didServerChange || 
                           (!sshService.isConnected && !hasTriedConnecting);
    
    // OR: Already connected but haven't tried loading yet (new screen instance)
    final needsLoad = sshService.isConnected && !hasTriedLoading;
    
    if ((needsConnection || needsLoad) && !isLoading) {
      if (kDebugMode) {
        print('[CHECK 1.1] needsConnection: $needsConnection, needsLoad: $needsLoad');
      }
      
      isLoading = true;
      errorState = null;
      
      if (needsConnection) {
        // Reset flags
        sshService.didServerChange = false;
        hasTriedConnecting = true;
        
        // Connect first, then load
        _connectToServer().then((error) {
          if (mounted) {
            if (error != null) {
              // Connection failed - stop loading and show error
              setState(() {
                isLoading = false;
                errorState = error;
              });
            } else {
              // Connection succeeded - load data
              if (kDebugMode) {
                print('[CHECK 1.4] Connection succeeded! Loading data...');
              }
              
              _loadItems().then((error) {
                if (mounted) {
                  // Check if it's a reconnect signal
                  if (error?.message == '__RECONNECT__') {
                    // Reset loading to allow CHECK 1 to run again
                    setState(() {
                      isLoading = false;
                    });
                  } else {
                    setState(() {
                      isLoading = false;
                      errorState = error;
                    });
                  }
                }
              });
            }
          }
        });
      } else {
        // Already connected - just load data
        if (kDebugMode) {
          print('[CHECK 1.5] Already connected, loading data...');
        }
        
        _loadItems().then((error) {
          if (mounted) {
            // Check if it's a reconnect signal
            if (error?.message == '__RECONNECT__') {
              // Reset loading to allow CHECK 1 to run again
              setState(() {
                isLoading = false;
              });
            } else {
              setState(() {
                isLoading = false;
                errorState = error;
              });
            }
          }
        });
      }
    }
    
    // Show loading screen
    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('[CHECK 1] Connecting to server...'),
            ],
          ),
        ),
      );
    }
    
    // Show error screen
    if (errorState != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                errorState!.icon,
                size: errorState!.iconSize,
                color: errorState!.iconColor,
              ),
              const SizedBox(height: 16),
              Text(
                errorState!.headline,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  errorState!.message,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              if (errorState!.onRetry != null)
                ElevatedButton(
                  onPressed: errorState!.onRetry,
                  child: Text(errorState!.retryButtonText),
                ),
            ],
          ),
        ),
      );
    }
    
    // Success - show the actual content
    return buildItemList(context);
  }
  
  // Helper method to connect to server
  // Returns ErrorState if failed, null if successful
  // Does NOT modify isLoading state - caller handles that
  Future<ErrorState?> _connectToServer() async {
    if (kDebugMode) {
      print('[CHECK 1.2] Starting connection - currentServer: ${sshService.currentServer?.name}');
    }
    
    // If no current server, try to load last used server from storage
    if (sshService.currentServer == null) {
      if (kDebugMode) {
        print('[CHECK 1.2.1] No current server, loading from storage...');
      }
      
      final lastUsedServer = await serverRepository.getLastUsedServer();
      
      if (lastUsedServer == null) {
        // No server in storage either - user needs to add one
        return ErrorState.empty(
          message: 'No server configured. Please add a server from the settings menu (top-right icon).',
          onRetry: null, // No retry for this case
        );
      }
      
      // Set the loaded server as current
      sshService.currentServer = lastUsedServer;
      
      if (kDebugMode) {
        print('[CHECK 1.2.2] Loaded server from storage: ${lastUsedServer.name}');
      }
    }
    
    // Now we have a server, try to connect
    final result = await sshService.connect(sshService.currentServer!);
    
    if (kDebugMode) {
      print('[CHECK 1.3] Connection completed - ${result.success ? "SUCCESS" : "FAILED: ${result.error}"}');
    }
    
    if (!result.success) {
      return ErrorState.connection(
        message: result.error ?? 'Unknown connection error',
        onRetry: () {
          setState(() {
            errorState = null;
            hasTriedConnecting = false;  // Reset flag to allow retry
          });
        },
      );
    }
    
    return null; // Success
  }

  Widget buildBody(BuildContext context) {
    // COMMENTED OUT - NOT USED
    return Container();
    /*
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
    */
  }

  // Provide default error state with permission handling
  Widget buildErrorState(BuildContext context) {
    // COMMENTED OUT - NOT USED (we use errorState object now)
    return Container();
    /*
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
    */
  }

  Widget buildEmptyState(BuildContext context);
  Widget buildNoSearchResultsState(BuildContext context);
  Widget buildItemList(BuildContext context);
}

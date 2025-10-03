import 'package:flutter/material.dart';
import '../../domain/models/docker_container.dart';
import '../../domain/repositories/docker_repository.dart';
import '../../data/repositories/docker_repository_impl.dart';
import '../../data/services/ssh_connection_service.dart';
import '../../domain/models/server.dart';

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends State<ContainersScreen> 
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final DockerRepository _dockerRepository = DockerRepositoryImpl();
  final SSHConnectionService _sshService = SSHConnectionService();
  List<DockerContainer> _containers = [];
  bool _isLoading = false;
  String? _error;
  bool _hasTriedLoading = false;
  Server? _lastKnownServer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start a periodic check to detect server changes
    _startServerChangeDetection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Start a timer to detect when server changes
  void _startServerChangeDetection() {
    // Check every second if the server changed
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      
      final currentServer = _sshService.currentServer;
      
      // If server changed or connection status changed, reload
      if (_lastKnownServer?.id != currentServer?.id || 
          (!_hasTriedLoading && _sshService.isConnected)) {
        _lastKnownServer = currentServer;
        _hasTriedLoading = false; // Reset to allow reload
        _checkConnectionAndLoad();
      }
      
      // Continue checking
      _startServerChangeDetection();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This gets called when the tab becomes visible
    if (!_hasTriedLoading && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkConnectionAndLoad();
        }
      });
    }
  }

  /// Check if SSH is connected before loading
  Future<void> _checkConnectionAndLoad() async {
    if (!mounted) return;
    
    setState(() {
      _hasTriedLoading = true;
      _isLoading = true;
      _error = null;
    });

    if (_sshService.isConnected) {
      // Connection is ready, load immediately
      await _loadContainers();
    } else if (_sshService.isConnecting) {
      // Connection is in progress, wait and try again
      // Wait up to 10 seconds for connection
      bool connectionSucceeded = false;
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        
        if (_sshService.isConnected) {
          connectionSucceeded = true;
          await _loadContainers();
          return;
        }
        if (_sshService.status == ConnectionStatus.failed || 
            _sshService.status == ConnectionStatus.disconnected) {
          break;
        }
      }
      
      if (!connectionSucceeded && mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Connection timeout. Please try again or check your server connection.';
        });
      }
    } else {
      // No connection
      setState(() {
        _isLoading = false;
        _error = 'No SSH connection available. Please connect to a server first.';
      });
    }
  }

  Future<void> _loadContainers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final containers = await _dockerRepository.getContainers();
      setState(() {
        _containers = containers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshContainers() async {
    _hasTriedLoading = false; // Reset the flag to allow reload
    await _checkConnectionAndLoad();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    if (!_hasTriedLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing...'),
          ],
        ),
      );
    }
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading containers...'),
          ],
        ),
      );
    }

    if (_error != null) {
      final isConnectionError = _error!.contains('No SSH connection') || 
                                _error!.contains('Connection timeout') ||
                                _error!.contains('Failed to get containers: Exception: No SSH connection');
      
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isConnectionError ? Icons.cloud_off : Icons.error_outline,
              size: 64,
              color: isConnectionError ? Colors.orange[400] : Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              isConnectionError ? 'No Server Connection' : 'Failed to load containers',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              isConnectionError 
                ? 'Please connect to a server to view containers'
                : _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isConnectionError) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      // The servers button is in the app bar, so we can't easily navigate to it
                      // Instead, show a helpful message
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Tap the server icon in the top-right to connect to a server'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    },
                    icon: const Icon(Icons.dns),
                    label: const Text('Connect to Server'),
                  ),
                  const SizedBox(width: 12),
                ],
                ElevatedButton.icon(
                  onPressed: _refreshContainers,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_containers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
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
              'No Docker containers are available on this server.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshContainers,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshContainers,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _containers.length,
        itemBuilder: (context, index) {
          final container = _containers[index];
          return _buildContainerCard(container);
        },
      ),
    );
  }

  Widget _buildContainerCard(DockerContainer container) {
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
            // Header with name and status
            Row(
              children: [
                Expanded(
                  child: Text(
                    container.names,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
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
}
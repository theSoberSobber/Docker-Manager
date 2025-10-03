import 'package:flutter/material.dart';
import '../../domain/models/server.dart';
import '../../domain/repositories/server_repository.dart';
import '../../data/repositories/server_repository_impl.dart';
import '../../data/services/ssh_connection_service.dart';
import 'server_list_screen.dart';
import 'containers_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ServerRepository _serverRepository = ServerRepositoryImpl();
  final SSHConnectionService _sshService = SSHConnectionService();
  int _currentIndex = 0;
  Server? _currentServer;
  bool _isLoading = true;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLastUsedServer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Disconnect SSH when app is disposed
    _sshService.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground, reload last used server
      _loadLastUsedServer();
    }
  }

  Future<void> _loadLastUsedServer() async {
    try {
      setState(() => _isLoading = true);
      final lastUsedServer = await _serverRepository.getLastUsedServer();
      setState(() {
        _currentServer = lastUsedServer;
        _isLoading = false;
      });

      // Auto-connect to last used server if available (silently)
      if (lastUsedServer != null) {
        _connectToServerSilently(lastUsedServer);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load server: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _connectToServerSilently(Server server) async {
    try {
      setState(() => _connectionStatus = ConnectionStatus.connecting);
      
      final result = await _sshService.switchToServer(server);
      
      setState(() => _connectionStatus = result.status);
      
      // Only show message if connection failed on startup
      if (mounted && !result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Could not connect to ${server.name}'),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _connectionStatus = ConnectionStatus.failed);
      // Silent failure on startup - user can see status in UI
    }
  }

  Future<void> _connectToServer(Server server) async {
    try {
      setState(() => _connectionStatus = ConnectionStatus.connecting);
      
      // Show connecting message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text('Connecting to ${server.name}...'),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
      
      final result = await _sshService.switchToServer(server);
      
      setState(() => _connectionStatus = result.status);
      
      // Clear any existing snackbars before showing result
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Text('Connected to ${server.name}'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Failed to connect: ${result.error ?? 'Unknown error'}'),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _connectionStatus = ConnectionStatus.failed);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Connection error: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _selectServer(Server server) async {
    try {
      // 1. Save server selection first
      await _serverRepository.setLastUsedServerId(server.id);
      setState(() {
        _currentServer = server;
      });
      
      // 2. Show selection message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Selected server: ${server.name}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      
      // 3. Small delay to show selection message, then connect
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 4. Connect to server (this will show connecting/connected/error messages)
      await _connectToServer(server);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select server: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildTabContent(String tabName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            tabName,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          if (_isLoading)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading server...'),
              ],
            )
          else if (_currentServer != null)
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      _currentServer!.name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    
                    // Connection Status Indicator
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getStatusColor().withOpacity(0.1),
                        border: Border.all(color: _getStatusColor()),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _getStatusIcon(),
                          const SizedBox(width: 8),
                          Text(
                            _getStatusText(),
                            style: TextStyle(
                              color: _getStatusColor(),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_connectionStatus == ConnectionStatus.connecting)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Server Details
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.computer, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '${_currentServer!.ip}:${_currentServer!.port}',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.person, size: 20),
                              const SizedBox(width: 8),
                              Text(_currentServer!.username),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _currentServer!.password != null 
                                    ? Icons.key 
                                    : Icons.vpn_key,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(_currentServer!.password != null 
                                  ? 'Password Auth' 
                                  : 'Key Auth'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Retry button for failed connections
                    if (_connectionStatus == ConnectionStatus.failed) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _connectToServer(_currentServer!),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry Connection'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      size: 48,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No Server Selected',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please select a server from the servers list to continue.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ServerListScreen(
                              onServerSelected: _selectServer,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.dns),
                      label: const Text('Select Server'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connecting:
        return Colors.orange;
      case ConnectionStatus.failed:
        return Colors.red;
      case ConnectionStatus.disconnected:
        return Colors.grey;
    }
  }

  Icon _getStatusIcon() {
    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        return const Icon(Icons.check_circle, color: Colors.green);
      case ConnectionStatus.connecting:
        return const Icon(Icons.sync, color: Colors.orange);
      case ConnectionStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case ConnectionStatus.disconnected:
        return const Icon(Icons.cloud_off, color: Colors.grey);
    }
  }

  String _getStatusText() {
    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.failed:
        return 'Connection Failed';
      case ConnectionStatus.disconnected:
        return 'Disconnected';
    }
  }

  List<Widget> get _pages => [
    const ContainersScreen(),
    _buildTabContent('Images'),
    _buildTabContent('Volumes'),
    _buildTabContent('Networks'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Docker Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ServerListScreen(
                    onServerSelected: _selectServer,
                  ),
                ),
              );
              // Reload servers when returning from server list
              if (result == true) {
                _loadLastUsedServer();
              }
            },
            tooltip: 'Servers',
          ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.view_list),
            label: 'Containers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.image),
            label: 'Images',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storage),
            label: 'Volumes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.hub),
            label: 'Networks',
          ),
        ],
      ),
    );
  }
}
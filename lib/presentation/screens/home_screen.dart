import 'package:flutter/material.dart';
import '../../domain/models/server.dart';
import '../../domain/repositories/server_repository.dart';
import '../../data/repositories/server_repository_impl.dart';
import '../../data/services/ssh_connection_service.dart';
import '../widgets/theme_manager.dart';
import 'server_list_screen.dart';
import 'containers_screen.dart';
import 'images_screen.dart';
import 'volumes_screen.dart';
import 'networks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ServerRepository _serverRepository = ServerRepositoryImpl();
  final SSHConnectionService _sshService = SSHConnectionService();
  int _currentIndex = 0;

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
      final lastUsedServer = await _serverRepository.getLastUsedServer();

      // Auto-connect to last used server if available (silently)
      if (lastUsedServer != null) {
        _connectToServerSilently(lastUsedServer);
      }
    } catch (e) {
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
      final result = await _sshService.switchToServer(server);
      
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
      // Silent failure on startup
    }
  }

  Future<void> _selectServer(Server server) async {
    try {
      // 1. Save server selection first
      await _serverRepository.setLastUsedServerId(server.id);
      
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
      await _connectToServerSilently(server);
      
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

  List<Widget> get _pages => [
    const ContainersScreen(),
    const ImagesScreen(),
    const VolumesScreen(),
    const NetworksScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Docker Manager'),
        actions: [
          IconButton(
            icon: Icon(ThemeManager().themeIcon),
            onPressed: () {
              ThemeManager().toggleTheme();
            },
            tooltip: ThemeManager().themeLabel,
          ),
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
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Containers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.layers_outlined),
            label: 'Images',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dns_outlined),
            label: 'Volumes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_tree_outlined),
            label: 'Networks',
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../../domain/models/server.dart';
import '../../domain/repositories/server_repository.dart';
import '../../data/repositories/server_repository_impl.dart';
import '../../data/services/ssh_connection_service.dart';
import '../widgets/theme_manager.dart';
import '../widgets/system_info_dialog.dart';
import '../widgets/speed_dial_fab.dart';
import 'server_list_screen.dart';
import 'shell_screen.dart';
import 'containers_screen.dart';
import 'containers/create_container_screen.dart';
import 'images_screen.dart';
import 'images/pull_image_screen.dart';
import 'images/build_image_screen.dart';
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

  Widget? _buildFloatingActionButton() {
    switch (_currentIndex) {
      case 0: // Containers tab
        return FloatingActionButton(
          onPressed: () async {
            if (!_sshService.isConnected) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please connect to a server first'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CreateContainerScreen(),
              ),
            );
            // If container was created, the result will be true
            if (result == true) {
              // Trigger refresh on the containers screen if needed
              setState(() {});
            }
          },
          tooltip: 'Create Container',
          child: const Icon(Icons.add),
        );
      case 1: // Images tab - Speed Dial FAB
        return SpeedDialFAB(
          mainIcon: Icons.add,
          mainTooltip: 'Image Actions',
          actions: [
            SpeedDialAction(
              icon: Icons.search,
              label: 'Pull Image',
              tooltip: 'Search and pull image from registry',
              onPressed: () async {
                if (!_sshService.isConnected) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please connect to a server first'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PullImageScreen(),
                  ),
                );
                if (result == true) {
                  setState(() {}); // Refresh images list
                }
              },
            ),
            SpeedDialAction(
              icon: Icons.build,
              label: 'Build Image',
              tooltip: 'Build image from Dockerfile',
              onPressed: () async {
                if (!_sshService.isConnected) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please connect to a server first'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BuildImageScreen(),
                  ),
                );
                if (result == true) {
                  setState(() {}); // Refresh images list
                }
              },
            ),
          ],
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Docker Manager'),
        actions: [
          // System Info button
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              if (_sshService.isConnected) {
                showDialog(
                  context: context,
                  builder: (context) => const SystemInfoDialog(),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please connect to a server first'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            tooltip: 'System Information',
          ),
          // Host Shell button
          IconButton(
            icon: const Icon(Icons.terminal),
            onPressed: () {
              if (_sshService.isConnected) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ShellScreen(
                      title: 'Host Shell',
                      isInteractive: true,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please connect to a server first'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            tooltip: 'Host Shell',
          ),
          // Theme toggle button
          IconButton(
            icon: Icon(ThemeManager().themeIcon),
            onPressed: () {
              ThemeManager().toggleTheme();
            },
            tooltip: ThemeManager().themeLabel,
          ),
          // Server selection button
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
      floatingActionButton: _buildFloatingActionButton(),
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
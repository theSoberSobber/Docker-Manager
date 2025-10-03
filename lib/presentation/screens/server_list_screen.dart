import 'package:flutter/material.dart';
import '../../domain/models/server.dart';
import '../../domain/repositories/server_repository.dart';
import '../../data/repositories/server_repository_impl.dart';
import '../widgets/add_server_dialog.dart';

class ServerListScreen extends StatefulWidget {
  final Function(Server)? onServerSelected;
  
  const ServerListScreen({
    super.key, 
    this.onServerSelected,
  });

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  final ServerRepository _serverRepository = ServerRepositoryImpl();
  List<Server> _servers = [];
  bool _isLoading = true;
  String? _currentServerId;

  @override
  void initState() {
    super.initState();
    _loadServers();
    _loadCurrentServerId();
  }

  Future<void> _loadCurrentServerId() async {
    try {
      final currentServerId = await _serverRepository.getLastUsedServerId();
      setState(() {
        _currentServerId = currentServerId;
      });
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _loadServers() async {
    try {
      setState(() => _isLoading = true);
      final servers = await _serverRepository.getServers();
      setState(() {
        _servers = servers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load servers: $e')),
        );
      }
    }
  }

  Future<void> _addServer(Server server) async {
    try {
      await _serverRepository.saveServer(server);
      await _loadServers(); // Refresh the list
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add server: $e')),
        );
      }
    }
  }

  Future<void> _deleteServer(String serverId) async {
    try {
      await _serverRepository.deleteServer(serverId);
      await _loadServers(); // Refresh the list
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete server: $e')),
        );
      }
    }
  }

  Future<void> _selectServer(Server server) async {
    if (widget.onServerSelected != null) {
      widget.onServerSelected!(server);
      Navigator.of(context).pop(true); // Return true to indicate server was selected
    }
  }

  void _showAddServerDialog() {
    showDialog(
      context: context,
      builder: (context) => AddServerDialog(onAdd: _addServer),
    );
  }

  void _showDeleteConfirmation(Server server) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Server'),
        content: Text('Are you sure you want to delete ${server.ip}:${server.port}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteServer(server.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Docker Servers'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _servers.isEmpty
              ? const Center(
                  child: Text(
                    'No servers added yet.\nTap + to add your first server.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadServers,
                  child: ListView.builder(
                    itemCount: _servers.length,
                    itemBuilder: (context, index) {
                      final server = _servers[index];
                      final isSelected = server.id == _currentServerId;
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        elevation: isSelected ? 4 : 1,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected 
                                ? Border.all(
                                    color: Theme.of(context).primaryColor,
                                    width: 2,
                                  )
                                : null,
                            color: isSelected 
                                ? Theme.of(context).primaryColor.withOpacity(0.05)
                                : null,
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Icon(
                              Icons.computer,
                              color: isSelected 
                                  ? Theme.of(context).primaryColor 
                                  : null,
                            ),
                            title: Text(
                              server.name,
                              style: TextStyle(
                                fontWeight: isSelected 
                                    ? FontWeight.bold 
                                    : FontWeight.normal,
                                color: isSelected 
                                    ? Theme.of(context).primaryColor
                                    : null,
                              ),
                            ),
                            subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${server.ip}:${server.port}'),
                              Row(
                                children: [
                                  Text('User: ${server.username}'),
                                  if (isSelected) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6, 
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).primaryColor,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'CURRENT',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                server.password != null ? Icons.key : Icons.vpn_key,
                                size: 16,
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _showDeleteConfirmation(server),
                              ),
                            ],
                          ),
                          onTap: widget.onServerSelected != null && !isSelected
                              ? () => _selectServer(server)
                              : null,
                        ),
                      ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddServerDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
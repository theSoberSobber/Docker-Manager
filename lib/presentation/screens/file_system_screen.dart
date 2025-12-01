import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';

import '../../data/services/sftp_service.dart';
import '../../data/services/ssh_connection_service.dart';
import '../../domain/models/remote_file_entry.dart';
import 'server_list_screen.dart';
import 'file_editor_screen.dart';

class FileSystemScreen extends StatefulWidget {
  final String initialPath;
  final String? title;
  final ValueChanged<RemoteFileEntry>? onItemSelected;

  const FileSystemScreen({
    super.key,
    this.initialPath = '/',
    this.title,
    this.onItemSelected,
  });

  @override
  State<FileSystemScreen> createState() => _FileSystemScreenState();
}

class _FileSystemScreenState extends State<FileSystemScreen> {
  final SSHConnectionService _sshService = SSHConnectionService();
  final SftpService _sftpService = SftpService();

  late String _currentPath;
  List<RemoteFileEntry> _entries = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _load();
  }

  @override
  void dispose() {
    _sftpService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_sshService.isConnected) {
      setState(() {
        _isLoading = false;
        _error = 'file_manager.not_connected'.tr();
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await _sftpService.listDirectory(_currentPath);
      if (!mounted) return;
      setState(() {
        _entries = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'file_manager.load_error'.tr(args: [e.toString()]);
        _isLoading = false;
      });
    }
  }

  void _openEntry(RemoteFileEntry entry) {
    if (entry.isDirectory) {
      setState(() {
        _currentPath = entry.path;
      });
      _load();
    } else if (widget.onItemSelected != null) {
      widget.onItemSelected!(entry);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => FileEditorScreen(path: entry.path),
        ),
      ).then((_) => _load());
    }
  }

  void _goUp() {
    if (_currentPath == '/' || _currentPath.trim().isEmpty) return;
    final trimmed = _currentPath.endsWith('/') && _currentPath != '/'
        ? _currentPath.substring(0, _currentPath.length - 1)
        : _currentPath;
    final lastSlash = trimmed.lastIndexOf('/');
    final parent = lastSlash <= 0 ? '/' : trimmed.substring(0, lastSlash);
    setState(() {
      _currentPath = parent;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'file_manager.title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'common.refresh'.tr(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.red),
            ),
            const SizedBox(height: 12),
            if (!_sshService.isConnected)
              FilledButton(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ServerListScreen(
                        onServerSelected: (_) {},
                      ),
                    ),
                  );
                  if (result == true) {
                    _load();
                  }
                },
                child: Text('common.servers'.tr()),
              )
            else
              FilledButton(
                onPressed: _load,
                child: Text('common.retry'.tr()),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildPathRow()),
          if (_currentPath != '/')
            SliverToBoxAdapter(
              child: ListTile(
                leading: const Icon(Icons.arrow_upward),
                title: Text('file_manager.go_up'.tr()),
                onTap: _goUp,
              ),
            ),
          if (_entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('file_manager.empty'.tr())),
            )
          else
            SliverList.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return ListTile(
                  leading: Icon(
                    entry.isDirectory ? Icons.folder : Icons.insert_drive_file,
                    color: entry.isDirectory
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(entry.name),
                  subtitle: Text(_entrySubtitle(entry)),
                  onTap: () => _openEntry(entry),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPathRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      child: Row(
        children: [
          const Icon(Icons.folder_open, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                _currentPath,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _entrySubtitle(RemoteFileEntry entry) {
    final parts = <String>[];
    if (entry.modified != null) {
      parts.add(
        DateFormat.yMMMd(context.locale.toString())
            .add_jm()
            .format(entry.modified!.toLocal()),
      );
    }
    if (!entry.isDirectory && entry.size != null) {
      parts.add(_readableSize(entry.size!));
    }
    return parts.isEmpty ? '' : parts.join(' • ');
  }

  String _readableSize(int size) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = size.toDouble();
    int unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unitIndex]}';
  }
}

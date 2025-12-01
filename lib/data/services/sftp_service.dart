import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

import '../../domain/models/remote_file_entry.dart';
import 'ssh_connection_service.dart';

class SftpService {
  final SSHConnectionService _sshService = SSHConnectionService();
  SftpClient? _sftpClient;

  Future<SftpClient> _client() async {
    if (!_sshService.isConnected || _sshService.currentConnection == null) {
      throw Exception('No active SSH connection');
    }

    _sftpClient ??= await _sshService.currentConnection!.sftp();
    return _sftpClient!;
  }

  Future<List<RemoteFileEntry>> listDirectory(String path) async {
    final client = await _client();
    final entries = await client.listdir(path);

    final mapped = entries
        .where((e) => e.filename != '.' && e.filename != '..')
        .map((entry) {
          final attr = entry.attr;
          final isDirectory = attr.isDirectory;

          return RemoteFileEntry(
            name: entry.filename,
            path: _joinPath(path, entry.filename),
            isDirectory: isDirectory,
            size: attr.size?.toInt(),
            modified: attr.modifyTime != null
                ? DateTime.fromMillisecondsSinceEpoch(attr.modifyTime! * 1000)
                : null,
          );
        })
        .toList();

    mapped.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return mapped;
  }

  String _joinPath(String base, String name) {
    if (base.endsWith('/')) {
      return '$base$name';
    }
    return '$base/$name';
  }

  Future<bool> exists(String path) async {
    try {
      final client = await _client();
      await client.stat(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> dispose() async {
    try {
      _sftpClient?.close();
    } catch (_) {
      // ignore
    } finally {
      _sftpClient = null;
    }
  }

  Future<String> readFile(String path) async {
    final client = await _client();
    final file = await client.open(path, mode: SftpFileOpenMode.read);
    try {
      final bytes = await file.readBytes();
      return utf8.decode(bytes);
    } finally {
      await file.close();
    }
  }

  Future<void> writeFile(String path, String contents) async {
    final client = await _client();
    final file = await client.open(
      path,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      final data = utf8.encode(contents);
      await file.writeBytes(Uint8List.fromList(data));
    } finally {
      await file.close();
    }
  }
}

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../data/services/sftp_service.dart';

class FileEditorScreen extends StatefulWidget {
  final String path;

  const FileEditorScreen({
    super.key,
    required this.path,
  });

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  final SftpService _sftpService = SftpService();
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void dispose() {
    _sftpService.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final content = await _sftpService.readFile(widget.path);
      if (!mounted) return;
      setState(() {
        _controller.text = content;
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

  Future<void> _saveFile() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _sftpService.writeFile(widget.path, _controller.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('file_manager.save_success'.tr())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('file_manager.save_error'.tr(args: [e.toString()])),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('file_manager.edit_title'.tr(args: [widget.path])),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            tooltip: 'common.save'.tr(),
            onPressed: _isSaving ? null : _saveFile,
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadFile,
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _controller,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: 'file_manager.editing'.tr(args: [widget.path]),
        ),
      ),
    );
  }
}

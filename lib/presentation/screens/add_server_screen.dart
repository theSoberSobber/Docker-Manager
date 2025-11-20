import 'package:flutter/material.dart';
import '../../domain/models/server.dart';
import '../../data/services/ssh_connection_service.dart';
import 'package:easy_localization/easy_localization.dart';

class AddServerScreen extends StatefulWidget {
  final Server? server;
  
  const AddServerScreen({super.key, this.server});

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final SSHConnectionService _sshService = SSHConnectionService();
  bool _usePassword = true;
  bool _isTesting = false;
  String? _testResult;
  
  bool get _isEditMode => widget.server != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _loadServerData();
    }
  }
  
  void _loadServerData() {
    final server = widget.server!;
    _nameController.text = server.name;
    _ipController.text = server.ip;
    _portController.text = server.port.toString();
    _usernameController.text = server.username;
    
    if (server.password != null && server.password!.isNotEmpty) {
      _usePassword = true;
      _passwordController.text = server.password!;
    } else if (server.privateKey != null && server.privateKey!.isNotEmpty) {
      _usePassword = false;
      _privateKeyController.text = server.privateKey!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final server = Server(
        id: _isEditMode ? widget.server!.id : DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        ip: _ipController.text.trim(),
        port: int.parse(_portController.text.trim()),
        username: _usernameController.text.trim(),
        password: _usePassword && _passwordController.text.trim().isNotEmpty 
            ? _passwordController.text.trim() 
            : null,
        privateKey: !_usePassword && _privateKeyController.text.trim().isNotEmpty 
            ? _privateKeyController.text.trim() 
            : null,
      );
      Navigator.of(context).pop(server);
    }
  }

  Future<void> _testConnection() async {
    // Validate basic fields first
    if (_ipController.text.trim().isEmpty) {
      setState(() {
        _testResult = 'servers.error_ip_required'.tr();
      });
      return;
    }
    
    if (_usernameController.text.trim().isEmpty) {
      setState(() {
        _testResult = 'servers.error_username_required'.tr();
      });
      return;
    }

    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() {
        _testResult = 'servers.error_port_invalid'.tr();
      });
      return;
    }

    // Check if authentication is provided
    if (_usePassword && _passwordController.text.trim().isEmpty) {
      setState(() {
        _testResult = 'servers.error_password_required'.tr();
      });
      return;
    }

    if (!_usePassword && _privateKeyController.text.trim().isEmpty) {
      setState(() {
        _testResult = 'servers.error_private_key_required'.tr();
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final testServer = Server(
        id: 'test',
        name: 'Test Connection',
        ip: _ipController.text.trim(),
        port: port,
        username: _usernameController.text.trim(),
        password: _usePassword && _passwordController.text.trim().isNotEmpty 
            ? _passwordController.text.trim() 
            : null,
        privateKey: !_usePassword && _privateKeyController.text.trim().isNotEmpty 
            ? _privateKeyController.text.trim() 
            : null,
      );

      // Use the isolated test method that won't affect the main connection
      final result = await _sshService.testServerConnection(testServer);
      
      setState(() {
        _isTesting = false;
        if (result.success) {
          _testResult = 'success';
        } else {
          _testResult = result.error ?? 'Unknown connection error';
        }
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testResult = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'servers.add_server'.tr() : 'servers.add_server'.tr()),
        actions: [
          TextButton(
            onPressed: _submit,
            child: Text(
              (_isEditMode ? 'common.save'.tr() : 'common.add'.tr()).toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'servers.server_name'.tr(),
                hintText: 'servers.server_name_hint'.tr(),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.label),
                helperText: 'servers.server_name_helper'.tr(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'servers.error_name_required'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: 'servers.ip_address'.tr(),
                hintText: 'servers.ip_address_hint'.tr(),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.computer),
                helperText: 'servers.ip_address_helper'.tr(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'servers.error_ip_required'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _portController,
              decoration: InputDecoration(
                labelText: 'servers.port'.tr(),
                hintText: 'servers.port_hint'.tr(),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.settings_ethernet),
                helperText: 'servers.port_helper'.tr(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'servers.error_port_required'.tr();
                }
                final port = int.tryParse(value.trim());
                if (port == null || port < 1 || port > 65535) {
                  return 'servers.error_port_invalid'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'servers.username'.tr(),
                hintText: 'servers.username_hint'.tr(),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person),
                helperText: 'servers.username_helper'.tr(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'servers.error_username_required'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'servers.auth_method'.tr(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _usePassword = true;
                              });
                            },
                            child: Row(
                              children: [
                                Radio<bool>(
                                  value: true,
                                  groupValue: _usePassword,
                                  onChanged: (value) {
                                    setState(() {
                                      _usePassword = value!;
                                    });
                                  },
                                ),
                                Text('auth.password'.tr()),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _usePassword = false;
                              });
                            },
                            child: Row(
                              children: [
                                Radio<bool>(
                                  value: false,
                                  groupValue: _usePassword,
                                  onChanged: (value) {
                                    setState(() {
                                      _usePassword = value!;
                                    });
                                  },
                                ),
                                Text('auth.private_key'.tr()),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_usePassword)
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'auth.password'.tr(),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  helperText: 'servers.password_helper'.tr(),
                  helperMaxLines: 2,
                ),
                obscureText: true,
              )
            else
              TextFormField(
                controller: _privateKeyController,
                decoration: InputDecoration(
                  labelText: 'auth.private_key'.tr(),
                  hintText: 'servers.private_key_hint'.tr(),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.vpn_key),
                  helperText: 'servers.private_key_helper'.tr(),
                  helperMaxLines: 2,
                ),
                maxLines: 6,
              ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cable),
              label: Text(_isTesting ? 'servers.testing'.tr() : 'servers.test_connection'.tr()),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: _testResult == 'success'
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _testResult == 'success'
                        ? Colors.green.shade300
                        : Colors.red.shade300,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testResult == 'success'
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: _testResult == 'success'
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _testResult == 'success' 
                                ? 'servers.connection_successful'.tr()
                                : 'servers.connection_failed'.tr(),
                            style: TextStyle(
                              color: _testResult == 'success'
                                  ? Colors.green.shade900
                                  : Colors.red.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (_testResult != 'success') ...[
                            const SizedBox(height: 4),
                            Text(
                              _testResult!,
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'servers.info_message'.tr(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

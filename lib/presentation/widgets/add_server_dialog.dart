import 'package:flutter/material.dart';
import '../../domain/models/server.dart';

class AddServerDialog extends StatefulWidget {
  final Function(Server) onAdd;

  const AddServerDialog({super.key, required this.onAdd});

  @override
  State<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<AddServerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  bool _usePassword = true;

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
        id: DateTime.now().millisecondsSinceEpoch.toString(),
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
      widget.onAdd(server);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Docker Server'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Server Name',
                  hintText: 'Production Server, Dev Box, etc.',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a server name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'IP Address/Hostname',
                  hintText: '192.168.1.100',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.computer),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an IP address/Hostname';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '22',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.settings_ethernet),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a port';
                  }
                  final port = int.tryParse(value.trim());
                  if (port == null || port < 1 || port > 65535) {
                    return 'Please enter a valid port (1-65535)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'root',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      const Text(
                        'Authentication Method',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
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
                                mainAxisSize: MainAxisSize.min,
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
                                  const Text('Password'),
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
                                mainAxisSize: MainAxisSize.min,
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
                                  const Text('Private Key'),
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
              const SizedBox(height: 16),
              if (_usePassword)
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password (optional)',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                )
              else
                TextFormField(
                  controller: _privateKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Private Key (optional)',
                    hintText: 'Paste your private key here...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 4,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Add Server'),
        ),
      ],
    );
  }
}
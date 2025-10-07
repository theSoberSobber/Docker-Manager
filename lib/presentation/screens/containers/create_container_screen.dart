import 'package:flutter/material.dart';
import '../../../domain/models/docker_image.dart';
import '../../../data/repositories/docker_repository_impl.dart';
import '../../../data/services/ssh_connection_service.dart';

class CreateContainerScreen extends StatefulWidget {
  const CreateContainerScreen({super.key});

  @override
  State<CreateContainerScreen> createState() => _CreateContainerScreenState();
}

class _CreateContainerScreenState extends State<CreateContainerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _sshService = SSHConnectionService();
  final _dockerRepository = DockerRepositoryImpl();

  List<DockerImage> _availableImages = [];
  DockerImage? _selectedImage;
  bool _isLoadingImages = true;
  bool _isCreating = false;

  // Port mappings (host:container)
  final List<PortMapping> _portMappings = [];

  // Environment variables
  final List<EnvVariable> _envVariables = [];

  // Volume mounts
  final List<VolumeMount> _volumeMounts = [];

  // Advanced options
  String _restartPolicy = 'no';
  bool _showAdvanced = false;
  final _workDirController = TextEditingController();
  final _commandController = TextEditingController();
  final _memoryController = TextEditingController();
  final _cpuController = TextEditingController();
  String _networkMode = 'default';
  bool _privileged = false;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _workDirController.dispose();
    _commandController.dispose();
    _memoryController.dispose();
    _cpuController.dispose();
    super.dispose();
  }

  Future<void> _loadImages() async {
    try {
      final images = await _dockerRepository.getImages();
      setState(() {
        _availableImages = images;
        _isLoadingImages = false;
        if (images.isNotEmpty) {
          _selectedImage = images.first;
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingImages = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load images: $e')),
        );
      }
    }
  }

  void _addPortMapping() {
    setState(() {
      _portMappings.add(PortMapping());
    });
  }

  void _removePortMapping(int index) {
    setState(() {
      _portMappings.removeAt(index);
    });
  }

  void _addEnvVariable() {
    setState(() {
      _envVariables.add(EnvVariable());
    });
  }

  void _removeEnvVariable(int index) {
    setState(() {
      _envVariables.removeAt(index);
    });
  }

  void _addVolumeMount() {
    setState(() {
      _volumeMounts.add(VolumeMount());
    });
  }

  void _removeVolumeMount(int index) {
    setState(() {
      _volumeMounts.removeAt(index);
    });
  }

  String _buildDockerRunCommand() {
    if (_selectedImage == null) return '';

    final buffer = StringBuffer('docker run -d');

    // Container name
    if (_nameController.text.isNotEmpty) {
      buffer.write(' --name ${_nameController.text}');
    }

    // Port mappings
    for (final port in _portMappings) {
      if (port.hostPort.isNotEmpty && port.containerPort.isNotEmpty) {
        buffer.write(' -p ${port.hostPort}:${port.containerPort}');
      }
    }

    // Environment variables
    for (final env in _envVariables) {
      if (env.key.isNotEmpty && env.value.isNotEmpty) {
        buffer.write(' -e ${env.key}=${env.value}');
      }
    }

    // Volume mounts
    for (final volume in _volumeMounts) {
      if (volume.hostPath.isNotEmpty && volume.containerPath.isNotEmpty) {
        buffer.write(' -v ${volume.hostPath}:${volume.containerPath}');
      }
    }

    // Restart policy
    if (_restartPolicy != 'no') {
      buffer.write(' --restart=$_restartPolicy');
    }

    // Working directory
    if (_workDirController.text.isNotEmpty) {
      buffer.write(' -w ${_workDirController.text}');
    }

    // Memory limit
    if (_memoryController.text.isNotEmpty) {
      buffer.write(' -m ${_memoryController.text}');
    }

    // CPU limit
    if (_cpuController.text.isNotEmpty) {
      buffer.write(' --cpus=${_cpuController.text}');
    }

    // Network mode
    if (_networkMode != 'default') {
      buffer.write(' --network=$_networkMode');
    }

    // Privileged
    if (_privileged) {
      buffer.write(' --privileged');
    }

    // Image
    buffer.write(' ${_selectedImage!.repository}:${_selectedImage!.tag}');

    // Command override
    if (_commandController.text.isNotEmpty) {
      buffer.write(' ${_commandController.text}');
    }

    return buffer.toString();
  }

  Future<void> _createContainer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image')),
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final command = _buildDockerRunCommand();
      final result = await _sshService.executeCommand(command);

      if (mounted) {
        if (result != null && result.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Container created successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true); // Return true to indicate success
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create container'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Container'),
      ),
      body: _isLoadingImages
          ? const Center(child: CircularProgressIndicator())
          : _availableImages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_not_supported,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No images available',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Pull or build an image first to create containers',
                      ),
                    ],
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Image Selection
                      _buildSectionTitle('Image Selection'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: DropdownButtonFormField<DockerImage>(
                            value: _selectedImage,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Select Image',
                              border: OutlineInputBorder(),
                            ),
                            items: _availableImages.map((image) {
                              return DropdownMenuItem(
                                value: image,
                                child: Text(
                                  '${image.repository}:${image.tag}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedImage = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Container Name
                      _buildSectionTitle('Container Configuration'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Container Name (optional)',
                                  hintText: 'Auto-generated if empty',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value != null && value.isNotEmpty) {
                                    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*$')
                                        .hasMatch(value)) {
                                      return 'Invalid container name format';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Port Mappings
                      _buildSectionTitle('Port Mappings'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              ..._portMappings.asMap().entries.map((entry) {
                                final index = entry.key;
                                final port = entry.value;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: port.hostPort,
                                          decoration: const InputDecoration(
                                            labelText: 'Host Port',
                                            border: OutlineInputBorder(),
                                          ),
                                          keyboardType: TextInputType.number,
                                          onChanged: (value) {
                                            port.hostPort = value;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(':'),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: port.containerPort,
                                          decoration: const InputDecoration(
                                            labelText: 'Container Port',
                                            border: OutlineInputBorder(),
                                          ),
                                          keyboardType: TextInputType.number,
                                          onChanged: (value) {
                                            port.containerPort = value;
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () =>
                                            _removePortMapping(index),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              TextButton.icon(
                                onPressed: _addPortMapping,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Port Mapping'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Environment Variables
                      _buildSectionTitle('Environment Variables'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              ..._envVariables.asMap().entries.map((entry) {
                                final index = entry.key;
                                final env = entry.value;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: env.key,
                                          decoration: const InputDecoration(
                                            labelText: 'Key',
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (value) {
                                            env.key = value;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('='),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: env.value,
                                          decoration: const InputDecoration(
                                            labelText: 'Value',
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (value) {
                                            env.value = value;
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () =>
                                            _removeEnvVariable(index),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              TextButton.icon(
                                onPressed: _addEnvVariable,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Environment Variable'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Volume Mounts
                      _buildSectionTitle('Volume Mounts'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              ..._volumeMounts.asMap().entries.map((entry) {
                                final index = entry.key;
                                final volume = entry.value;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: volume.hostPath,
                                          decoration: const InputDecoration(
                                            labelText: 'Host Path',
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (value) {
                                            volume.hostPath = value;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(':'),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: volume.containerPath,
                                          decoration: const InputDecoration(
                                            labelText: 'Container Path',
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (value) {
                                            volume.containerPath = value;
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () =>
                                            _removeVolumeMount(index),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              TextButton.icon(
                                onPressed: _addVolumeMount,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Volume Mount'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Advanced Options
                      Card(
                        child: ExpansionTile(
                          title: const Text('Advanced Options'),
                          initiallyExpanded: _showAdvanced,
                          onExpansionChanged: (expanded) {
                            setState(() {
                              _showAdvanced = expanded;
                            });
                          },
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  DropdownButtonFormField<String>(
                                    value: _restartPolicy,
                                    decoration: const InputDecoration(
                                      labelText: 'Restart Policy',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'no', child: Text('No')),
                                      DropdownMenuItem(
                                          value: 'always',
                                          child: Text('Always')),
                                      DropdownMenuItem(
                                          value: 'unless-stopped',
                                          child: Text('Unless Stopped')),
                                      DropdownMenuItem(
                                          value: 'on-failure',
                                          child: Text('On Failure')),
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        _restartPolicy = value!;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _workDirController,
                                    decoration: const InputDecoration(
                                      labelText: 'Working Directory',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _commandController,
                                    decoration: const InputDecoration(
                                      labelText: 'Command Override',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _memoryController,
                                    decoration: const InputDecoration(
                                      labelText: 'Memory Limit (e.g., 512m)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _cpuController,
                                    decoration: const InputDecoration(
                                      labelText: 'CPU Limit (e.g., 0.5)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    value: _networkMode,
                                    decoration: const InputDecoration(
                                      labelText: 'Network Mode',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'default',
                                          child: Text('Default')),
                                      DropdownMenuItem(
                                          value: 'bridge',
                                          child: Text('Bridge')),
                                      DropdownMenuItem(
                                          value: 'host', child: Text('Host')),
                                      DropdownMenuItem(
                                          value: 'none', child: Text('None')),
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        _networkMode = value!;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  SwitchListTile(
                                    title: const Text('Privileged Mode'),
                                    value: _privileged,
                                    onChanged: (value) {
                                      setState(() {
                                        _privileged = value;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isCreating
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: _isCreating ? null : _createContainer,
                              child: _isCreating
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('Create & Start'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class PortMapping {
  String hostPort = '';
  String containerPort = '';
}

class EnvVariable {
  String key = '';
  String value = '';
}

class VolumeMount {
  String hostPath = '';
  String containerPath = '';
}

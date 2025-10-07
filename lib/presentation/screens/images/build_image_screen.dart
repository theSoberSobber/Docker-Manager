import 'package:flutter/material.dart';
import '../../../data/services/ssh_connection_service.dart';

class BuildImageScreen extends StatefulWidget {
  const BuildImageScreen({super.key});

  @override
  State<BuildImageScreen> createState() => _BuildImageScreenState();
}

class _BuildImageScreenState extends State<BuildImageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _tagController = TextEditingController(text: 'latest');
  final _dockerfileController = TextEditingController(
    text: 'FROM busybox\nRUN echo "Hello from Docker Manager"',
  );
  final _sshService = SSHConnectionService();
  
  bool _isBuilding = false;
  String _buildLogs = '';
  final ScrollController _logsScrollController = ScrollController();

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    _dockerfileController.dispose();
    _logsScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_logsScrollController.hasClients) {
      _logsScrollController.animateTo(
        _logsScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _buildImage() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isBuilding = true;
      _buildLogs = '';
    });

    try {
      final imageName = _nameController.text.trim();
      final tag = _tagController.text.trim();
      final dockerfile = _dockerfileController.text;

      // Create a temporary directory and Dockerfile on the server
      final tempDir = '/tmp/docker_build_${DateTime.now().millisecondsSinceEpoch}';
      final dockerfilePath = '$tempDir/Dockerfile';

      // Create temp directory
      await _sshService.executeCommand('mkdir -p $tempDir');

      // Write Dockerfile content
      // Escape single quotes in dockerfile content
      final escapedDockerfile = dockerfile.replaceAll("'", "'\\''");
      await _sshService.executeCommand("echo '$escapedDockerfile' > $dockerfilePath");

      setState(() {
        _buildLogs += 'Created Dockerfile at $dockerfilePath\n';
        _buildLogs += 'Building image $imageName:$tag...\n\n';
      });
      _scrollToBottom();

      // Build the image with streaming output
      final buildCommand = 'docker build -t $imageName:$tag -f $dockerfilePath $tempDir';
      
      // For now, execute command and get output
      // TODO: Implement streaming output
      final result = await _sshService.executeCommand(buildCommand);

      setState(() {
        if (result != null && result.isNotEmpty) {
          _buildLogs += result;
        }
      });
      _scrollToBottom();

      // Cleanup
      await _sshService.executeCommand('rm -rf $tempDir');

      if (mounted) {
        // Check for success indicators in the output
        // Modern BuildKit: "writing image sha256:" or "naming to"
        // Legacy builder: "Successfully built"
        final isSuccess = result != null && 
                         (result.contains('Successfully built') || 
                          result.contains('writing image sha256:') ||
                          result.contains('naming to'));
        
        if (isSuccess) {
          setState(() {
            _buildLogs += '\n✓ Successfully built $imageName:$tag\n';
            _isBuilding = false;
          });
          _scrollToBottom();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully built $imageName:$tag'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Wait a moment for user to see the success message
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pop(true); // Return to images screen
          }
        } else {
          setState(() {
            _buildLogs += '\n✗ Build failed\n';
            _isBuilding = false;
          });
          _scrollToBottom();
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Build failed. Check logs for details.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _buildLogs += '\nError: $e\n';
        _isBuilding = false;
      });
      _scrollToBottom();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Build Image'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Image Name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Image Name',
                hintText: 'my-custom-image',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.image),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an image name';
                }
                if (!RegExp(r'^[a-z0-9][a-z0-9_.-]*$').hasMatch(value.trim())) {
                  return 'Invalid image name format';
                }
                return null;
              },
              enabled: !_isBuilding,
            ),
            const SizedBox(height: 16),

            // Tag
            TextFormField(
              controller: _tagController,
              decoration: const InputDecoration(
                labelText: 'Tag',
                hintText: 'latest',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a tag';
                }
                if (!RegExp(r'^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$')
                    .hasMatch(value.trim())) {
                  return 'Invalid tag format';
                }
                return null;
              },
              enabled: !_isBuilding,
            ),
            const SizedBox(height: 16),

            // Dockerfile Editor
            Text(
              'Dockerfile',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              child: TextFormField(
                controller: _dockerfileController,
                decoration: const InputDecoration(
                  hintText: 'FROM busybox\nRUN echo "hello"',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                ),
                maxLines: 12,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter Dockerfile content';
                  }
                  if (!value.toUpperCase().contains('FROM')) {
                    return 'Dockerfile must contain a FROM instruction';
                  }
                  return null;
                },
                enabled: !_isBuilding,
              ),
            ),
            const SizedBox(height: 24),

            // Build Button
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isBuilding ? null : _buildImage,
                icon: _isBuilding
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.build),
                label: Text(_isBuilding ? 'Building...' : 'Build Image'),
              ),
            ),
            const SizedBox(height: 24),

            // Build Logs
            if (_buildLogs.isNotEmpty) ...[
              Row(
                children: [
                  Text(
                    'Build Logs',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  if (!_isBuilding)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _buildLogs = '';
                        });
                      },
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade700),
                ),
                child: ListView(
                  controller: _logsScrollController,
                  padding: const EdgeInsets.all(12),
                  children: [
                    SelectableText(
                      _buildLogs,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// Represents a Docker action that can be performed on a resource
class DockerAction {
  final String label;
  final IconData icon;
  final String command;
  final Color? color;
  final bool isDestructive;

  const DockerAction({
    required this.label,
    required this.icon,
    required this.command,
    this.color,
    this.isDestructive = false,
  });
}

/// Generic dropdown menu for Docker resource actions
class DockerResourceActions extends StatelessWidget {
  final List<DockerAction> actions;
  final Function(DockerAction) onActionSelected;
  final String resourceName;

  const DockerResourceActions({
    super.key,
    required this.actions,
    required this.onActionSelected,
    required this.resourceName,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<DockerAction>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'common.actions_for'.tr(args: [resourceName]),
      onSelected: (action) {
        if (action.isDestructive) {
          _showConfirmationDialog(context, action);
        } else {
          onActionSelected(action);
        }
      },
      itemBuilder: (BuildContext context) {
        return actions.map((action) {
          return PopupMenuItem<DockerAction>(
            value: action,
            child: Row(
              children: [
                Icon(
                  action.icon,
                  size: 20,
                  color: action.color ?? Theme.of(context).iconTheme.color,
                ),
                const SizedBox(width: 12),
                Text(
                  action.label.tr(),
                  style: TextStyle(
                    color: action.color,
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
    );
  }

  void _showConfirmationDialog(BuildContext context, DockerAction action) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('actions.confirm_action'.tr(args: [action.label.tr()])),
          content: Text(
            'Are you sure you want to ${action.label.tr().toLowerCase()} "$resourceName"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('common.cancel'.tr()),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                onActionSelected(action);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: action.color ?? Colors.red,
              ),
              child: Text(
                action.label.tr(),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Predefined actions for containers
class ContainerActions {
  static List<DockerAction> getActions(bool isRunning) {
    final List<DockerAction> actions = [
      const DockerAction(
        label: 'actions.logs',
        icon: Icons.article,
        command: 'docker logs',
      ),
      const DockerAction(
        label: 'actions.inspect',
        icon: Icons.info,
        command: 'docker inspect',
      ),
    ];

    if (isRunning) {
      actions.addAll([
        const DockerAction(
          label: 'actions.stop',
          icon: Icons.stop,
          command: 'docker stop',
          color: Colors.red,
        ),
        const DockerAction(
          label: 'actions.restart',
          icon: Icons.refresh,
          command: 'docker restart',
          color: Colors.orange,
        ),
        const DockerAction(
          label: 'actions.shell',
          icon: Icons.terminal,
          command: 'docker exec -it',
        ),
      ]);
    } else {
      actions.addAll([
        const DockerAction(
          label: 'actions.start',
          icon: Icons.play_arrow,
          command: 'docker start',
          color: Colors.green,
        ),
        const DockerAction(
          label: 'actions.remove',
          icon: Icons.delete,
          command: 'docker rm',
          color: Colors.red,
          isDestructive: true,
        ),
      ]);
    }

    return actions;
  }
}

/// Predefined actions for images
class ImageActions {
  static List<DockerAction> getActions() {
    return [
      const DockerAction(
        label: 'actions.inspect',
        icon: Icons.info,
        command: 'docker inspect',
      ),
      const DockerAction(
        label: 'actions.history',
        icon: Icons.history,
        command: 'docker history',
      ),
      const DockerAction(
        label: 'actions.remove',
        icon: Icons.delete,
        command: 'docker rmi',
        color: Colors.red,
        isDestructive: true,
      ),
    ];
  }
}

/// Predefined actions for volumes
class VolumeActions {
  static List<DockerAction> getActions() {
    return [
      const DockerAction(
        label: 'actions.inspect',
        icon: Icons.info,
        command: 'docker volume inspect',
      ),
      const DockerAction(
        label: 'actions.remove',
        icon: Icons.delete,
        command: 'docker volume rm',
        color: Colors.red,
        isDestructive: true,
      ),
    ];
  }
}

/// Predefined actions for networks
class NetworkActions {
  static List<DockerAction> getActions() {
    return [
      const DockerAction(
        label: 'actions.inspect',
        icon: Icons.info,
        command: 'docker network inspect',
      ),
      const DockerAction(
        label: 'actions.remove',
        icon: Icons.delete,
        command: 'docker network rm',
        color: Colors.red,
        isDestructive: true,
      ),
    ];
  }
}
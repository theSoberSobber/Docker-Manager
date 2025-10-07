import 'package:flutter/material.dart';

class SpeedDialFAB extends StatefulWidget {
  final List<SpeedDialAction> actions;
  final IconData mainIcon;
  final String mainTooltip;

  const SpeedDialFAB({
    super.key,
    required this.actions,
    this.mainIcon = Icons.add,
    this.mainTooltip = 'Actions',
  });

  @override
  State<SpeedDialFAB> createState() => _SpeedDialFABState();
}

class _SpeedDialFABState extends State<SpeedDialFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotation;
  late Animation<double> _translation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _rotation = Tween<double>(begin: 0, end: 0.125).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _translation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Action buttons
        if (_isOpen)
          ...List.generate(widget.actions.length, (index) {
            final action = widget.actions[widget.actions.length - 1 - index];
            return AnimatedBuilder(
              animation: _translation,
              builder: (context, child) {
                return Opacity(
                  opacity: _translation.value,
                  child: child,
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (action.label != null) ...[
                      Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            action.label!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FloatingActionButton.small(
                      heroTag: action.label ?? 'action_$index',
                      onPressed: () {
                        _toggle();
                        action.onPressed();
                      },
                      tooltip: action.tooltip,
                      child: Icon(action.icon),
                    ),
                  ],
                ),
              ),
            );
          }),
        // Main FAB
        FloatingActionButton(
          heroTag: 'main_fab',
          onPressed: _toggle,
          tooltip: widget.mainTooltip,
          child: AnimatedBuilder(
            animation: _rotation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotation.value * 2 * 3.14159,
                child: Icon(_isOpen ? Icons.close : widget.mainIcon),
              );
            },
          ),
        ),
      ],
    );
  }
}

class SpeedDialAction {
  final IconData icon;
  final String? label;
  final String tooltip;
  final VoidCallback onPressed;

  SpeedDialAction({
    required this.icon,
    this.label,
    required this.tooltip,
    required this.onPressed,
  });
}

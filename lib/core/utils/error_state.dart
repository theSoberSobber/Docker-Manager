import 'package:flutter/material.dart';

/// Configuration for error state UI
class ErrorState {
  final IconData icon;
  final double iconSize;
  final Color? iconColor;
  final String headline;
  final String message;
  final String retryButtonText;
  final VoidCallback? onRetry;

  const ErrorState({
    this.icon = Icons.error_outline,
    this.iconSize = 64.0,
    this.iconColor = Colors.red,
    required this.headline,
    required this.message,
    this.retryButtonText = 'Retry',
    this.onRetry,
  });

  /// Factory for connection errors
  factory ErrorState.connection({
    required String message,
    VoidCallback? onRetry,
  }) {
    return ErrorState(
      icon: Icons.cloud_off,
      headline: 'Connection Failed',
      message: message,
      onRetry: onRetry,
    );
  }

  /// Factory for general errors
  factory ErrorState.general({
    required String message,
    VoidCallback? onRetry,
  }) {
    return ErrorState(
      icon: Icons.error_outline,
      headline: 'Error',
      message: message,
      onRetry: onRetry,
    );
  }

  /// Factory for no data/empty state
  factory ErrorState.empty({
    required String message,
    VoidCallback? onRetry,
  }) {
    return ErrorState(
      icon: Icons.inbox_outlined,
      iconColor: Colors.grey,
      headline: 'No Servers Found',
      message: message,
      onRetry: onRetry,
    );
  }

  /// Factory for permission errors (Docker group, sudo, etc.)
  factory ErrorState.permission({
    required String message,
    VoidCallback? onRetry,
  }) {
    return ErrorState(
      icon: Icons.lock_outline,
      iconColor: Colors.orange,
      headline: 'Permission Issue',
      message: message,
      onRetry: onRetry,
    );
  }
}

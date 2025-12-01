import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../screens/settings_screen.dart';
import '../../data/services/analytics_service.dart';

class SettingsIconButton extends StatelessWidget {
  const SettingsIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    final analytics = AnalyticsService();
    return Container(
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Icon(
          Icons.settings,
          color: Theme.of(context).colorScheme.primary,
        ),
        onPressed: () {
          analytics.trackButton('open_settings', location: 'search_bar');
          Navigator.push(
            context,
            MaterialPageRoute(
              settings: const RouteSettings(name: 'Settings'),
              builder: (context) => const SettingsScreen(),
            ),
          );
        },
        tooltip: 'common.settings'.tr(),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'search_bar.dart';
import 'settings_icon_button.dart';

class SearchBarWithSettings extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onSearchChanged;

  const SearchBarWithSettings({
    super.key,
    required this.hintText,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: CustomSearchBar(
              hintText: hintText,
              onSearchChanged: onSearchChanged,
            ),
          ),
          const SettingsIconButton(),
        ],
      ),
    );
  }
}

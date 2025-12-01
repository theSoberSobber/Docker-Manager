//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <url_launcher_windows/url_launcher_windows.h>

/**
 * @brief Registers platform plugins with the given Flutter plugin registry.
 *
 * Registers the UrlLauncherWindows plugin implementation with the provided
 * Flutter plugin registry so the plugin becomes available to the Flutter
 * engine on Windows.
 *
 * @param registry Pointer to the Flutter plugin registry used to register plugins.
 */
void RegisterPlugins(flutter::PluginRegistry* registry) {
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
}
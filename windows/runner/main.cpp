#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // Keep Win32 window messages responsive while Flutter lays out and paints
  // frames during live resize. Explicitly separating the UI isolate avoids the
  // Windows thread-merging performance regression seen in recent engines.
  project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);
  project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);

  // The current Windows Impeller backend can allocate aggressively while the
  // swap chain is repeatedly resized. Skia remains GPU accelerated and is more
  // stable for this image-heavy desktop UI.
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(20, 20);
  Win32Window::Size size(1440, 900);
  if (!window.Create(L"3080\u5DE5\u5177\u7BB1", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

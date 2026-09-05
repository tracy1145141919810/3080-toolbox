#ifndef RUNNER_SCREEN_CAPTURE_BRIDGE_H_
#define RUNNER_SCREEN_CAPTURE_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>

#include <memory>

#include <windows.h>

class ScreenCaptureBridge {
 public:
  ScreenCaptureBridge(flutter::BinaryMessenger* messenger, HWND owner_window);
  ~ScreenCaptureBridge();

 private:
  HWND owner_window_;
  bool owner_was_maximized_ = false;
  HWND indicator_window_ = nullptr;
  HANDLE child_job_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_SCREEN_CAPTURE_BRIDGE_H_

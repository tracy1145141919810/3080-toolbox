#include "screen_capture_bridge.h"

#include <windowsx.h>

#include <algorithm>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include <flutter/standard_method_codec.h>

namespace {

constexpr wchar_t kSelectorClassName[] = L"Toolbox3080RegionSelector";
constexpr wchar_t kIndicatorClassName[] = L"Toolbox3080RecordingIndicator";

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0);
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), length);
  return result;
}

LRESULT CALLBACK RecordingIndicatorProc(HWND window, UINT message,
                                        WPARAM wparam, LPARAM lparam) {
  auto* channel = reinterpret_cast<
      flutter::MethodChannel<flutter::EncodableValue>*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCT*>(lparam);
    channel = static_cast<flutter::MethodChannel<flutter::EncodableValue>*>(
        create->lpCreateParams);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(channel));
  }
  switch (message) {
    case WM_SETCURSOR:
      SetCursor(LoadCursor(nullptr, IDC_HAND));
      return TRUE;
    case WM_LBUTTONUP: {
      if (channel != nullptr) {
        channel->InvokeMethod("recordingIndicatorClicked", nullptr);
      }
      return 0;
    }
    case WM_ERASEBKGND:
      return TRUE;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(window, &paint);
      RECT client{};
      GetClientRect(window, &client);
      HBRUSH background = CreateSolidBrush(RGB(17, 24, 39));
      FillRect(dc, &client, background);
      DeleteObject(background);

      HBRUSH dot = CreateSolidBrush(RGB(240, 68, 56));
      HGDIOBJ old_brush = SelectObject(dc, dot);
      HGDIOBJ old_pen = SelectObject(dc, GetStockObject(NULL_PEN));
      Ellipse(dc, 16, 18, 32, 34);
      SelectObject(dc, old_pen);
      SelectObject(dc, old_brush);
      DeleteObject(dot);

      wchar_t text[256]{};
      GetWindowTextW(window, text, static_cast<int>(std::size(text)));
      RECT text_rect{43, 0, client.right - 12, client.bottom};
      SetBkMode(dc, TRANSPARENT);
      SetTextColor(dc, RGB(255, 255, 255));
      DrawTextW(dc, text, -1, &text_rect,
                DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
      EndPaint(window, &paint);
      return 0;
    }
  }
  return DefWindowProc(window, message, wparam, lparam);
}

HWND CreateRecordingIndicator(
    const std::wstring& text,
    flutter::MethodChannel<flutter::EncodableValue>* channel) {
  HINSTANCE instance = GetModuleHandle(nullptr);
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = RecordingIndicatorProc;
  window_class.hInstance = instance;
  window_class.hCursor = LoadCursor(nullptr, IDC_HAND);
  window_class.hbrBackground =
      static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  window_class.lpszClassName = kIndicatorClassName;
  if (RegisterClassW(&window_class) == 0 &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return nullptr;
  }

  const int virtual_x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int virtual_y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int virtual_width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  HWND indicator = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kIndicatorClassName,
      text.c_str(), WS_POPUP, virtual_x + virtual_width - 332, virtual_y + 24,
      308, 52, nullptr, nullptr, instance, channel);
  if (indicator == nullptr) {
    return nullptr;
  }
  SetWindowDisplayAffinity(indicator, WDA_EXCLUDEFROMCAPTURE);
  ShowWindow(indicator, SW_SHOWNOACTIVATE);
  UpdateWindow(indicator);
  return indicator;
}

struct RegionSelection {
  bool done = false;
  bool cancelled = false;
  bool dragging = false;
  POINT start{};
  POINT current{};
  RECT result{};
  int virtual_x = 0;
  int virtual_y = 0;
};

RECT NormalizedRect(const POINT& first, const POINT& second) {
  RECT rect{};
  rect.left = std::min(first.x, second.x);
  rect.top = std::min(first.y, second.y);
  rect.right = std::max(first.x, second.x);
  rect.bottom = std::max(first.y, second.y);
  return rect;
}

LRESULT CALLBACK RegionSelectorProc(HWND window, UINT message, WPARAM wparam,
                                    LPARAM lparam) {
  auto* state = reinterpret_cast<RegionSelection*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCT*>(lparam);
    state = static_cast<RegionSelection*>(create->lpCreateParams);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(state));
  }

  switch (message) {
    case WM_SETCURSOR:
      SetCursor(LoadCursor(nullptr, IDC_CROSS));
      return TRUE;
    case WM_ERASEBKGND:
      return TRUE;
    case WM_LBUTTONDOWN:
      if (state != nullptr) {
        state->dragging = true;
        state->start = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        state->current = state->start;
        SetCapture(window);
        InvalidateRect(window, nullptr, TRUE);
      }
      return 0;
    case WM_MOUSEMOVE:
      if (state != nullptr && state->dragging) {
        state->current = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        InvalidateRect(window, nullptr, TRUE);
      }
      return 0;
    case WM_LBUTTONUP:
      if (state != nullptr && state->dragging) {
        state->current = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ReleaseCapture();
        const RECT local = NormalizedRect(state->start, state->current);
        if (local.right - local.left >= 32 && local.bottom - local.top >= 32) {
          state->result = {local.left + state->virtual_x,
                           local.top + state->virtual_y,
                           local.right + state->virtual_x,
                           local.bottom + state->virtual_y};
          state->done = true;
          DestroyWindow(window);
        } else {
          state->dragging = false;
          InvalidateRect(window, nullptr, TRUE);
        }
      }
      return 0;
    case WM_RBUTTONDOWN:
    case WM_KEYDOWN:
      if (state != nullptr &&
          (message == WM_RBUTTONDOWN || wparam == VK_ESCAPE)) {
        state->cancelled = true;
        state->done = true;
        DestroyWindow(window);
        return 0;
      }
      break;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(window, &paint);
      RECT client{};
      GetClientRect(window, &client);
      FillRect(dc, &client, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
      RECT help_rect{24, 20, client.right - 24, 58};
      SetBkMode(dc, TRANSPARENT);
      SetTextColor(dc, RGB(255, 255, 255));
      DrawTextW(dc,
                L"\u62D6\u52A8\u9F20\u6807\u6846\u9009\u5F55\u5236\u533A"
                L"\u57DF \u00B7 Esc \u6216\u53F3\u952E\u53D6\u6D88",
                -1, &help_rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
      if (state != nullptr && state->dragging) {
        const RECT selected = NormalizedRect(state->start, state->current);
        HPEN pen = CreatePen(PS_SOLID, 4, RGB(37, 99, 235));
        HGDIOBJ old_pen = SelectObject(dc, pen);
        HGDIOBJ old_brush = SelectObject(dc, GetStockObject(NULL_BRUSH));
        Rectangle(dc, selected.left, selected.top, selected.right,
                  selected.bottom);
        SelectObject(dc, old_brush);
        SelectObject(dc, old_pen);
        DeleteObject(pen);

        const int width = selected.right - selected.left;
        const int height = selected.bottom - selected.top;
        std::wstring label = std::to_wstring(width) + L" x " +
                             std::to_wstring(height);
        RECT label_rect{selected.left + 8, selected.top + 8,
                        selected.left + 190, selected.top + 40};
        SetBkColor(dc, RGB(37, 99, 235));
        SetTextColor(dc, RGB(255, 255, 255));
        DrawTextW(dc, label.c_str(), -1, &label_rect,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE);
      }
      EndPaint(window, &paint);
      return 0;
    }
  }
  return DefWindowProc(window, message, wparam, lparam);
}

std::optional<RECT> SelectScreenRegion(HWND owner_window) {
  HINSTANCE instance = GetModuleHandle(nullptr);
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = RegionSelectorProc;
  window_class.hInstance = instance;
  window_class.hCursor = LoadCursor(nullptr, IDC_CROSS);
  window_class.hbrBackground =
      static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  window_class.lpszClassName = kSelectorClassName;
  if (RegisterClassW(&window_class) == 0 &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return std::nullopt;
  }

  RegionSelection state;
  state.virtual_x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  state.virtual_y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);

  HWND selector = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED, kSelectorClassName,
      L"Select recording area", WS_POPUP, state.virtual_x, state.virtual_y,
      width, height, owner_window, nullptr, instance, &state);
  if (selector == nullptr) {
    return std::nullopt;
  }
  SetLayeredWindowAttributes(selector, 0, 145, LWA_ALPHA);
  ShowWindow(selector, SW_SHOW);
  SetForegroundWindow(selector);
  SetFocus(selector);

  MSG message{};
  while (!state.done) {
    const BOOL status = GetMessageW(&message, nullptr, 0, 0);
    if (status <= 0) {
      state.cancelled = true;
      state.done = true;
      if (status == 0) {
        PostQuitMessage(static_cast<int>(message.wParam));
      }
      break;
    }
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }

  if (IsWindow(selector)) {
    DestroyWindow(selector);
  }
  SetForegroundWindow(owner_window);
  if (state.cancelled) {
    return std::nullopt;
  }
  return state.result;
}

const flutter::EncodableValue* FindValue(const flutter::EncodableMap& map,
                                         const char* key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

int ReadInt(const flutter::EncodableMap& map, const char* key, int fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* number = std::get_if<int32_t>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<int64_t>(value)) {
    return static_cast<int>(*number);
  }
  return fallback;
}

bool ReadBool(const flutter::EncodableMap& map, const char* key,
              bool fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* flag = std::get_if<bool>(value)) {
    return *flag;
  }
  return fallback;
}

std::string ReadString(const flutter::EncodableMap& map, const char* key,
                       const std::string& fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* text = std::get_if<std::string>(value)) {
    return *text;
  }
  return fallback;
}

std::optional<std::vector<uint8_t>> CaptureRegion(
    const flutter::EncodableMap& arguments, int* captured_width,
    int* captured_height) {
  const int x = ReadInt(arguments, "x", 0);
  const int y = ReadInt(arguments, "y", 0);
  const int source_width = ReadInt(arguments, "width", 0);
  const int source_height = ReadInt(arguments, "height", 0);
  const int output_width = ReadInt(arguments, "outputWidth", source_width);
  const int output_height = ReadInt(arguments, "outputHeight", source_height);
  const bool include_cursor = ReadBool(arguments, "includeCursor", true);
  if (source_width <= 0 || source_height <= 0 || output_width <= 0 ||
      output_height <= 0 || output_width > 4096 || output_height > 4096) {
    return std::nullopt;
  }

  HDC screen_dc = GetDC(nullptr);
  HDC memory_dc = CreateCompatibleDC(screen_dc);
  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = output_width;
  bitmap_info.bmiHeader.biHeight = -output_height;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  void* pixel_data = nullptr;
  HBITMAP bitmap = CreateDIBSection(screen_dc, &bitmap_info, DIB_RGB_COLORS,
                                    &pixel_data, nullptr, 0);
  if (screen_dc == nullptr || memory_dc == nullptr || bitmap == nullptr ||
      pixel_data == nullptr) {
    if (bitmap != nullptr) DeleteObject(bitmap);
    if (memory_dc != nullptr) DeleteDC(memory_dc);
    if (screen_dc != nullptr) ReleaseDC(nullptr, screen_dc);
    return std::nullopt;
  }

  HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);
  BOOL copied = FALSE;
  if (source_width == output_width && source_height == output_height) {
    copied = BitBlt(memory_dc, 0, 0, output_width, output_height, screen_dc, x,
                    y, SRCCOPY | CAPTUREBLT);
  } else {
    SetStretchBltMode(memory_dc, HALFTONE);
    SetBrushOrgEx(memory_dc, 0, 0, nullptr);
    copied = StretchBlt(memory_dc, 0, 0, output_width, output_height, screen_dc,
                        x, y, source_width, source_height,
                        SRCCOPY | CAPTUREBLT);
  }

  if (copied && include_cursor) {
    CURSORINFO cursor_info{};
    cursor_info.cbSize = sizeof(CURSORINFO);
    if (GetCursorInfo(&cursor_info) &&
        (cursor_info.flags & CURSOR_SHOWING) != 0) {
      ICONINFO icon_info{};
      if (GetIconInfo(cursor_info.hCursor, &icon_info)) {
        const double scale_x =
            static_cast<double>(output_width) / source_width;
        const double scale_y =
            static_cast<double>(output_height) / source_height;
        const int cursor_x = static_cast<int>(
            (cursor_info.ptScreenPos.x - x - static_cast<int>(icon_info.xHotspot)) *
            scale_x);
        const int cursor_y = static_cast<int>(
            (cursor_info.ptScreenPos.y - y - static_cast<int>(icon_info.yHotspot)) *
            scale_y);
        const int cursor_width = std::max(
            1, static_cast<int>(GetSystemMetrics(SM_CXCURSOR) * scale_x));
        const int cursor_height = std::max(
            1, static_cast<int>(GetSystemMetrics(SM_CYCURSOR) * scale_y));
        DrawIconEx(memory_dc, cursor_x, cursor_y, cursor_info.hCursor,
                   cursor_width, cursor_height, 0, nullptr, DI_NORMAL);
        if (icon_info.hbmMask != nullptr) DeleteObject(icon_info.hbmMask);
        if (icon_info.hbmColor != nullptr) DeleteObject(icon_info.hbmColor);
      }
    }
  }

  std::optional<std::vector<uint8_t>> pixels;
  if (copied) {
    const size_t byte_count = static_cast<size_t>(output_width) *
                              static_cast<size_t>(output_height) * 4;
    auto* bytes = static_cast<uint8_t*>(pixel_data);
    for (size_t index = 3; index < byte_count; index += 4) {
      bytes[index] = 255;
    }
    pixels = std::vector<uint8_t>(bytes, bytes + byte_count);
    *captured_width = output_width;
    *captured_height = output_height;
  }

  SelectObject(memory_dc, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory_dc);
  ReleaseDC(nullptr, screen_dc);
  return pixels;
}

}  // namespace

ScreenCaptureBridge::ScreenCaptureBridge(flutter::BinaryMessenger* messenger,
                                         HWND owner_window)
    : owner_window_(owner_window),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "toolbox_3080/screen_capture",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "selectRegion") {
          const auto selection = SelectScreenRegion(owner_window_);
          if (!selection.has_value()) {
            result->Success();
            return;
          }
          flutter::EncodableMap map;
          map[flutter::EncodableValue("x")] =
              flutter::EncodableValue(selection->left);
          map[flutter::EncodableValue("y")] =
              flutter::EncodableValue(selection->top);
          map[flutter::EncodableValue("width")] =
              flutter::EncodableValue(selection->right - selection->left);
          map[flutter::EncodableValue("height")] =
              flutter::EncodableValue(selection->bottom - selection->top);
          result->Success(flutter::EncodableValue(map));
          return;
        }

        if (call.method_name() == "captureRegion") {
          const auto* arguments = call.arguments() == nullptr
                                      ? nullptr
                                      : std::get_if<flutter::EncodableMap>(
                                            call.arguments());
          if (arguments == nullptr) {
            result->Error("INVALID_ARGUMENTS", "Missing capture arguments");
            return;
          }
          int width = 0;
          int height = 0;
          auto pixels = CaptureRegion(*arguments, &width, &height);
          if (!pixels.has_value()) {
            result->Error("CAPTURE_FAILED", "Unable to capture screen region");
            return;
          }
          flutter::EncodableMap map;
          map[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
          map[flutter::EncodableValue("height")] =
              flutter::EncodableValue(height);
          map[flutter::EncodableValue("pixels")] =
              flutter::EncodableValue(std::move(*pixels));
          result->Success(flutter::EncodableValue(map));
          return;
        }

        if (call.method_name() == "setToolboxVisible") {
          const auto* arguments = call.arguments() == nullptr
                                      ? nullptr
                                      : std::get_if<flutter::EncodableMap>(
                                            call.arguments());
          const bool visible =
              arguments == nullptr ? true : ReadBool(*arguments, "visible", true);
          ShowWindow(owner_window_, visible ? SW_RESTORE : SW_HIDE);
          if (visible) {
            SetForegroundWindow(owner_window_);
          }
          result->Success();
          return;
        }

        if (call.method_name() == "showRecordingIndicator") {
          const auto* arguments = call.arguments() == nullptr
                                      ? nullptr
                                      : std::get_if<flutter::EncodableMap>(
                                            call.arguments());
          const std::string text = arguments == nullptr
                                       ? "Recording"
                                       : ReadString(*arguments, "text", "Recording");
          if (indicator_window_ != nullptr && IsWindow(indicator_window_)) {
            DestroyWindow(indicator_window_);
          }
          indicator_window_ =
              CreateRecordingIndicator(Utf8ToWide(text), channel_.get());
          result->Success(flutter::EncodableValue(indicator_window_ != nullptr));
          return;
        }

        if (call.method_name() == "updateRecordingIndicator") {
          const auto* arguments = call.arguments() == nullptr
                                      ? nullptr
                                      : std::get_if<flutter::EncodableMap>(
                                            call.arguments());
          if (arguments != nullptr && indicator_window_ != nullptr &&
              IsWindow(indicator_window_)) {
            const std::wstring text =
                Utf8ToWide(ReadString(*arguments, "text", "Recording"));
            SetWindowTextW(indicator_window_, text.c_str());
            InvalidateRect(indicator_window_, nullptr, TRUE);
          }
          result->Success();
          return;
        }

        if (call.method_name() == "hideRecordingIndicator") {
          if (indicator_window_ != nullptr && IsWindow(indicator_window_)) {
            DestroyWindow(indicator_window_);
          }
          indicator_window_ = nullptr;
          result->Success();
          return;
        }

        result->NotImplemented();
      });
}

ScreenCaptureBridge::~ScreenCaptureBridge() {
  if (indicator_window_ != nullptr && IsWindow(indicator_window_)) {
    DestroyWindow(indicator_window_);
  }
}

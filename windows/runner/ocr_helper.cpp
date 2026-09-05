#include <windows.h>
#include <shellapi.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <vector>
#include <algorithm>

using namespace winrt;
using namespace Windows::Data::Json;
using namespace Windows::Media::Ocr;

// Separate, short-lived process: OCR never blocks Flutter's UI or message loop.
// Input/output files belong to one randomly named temporary directory managed
// by the caller. This executable contains no network or model-download code.
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  init_apartment(apartment_type::multi_threaded);
  int count = 0;
  auto args = CommandLineToArgvW(GetCommandLineW(), &count);
  if (!args || count < 3) return 2;
  const std::wstring mode(args[1]);
  if (mode != L"--languages" && count != 7) { LocalFree(args); return 2; }
  const std::filesystem::path output(args[mode == L"--languages" ? 2 : 3]);
  JsonObject response;
  int status = 0;
  try {
    JsonArray languages;
    for (const auto& lang : OcrEngine::AvailableRecognizerLanguages()) {
      JsonObject item;
      item.Insert(L"tag", JsonValue::CreateStringValue(lang.LanguageTag()));
      item.Insert(L"name", JsonValue::CreateStringValue(lang.DisplayName()));
      languages.Append(item);
    }
    response.Insert(L"languages", languages);
    if (mode == L"--recognize" && count == 7) {
      const auto width = std::stoi(args[4]);
      const auto height = std::stoi(args[5]);
      const auto limit = static_cast<int>(OcrEngine::MaxImageDimension());
      if (width < 1 || height < 1 || width > limit || height > limit)
        throw std::runtime_error("Image dimensions exceed local OCR limits");
      const std::wstring language(args[6]);
      auto engine = language == L"auto"
          ? OcrEngine::TryCreateFromUserProfileLanguages()
          : OcrEngine::TryCreateFromLanguage(Windows::Globalization::Language(language));
      if (!engine) throw std::runtime_error("OCR language is not installed. Install the Windows language OCR pack first.");
      std::ifstream input(std::filesystem::path(args[2]), std::ios::binary);
      std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), {});
      if (bytes.size() != static_cast<size_t>(width) * height * 4)
        throw std::runtime_error("Invalid BGRA image data");
      Windows::Storage::Streams::DataWriter writer;
      writer.WriteBytes(bytes);
      Windows::Graphics::Imaging::SoftwareBitmap bitmap(
          Windows::Graphics::Imaging::BitmapPixelFormat::Bgra8, width, height,
          Windows::Graphics::Imaging::BitmapAlphaMode::Ignore);
      bitmap.CopyFromBuffer(writer.DetachBuffer());
      const auto result = engine.RecognizeAsync(bitmap).get();
      std::wstring text;
      JsonArray blocks;
      for (const auto& line : result.Lines()) {
        if (!text.empty()) text += L"\n";
        text += line.Text();
        float left = static_cast<float>(width), top = static_cast<float>(height);
        float right = 0, bottom = 0;
        for (const auto& word : line.Words()) {
          const auto rect = word.BoundingRect();
          left = std::min(left, rect.X); top = std::min(top, rect.Y);
          right = std::max(right, rect.X + rect.Width);
          bottom = std::max(bottom, rect.Y + rect.Height);
        }
        if (right > left && bottom > top) {
          JsonObject block;
          block.Insert(L"text", JsonValue::CreateStringValue(line.Text()));
          block.Insert(L"x", JsonValue::CreateNumberValue(left));
          block.Insert(L"y", JsonValue::CreateNumberValue(top));
          block.Insert(L"width", JsonValue::CreateNumberValue(right-left));
          block.Insert(L"height", JsonValue::CreateNumberValue(bottom-top));
          blocks.Append(block);
        }
      }
      response.Insert(L"blocks", blocks);
      response.Insert(L"text", JsonValue::CreateStringValue(text));
      response.Insert(L"language", JsonValue::CreateStringValue(engine.RecognizerLanguage().LanguageTag()));
    } else if (mode != L"--languages") {
      throw std::runtime_error("Invalid OCR arguments");
    }
  } catch (const hresult_error& error) {
    response.Insert(L"error", JsonValue::CreateStringValue(error.message()));
    status = 1;
  } catch (const std::exception& error) {
    response.Insert(L"error", JsonValue::CreateStringValue(to_hstring(error.what())));
    status = 1;
  }
  std::ofstream file(output, std::ios::binary);
  file << to_string(response.Stringify());
  if (!file) status = 3;
  LocalFree(args);
  return status;
}

# 第三方组件说明

- 免安装版随应用本地部署 Microsoft Visual C++ 2015–2022 x64 Release CRT 可再分发 DLL（Microsoft 专有许可），来自构建工具的 `VC/Redist/MSVC` 目录；不包含调试运行库。

- 屏幕翻译使用 llama.cpp b10793（MIT）与腾讯 Hy-MT2-7B Q4_K_M GGUF 模型（Apache-2.0），许可文本位于 `translation/licenses`。
- 本地 OCR 使用 RapidOCR（Apache-2.0）、PaddleOCR 模型（Apache-2.0）及 ONNX Runtime；便携 Python 依赖的许可文本位于 `translation/licenses/python-packages`。
- 界面内置 Noto Sans CJK 字体，依据 SIL Open Font License 1.1 分发，字体许可同时包含在 Flutter 资源中。
- NVIDIA CUDA 12.4 的 CUDA Runtime 与 cuBLAS 可再分发组件随推理运行库提供，对应许可见 `translation/licenses/CUDA-EULA.html`。

- YOLO11n-seg 模型架构与权重源自 Ultralytics YOLO。Ultralytics 提供 AGPL-3.0 与企业商业许可双许可。
- ONNX Runtime DirectML 1.22.0 与 Microsoft DirectML 1.15.4 使用 MIT 许可；原始许可与第三方声明安装在 `licenses` 目录。
- `heic_native` 及其 Windows 版 libheif/libde265/libpng/zlib 运行库用于 HEIC/HEIF 本地解码；MIT、LGPL、libpng 与 zlib 许可文本安装在 `licenses` 目录。
- Flutter 及 Dart 依赖的许可信息可通过 Flutter 构建产物的许可清单查看。
- ImageMagick 7.1.2-29 Q16 x64 便携运行时用于本地图片格式转换，依据 ImageMagick License 分发。完整 `LICENSE.txt`、`NOTICE.txt` 和运行时配置文件安装在 `imagemagick` 目录。
- `flutter_zxing` 2.3.0 与其 ZXing-C++ 解码运行库用于本地二维码识别，分别依据 MIT 与 Apache-2.0 许可分发；许可文本安装在 `licenses` 目录。

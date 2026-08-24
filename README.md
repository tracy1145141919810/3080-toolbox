# 3080工具箱

一个采用 Flutter 构建的 Windows 本地工具箱。界面参考工具箱类软件的分类导航方式：左侧选择分类和工具，右侧进入实际工作区。当前内置“白底人像”“图片格式转换”“GIF录屏”和“硬件检测”四个模块。

Windows Runner 将 Flutter UI 隔离线程与窗口消息线程分开，并优先使用高性能 GPU 渲染；当前版本使用更稳定的 Skia Windows 后端，以减少连续拖动窗口边缘时的掉帧和内存抖动。

## 已内置工具

### 白底人像

- 导入 JPG、PNG、BMP、WebP、HEIC、HEIF 人像照片
- 使用随安装包提供的 libheif 在本地解码 HEIC/HEIF
- YOLO11n-seg 本地人像识别与实例分割，照片不上传
- ONNX Runtime DirectML 优先使用 NVIDIA、AMD 或 Intel GPU，失败时回退 CPU
- 任意 RGB/十六进制背景色与常用颜色预设
- 一寸、二寸、护照、社保、高清头像及自定义分辨率
- JPEG/PNG 导出，JPEG 可设置文件大小上限

### GIF录屏

- 以 ScreenToGif 的紧凑工作流为产品参考，自主实现界面与录制代码
- 全屏半透明框选录制区域，支持多显示器虚拟桌面坐标
- Windows GDI 本地抓屏，可选择是否录制鼠标指针
- 5/10/15 FPS 与 5 秒至 5 分钟录制设置；3 分钟以上自动限制为最高 5 FPS
- 开始录制后自动隐藏工具箱，避免工具箱覆盖录制内容
- 显示排除于屏幕捕获之外的“正在录制”浮动提示；点击浮窗会先暂停再返回工具箱
- 长录制使用 JPEG 压缩帧缓存，并自动降低捕获分辨率以控制内存占用
- 录制后显示帧时间线，可逐帧预览、删除所选帧或清空重录
- GIF 可设置 100%/75%/50% 输出分辨率、64/128/256 色
- 可设置目标文件大小上限；编码器会自动降低色彩或分辨率以尽量满足限制

### 图片格式转换

- 内置 ImageMagick 7.1.2-29 Q16 x64 便携运行时，无需单独安装或联网
- 批量选择文件，或递归扫描文件夹；单次最多加入 1000 张
- 输入覆盖 JPEG、PNG、WebP、AVIF、JPEG XL、TIFF、BMP、GIF、ICO、OpenEXR、PSD、JPEG 2000、HEIC/HEIF，以及常见相机 RAW
- 输出 JPEG、PNG、WebP、AVIF、JPEG XL、TIFF、BMP、GIF、ICO 与 OpenEXR
- 支持输出宽高、保持宽高比、画质、元数据和同名覆盖设置
- JPEG、WebP、AVIF、JPEG XL 可设置目标文件大小，程序会自动尝试降低画质
- 所有转换都在本机完成；本版 ImageMagick 可读取 HEIC/HEIF，但不提供 HEIC/HEIF 编码

### 硬件检测

- 在独立页面本地读取 Windows CIM/WMI 硬件信息，不上传数据、不修改系统设置
- 顶部实时监测 CPU 占用与频率、GPU 占用/温度/显存/功耗，以及内存占用；默认每秒更新
- 离开硬件页后自动停止实时采样，避免无意义的后台资源占用
- 详细展示处理器、主板、内存、显卡、显示器、物理磁盘、声卡和活动网卡
- 支持重新检测、复制完整报告和导出 UTF-8 TXT 报告
- 检测到 NVIDIA GeForce RTX 3080 时，显卡结果以红色显示为“老牧师3080”
- 完成上述专属识别后，工具中心显示“整机性能评分 114514分”；其他显卡不显示评分

## 使用

1. 在“工具中心”打开“白底人像”，或直接从左侧导航进入。
2. 选择照片、背景颜色和推理设备，点击“自动换背景”。
3. 设置分辨率、适配方式、格式和目标文件大小。
4. 点击“导出成品”。

### 图片格式转换使用

1. 从左侧“图像处理”进入“格式转换”。
2. 点击“添加图片”多选文件，或点击“添加文件夹”扫描目录。
3. 设置输出格式、画质、分辨率、目标 KB 与输出文件夹。
4. 点击“开始转换”，完成后可直接打开输出文件夹。

### GIF录屏使用

1. 从左侧“屏幕工具”进入“GIF录屏”。
2. 点击“选择录制区域”，按住左键拖出至少 32 × 32 的矩形；右键或 Esc 取消。
3. 设置帧率、最长录制时间（最多 5 分钟）和是否包含鼠标，点击“开始录制”；工具箱会自动隐藏。
4. 点击“正在录制”浮窗会先暂停录制并恢复工具箱，可选择继续或停止。
5. 在帧时间线中检查或删除帧，设置输出分辨率、色彩与目标 KB，点击“导出 GIF”。

### 硬件检测使用

1. 从左侧“硬件工具”进入“硬件检测”，等待本地检测完成。
2. 在三块摘要卡和“详细信息”区域查看配置。
3. 可点击“重新检测”“复制报告”或“导出 TXT”。

## 构建

需要 Flutter 3.47 或更新版本、Visual Studio 2022 C++ 桌面工作负载和 Inno Setup 6。

```powershell
flutter pub get
flutter test
flutter build windows --release
```

`windows/runtime` 包含 ONNX Runtime DirectML、CPU 回退运行库、ImageMagick 便携运行时和对应许可文件。白底人像工具的 HEIC 解码依赖由 `heic_native` 在构建时一并打包。

## 开源参考与许可

- 工具箱布局参考 [图吧工具箱 WinUI3](https://github.com/luolangaga/tubatools) 的分类导航和工具卡片思路，未复制其代码或素材
- GIF 录屏流程参考 [ScreenToGif](https://github.com/NickeManarin/ScreenToGif) 的区域录制与帧编辑思路；没有复制或打包其 Ms-PL 源码
- 界面与应用源码：AGPL-3.0
- Ultralytics YOLO11：AGPL-3.0 或商业许可
- ONNX Runtime 与 DirectML：MIT
- heic_native、libheif、libde265、libpng、zlib：许可文本随安装包分发
- ImageMagick：ImageMagick License；便携运行时许可与 NOTICE 随安装包分发

若计划闭源商用，请先取得适用的 YOLO 商业许可。

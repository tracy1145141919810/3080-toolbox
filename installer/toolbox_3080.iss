#define MyAppName "3080工具箱"
#define MyAppVersion "1.8.1"
#define MyAppExeName "toolbox_3080.exe"

#if !FileExists("..\build\windows\x64\runner\Release\translation\llama-server.exe")
  #error "Full offline translation runtime is missing. Stage the runtime and rebuild first."
#endif
#if !FileExists("..\build\windows\x64\runner\Release\translation\models\Hy-MT2-7B-Q4_K_M.gguf")
  #error "Bundled Hy-MT2 model is missing."
#endif
#if !FileExists("..\build\windows\x64\runner\Release\layout_ocr\layout_ocr.exe")
  #error "Bundled multilingual OCR is missing."
#endif

[Setup]
AppId={{54F183C8-64D8-4B8C-8A47-F0B06B53080A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppName}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\..\outputs
OutputBaseFilename=3080Toolbox-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/fast
SolidCompression=yes
; The offline 7B model exceeds the size limit of a single Windows EXE.
DiskSpanning=yes
DiskSliceSize=2000000000
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription=本地图像处理、屏幕翻译与硬件检测工具箱

[Languages]
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "translation\models\Qwen3-4B-Instruct-2507-Q4_K_M.gguf"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "运行 {#MyAppName}"; Flags: nowait postinstall skipifsilent

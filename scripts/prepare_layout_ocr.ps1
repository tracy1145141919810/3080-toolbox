param([Parameter(Mandatory=$true)][string]$Python)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$dest = Join-Path $repo 'windows/runtime/layout_ocr'
$models = Join-Path $repo 'build/ocr-models'
New-Item -ItemType Directory -Force -Path $models | Out-Null
$files = @(
  @{path='det/ch_PP-OCRv5_det_mobile.onnx';sha='4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae'},
  @{path='rec/ch_PP-OCRv5_rec_mobile.onnx';sha='5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5'},
  @{path='rec/japan_PP-OCRv4_rec_mobile.onnx';sha='e1075a67dba758ecfc7ebc78a10ae61c95ac8fb66a9c86fab5541e33f085cb7a';version='PP-OCRv4'},
  @{path='cls/ch_ppocr_mobile_v2.0_cls_mobile.onnx';sha='e47acedf663230f8863ff1ab0e64dd2d82b838fceb5957146dab185a89d6215c';version='PP-OCRv4'}
)
foreach ($item in $files) {
  $file = Join-Path $models (Split-Path $item.path -Leaf)
  if (!(Test-Path -LiteralPath $file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.sha) {
    $version = if ($item.version) { $item.version } else { 'PP-OCRv5' }
    Invoke-WebRequest "https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.9.2/onnx/$version/$($item.path)" -OutFile $file
  }
  if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.sha) { throw "Model hash mismatch: $file" }
}
& $Python -m PyInstaller --noconfirm --onedir --console --name layout_ocr --collect-all rapidocr --collect-all onnxruntime --distpath (Split-Path $dest -Parent) --workpath (Join-Path $repo 'build/ocr-freeze') --specpath (Join-Path $repo 'build') (Join-Path $PSScriptRoot 'layout_ocr.py')
if ($LASTEXITCODE -ne 0) { throw 'OCR build failed' }
$bundledModels = Join-Path $dest 'models'
New-Item -ItemType Directory -Force -Path $bundledModels | Out-Null
foreach ($item in $files) {
  Copy-Item -LiteralPath (Join-Path $models (Split-Path $item.path -Leaf)) -Destination $bundledModels -Force
}

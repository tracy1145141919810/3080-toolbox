param(
 [Parameter(Mandatory=$true)][string]$RuntimeSource,
 [Parameter(Mandatory=$true)][string]$ModelSource,
 [Parameter(Mandatory=$true)][string]$OcrPythonEnvironment
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$destination = Join-Path $repo 'windows/runtime/translation'
$licenses = Join-Path $destination 'licenses'
$modelName = 'Hy-MT2-7B-Q4_K_M.gguf'
$expected = '9f96256500f3fc1ab4d64336b58f52a949a95ad7516b0c229476eef782f9f77b'
if ((Get-FileHash -LiteralPath $ModelSource -Algorithm SHA256).Hash -ne $expected) {
 throw 'Unexpected Hy-MT2 model checksum'
}
foreach ($name in @('llama-server.exe','llama-server-impl.dll','llama.dll','llama-common.dll','ggml.dll','ggml-base.dll','ggml-cuda.dll','cublas64_12.dll','cublasLt64_12.dll','cudart64_12.dll')) {
 if (!(Test-Path -LiteralPath (Join-Path $RuntimeSource $name))) { throw "Missing runtime: $name" }
}
New-Item -ItemType Directory -Force -Path $destination,$licenses,(Join-Path $destination 'models') | Out-Null
# The server's native libraries include CPU variants for non-CUDA computers.
Get-ChildItem -LiteralPath $RuntimeSource -Filter '*.dll' -File | ForEach-Object {
 Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
}
Copy-Item -LiteralPath (Join-Path $RuntimeSource 'llama-server.exe') -Destination $destination -Force
Copy-Item -LiteralPath $ModelSource -Destination (Join-Path $destination "models/$modelName") -Force
Copy-Item -LiteralPath (Join-Path $RuntimeSource 'LICENSE-LLVM-OpenMP') -Destination $licenses -Force
$licenseSources = @{
 'llama.cpp-LICENSE.txt'='https://raw.githubusercontent.com/ggml-org/llama.cpp/b10793/LICENSE'
 'Hy-MT2-LICENSE.txt'='https://huggingface.co/tencent/Hy-MT2-7B-GGUF/raw/ab8472660ac61fac25f1af43fac2599d52a8a775/LICENSE.txt'
 'RapidOCR-LICENSE.txt'='https://raw.githubusercontent.com/RapidAI/RapidOCR/v3.9.2/LICENSE'
 'PaddleOCR-LICENSE.txt'='https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/LICENSE'
 'Python-LICENSE.txt'='https://raw.githubusercontent.com/python/cpython/v3.12.14/LICENSE'
 'CUDA-EULA.html'='https://docs.nvidia.com/cuda/archive/12.4.1/eula/index.html'
}
foreach ($entry in $licenseSources.GetEnumerator()) {
 Invoke-WebRequest -Uri $entry.Value -OutFile (Join-Path $licenses $entry.Key)
}
Copy-Item -LiteralPath (Join-Path $repo 'assets/fonts/OFL.txt') -Destination (Join-Path $licenses 'Noto-OFL.txt') -Force
$sitePackages = Join-Path $OcrPythonEnvironment 'Lib/site-packages'
foreach ($package in (Get-ChildItem -LiteralPath $sitePackages -Directory -Filter '*.dist-info')) {
 foreach ($license in (Get-ChildItem -LiteralPath $package.FullName -Recurse -File | Where-Object { $_.Name -match '^(LICENSE|LICENCE|COPYING|NOTICE|AUTHORS)' })) {
  $relative = $license.FullName.Substring($package.FullName.Length + 1)
  $target = Join-Path $licenses "python-packages/$($package.Name)/$relative"
  New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
  Copy-Item -LiteralPath $license.FullName -Destination $target -Force
 }
}
if ((Get-FileHash -LiteralPath (Join-Path $destination "models/$modelName") -Algorithm SHA256).Hash -ne $expected) {
 throw 'Staged model verification failed'
}
Write-Output "Full offline translation runtime staged: $destination"

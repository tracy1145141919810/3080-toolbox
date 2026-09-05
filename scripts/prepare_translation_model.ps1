param([Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference = 'Stop'
$name = 'Hy-MT2-7B-Q4_K_M.gguf'
$expected = '9f96256500f3fc1ab4d64336b58f52a949a95ad7516b0c229476eef782f9f77b'
$revision = 'ab8472660ac61fac25f1af43fac2599d52a8a775'
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$file = Join-Path $Destination $name
if (!(Test-Path -LiteralPath $file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $expected) {
  $partial = "$file.partial"
  & curl.exe --fail --location --retry 5 --continue-at - --output $partial "https://huggingface.co/tencent/Hy-MT2-7B-GGUF/resolve/$revision/$name"
  if ($LASTEXITCODE -ne 0) { throw 'Model download failed; the partial download is retained for resume' }
  if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $expected) { throw 'Downloaded Hy-MT2 checksum mismatch' }
  Move-Item -LiteralPath $partial -Destination $file -Force
}
if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $expected) {
  throw 'Hy-MT2 model checksum does not match the official Hugging Face artifact'
}
Invoke-WebRequest "https://huggingface.co/tencent/Hy-MT2-7B-GGUF/raw/$revision/LICENSE.txt" -OutFile (Join-Path $Destination 'Hy-MT2-LICENSE.txt')

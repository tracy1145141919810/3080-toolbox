param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$release = Join-Path $repo 'build/windows/x64/runner/Release'
$version = '1.8.1'
$root = "3080Toolbox-Portable-$version"
$model = 'translation/models/Hy-MT2-7B-Q4_K_M.gguf'
$expected = '9f96256500f3fc1ab4d64336b58f52a949a95ad7516b0c229476eef782f9f77b'
if (Test-Path -LiteralPath $Output) { throw 'Refusing to overwrite an existing portable archive' }
foreach ($file in @('toolbox_3080.exe','flutter_windows.dll','msvcp140.dll','vcruntime140.dll','imagemagick/magick.exe','imagemagick/vcomp140.dll','translation/llama-server.exe','translation/msvcp140.dll','layout_ocr/layout_ocr.exe',$model)) {
 if (!(Test-Path -LiteralPath (Join-Path $release $file))) { throw "Missing portable component: $file" }
}
if ((Get-FileHash -LiteralPath (Join-Path $release $model) -Algorithm SHA256).Hash -ne $expected) {
 throw 'The bundled translation model failed checksum verification'
}
$exeVersion = (Get-Item -LiteralPath (Join-Path $release 'toolbox_3080.exe')).VersionInfo.ProductVersion
if ($exeVersion -notlike "$version*") { throw "Wrong application version: $exeVersion" }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($Output, [IO.Compression.ZipArchiveMode]::Create)
try {
 foreach ($file in (Get-ChildItem -LiteralPath $release -Recurse -File)) {
  $relative = $file.FullName.Substring($release.Length + 1).Replace('\','/')
  # Ignore the previous build's default model if it remains in an incremental build.
  if ($relative -eq 'translation/models/Qwen3-4B-Instruct-2507-Q4_K_M.gguf') { continue }
  if ($file.Extension -in @('.log','.pdb')) { continue }
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,"$root/$relative",[IO.Compression.CompressionLevel]::Fastest) | Out-Null
 }
 foreach ($file in @('PORTABLE_README.txt','README.md','THIRD_PARTY_NOTICES.md')) {
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $repo $file),"$root/$file",[IO.Compression.CompressionLevel]::Fastest) | Out-Null
 }
} finally { $archive.Dispose() }
# Verify archive structure and the decompressed model, not just its source file.
$archive = [IO.Compression.ZipFile]::OpenRead($Output)
try {
 if ($archive.Entries.FullName -like '*Qwen3-4B*.gguf') { throw 'Old Qwen model unexpectedly included' }
 $entry = $archive.GetEntry("$root/$model")
 if ($null -eq $entry -or $entry.Length -ne 4624648896) { throw 'Invalid model entry in portable archive' }
 $stream = $entry.Open()
 $sha = [Security.Cryptography.SHA256]::Create()
 try { $actual = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
 finally { $stream.Dispose(); $sha.Dispose() }
 if ($actual -ne $expected) { throw 'Archived model failed checksum verification' }
 Write-Output "Verified portable archive: $($archive.Entries.Count) files; Hy-MT2 model SHA-256 matches"
} finally { $archive.Dispose() }
Get-Item -LiteralPath $Output | Select-Object FullName,Length

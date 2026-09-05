param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (Test-Path -LiteralPath $Output) { throw 'Refusing to overwrite an existing source archive' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
Push-Location $repo
try {
 $files = & git -c core.quotepath=false ls-files --cached --others --exclude-standard
 if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate source files' }
 $archive = [IO.Compression.ZipFile]::Open($Output, [IO.Compression.ZipArchiveMode]::Create)
 try {
  foreach ($relative in $files) {
   $source = Join-Path $repo $relative
   if (Test-Path -LiteralPath $source -PathType Leaf) {
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$source,"3080-toolbox/$relative",[IO.Compression.CompressionLevel]::Optimal) | Out-Null
   }
  }
 } finally { $archive.Dispose() }
} finally { Pop-Location }
Get-Item -LiteralPath $Output | Select-Object FullName,Length

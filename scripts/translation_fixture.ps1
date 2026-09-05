param([Parameter(Mandatory=$true)][string]$Output)
Add-Type -AssemblyName System.Drawing
$image = New-Object Drawing.Bitmap 1200,320
$g = [Drawing.Graphics]::FromImage($image)
$g.Clear([Drawing.Color]::White)
$g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$title = New-Object Drawing.Font 'Segoe UI',26,([Drawing.FontStyle]::Bold)
$body = New-Object Drawing.Font 'Segoe UI',23
$brush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(24,34,48))
$g.DrawString('Software update', $title, $brush, 35,25)
$g.DrawString('Please save your changes before closing this window.', $body, $brush,35,90)
$g.DrawString('Do not turn off the computer during the update.', $body, $brush,35,145)
$g.DrawString('Your files will not be deleted.', $body, $brush,35,200)
$image.Save($Output, [Drawing.Imaging.ImageFormat]::Png)
$brush.Dispose(); $body.Dispose(); $title.Dispose(); $g.Dispose(); $image.Dispose()

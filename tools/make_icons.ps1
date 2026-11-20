# Eski Android sürümleri (8.0 öncesi) için "A" monogram PNG simgelerini üretir.
Add-Type -AssemblyName System.Drawing
$res = Join-Path $PSScriptRoot '..\android\app\src\main\res'
$sizes = @{ 'mipmap-mdpi' = 48; 'mipmap-hdpi' = 72; 'mipmap-xhdpi' = 96; 'mipmap-xxhdpi' = 144; 'mipmap-xxxhdpi' = 192 }

function P($x, $y, $s) { New-Object System.Drawing.PointF((($x - 18) * $s), (($y - 18) * $s)) }

foreach ($dir in $sizes.Keys) {
    $n = $sizes[$dir]
    $s = $n / 72.0
    $bmp = New-Object System.Drawing.Bitmap $n, $n
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)

    $r = $n * 0.22
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, 2 * $r, 2 * $r, 180, 90)
    $path.AddArc($n - 2 * $r - 1, 0, 2 * $r, 2 * $r, 270, 90)
    $path.AddArc($n - 2 * $r - 1, $n - 2 * $r - 1, 2 * $r, 2 * $r, 0, 90)
    $path.AddArc(0, $n - 2 * $r - 1, 2 * $r, 2 * $r, 90, 90)
    $path.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#0F6E56'))), $path)

    foreach ($stroke in @(
        @{ c = '#FFFFFF'; w = 8.5; pts = @(@(36, 80), @(54, 31), @(72, 80)) },
        @{ c = '#FAC775'; w = 6.5; pts = @(@(43, 61), @(51, 69), @(68, 50)) })) {
        $pen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml($stroke.c)), ($stroke.w * $s)
        $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
        $pts = [System.Drawing.PointF[]]($stroke.pts | ForEach-Object { P $_[0] $_[1] $s })
        $g.DrawLines($pen, $pts)
    }
    $out = Join-Path $res "$dir\ic_launcher.png"
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host "$dir -> $n px"
}

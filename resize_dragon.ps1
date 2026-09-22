param([string]$dir)
Add-Type -AssemblyName System.Drawing
$files = Get-ChildItem "$dir\*_dragon.png"
foreach ($f in $files) {
    $base = $f.BaseName
    if ($base -like "*_thumb" -or $base -like "*_large") { continue }
    $thumb = "$dir\$($base)_thumb.png"
    $large = "$dir\$($base)_large.png"
    if ($f.Length -le 500) {
        if (Test-Path $thumb) { Remove-Item $thumb -Force }
        if (Test-Path $large) { Remove-Item $large -Force }
        continue
    }
    $needThumb = (-not (Test-Path $thumb)) -or ($f.LastWriteTime -gt (Get-Item $thumb).LastWriteTime)
    $needLarge = (-not (Test-Path $large)) -or ($f.LastWriteTime -gt (Get-Item $large).LastWriteTime)
    if ($needThumb -or $needLarge) {
        try {
            $src = [System.Drawing.Image]::FromFile($f.FullName)
            if ($src.Width -lt 100 -or $src.Height -lt 50) {
                $src.Dispose()
                if (Test-Path $thumb) { Remove-Item $thumb -Force }
                if (Test-Path $large) { Remove-Item $large -Force }
                continue
            }
            if ($needThumb) {
                $bm1 = New-Object System.Drawing.Bitmap(320, 120)
                $g1 = [System.Drawing.Graphics]::FromImage($bm1)
                $g1.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g1.DrawImage($src, 0, 0, 320, 120)
                $bm1.Save($thumb, [System.Drawing.Imaging.ImageFormat]::Png)
                $g1.Dispose(); $bm1.Dispose()
            }
            if ($needLarge) {
                $bm2 = New-Object System.Drawing.Bitmap(960, 361)
                $g2 = [System.Drawing.Graphics]::FromImage($bm2)
                $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g2.DrawImage($src, 0, 0, 960, 361)
                $bm2.Save($large, [System.Drawing.Imaging.ImageFormat]::Png)
                $g2.Dispose(); $bm2.Dispose()
            }
            $src.Dispose()
        } catch {}
    }
}

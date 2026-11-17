# Скачивает встроенные движки для Windows в app\engines\ (их упакует установщик).
#   powershell -ExecutionPolicy Bypass -File scripts\fetch-engines.ps1
#
# Последние версии определяются автоматически. Каждый движок необязателен:
# если один не скачался, сборка продолжится, а Morph предложит доустановить его в «Компонентах».

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$engines = Join-Path $root 'app\engines'
$bin = Join-Path $engines 'bin'
$tmp = Join-Path $env:TEMP 'morph-engines'
New-Item -ItemType Directory -Force $bin, $tmp | Out-Null
$headers = @{ 'User-Agent' = 'morph-build' }
if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }

function Get-Archive($url, $name) {
  $file = Join-Path $tmp $name
  Write-Host "↓ $url"
  Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -Headers @{ 'User-Agent' = 'morph-build' }
  $dir = Join-Path $tmp ($name -replace '\.[^.]+$', '')
  Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $dir | Out-Null
  # tar.exe (bsdtar) из Windows 10/11 распаковывает и zip, и 7z
  tar -xf $file -C $dir
  return $dir
}
function Get-LatestAsset($repo, $pattern) {
  $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers $headers
  ($rel.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1).browser_download_url
}
function Step($name, [scriptblock]$body) {
  try { & $body; Write-Host "✓ ${name}" } catch { Write-Warning "✗ ${name}: $($_.Exception.Message)" }
}

Step 'FFmpeg' {
  # Сборка BtbN (GPL, с x264/x265/libvpx/libwebp/libaom)
  $url = Get-LatestAsset 'BtbN/FFmpeg-Builds' 'ffmpeg-n\d.*-win64-gpl-\d.*\.zip$'
  if (-not $url) { $url = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip' }
  $d = Get-Archive $url 'ffmpeg.zip'
  Get-ChildItem $d -Recurse -Include ffmpeg.exe, ffprobe.exe | Copy-Item -Destination $bin -Force
}

Step 'ImageMagick' {
  # Портативная сборка из релизов ImageMagick на GitHub (без установщика и записей в реестре)
  $url = Get-LatestAsset 'ImageMagick/ImageMagick' 'portable-Q16-x64\.(7z|zip)$'
  if (-not $url) { $url = Get-LatestAsset 'ImageMagick/ImageMagick' 'portable-Q16-HDRI-x64\.(7z|zip)$' }
  if (-not $url) { throw 'не найден portable-архив в релизах' }
  $d = Get-Archive $url ("magick." + ($url -replace '.*\.', ''))
  if (-not (Test-Path (Join-Path $d 'magick.exe'))) {
    $inner = Get-ChildItem $d -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName 'magick.exe') } | Select-Object -First 1
    if ($inner) { $d = $inner.FullName }
  }
  $mdir = Join-Path $engines 'magick'
  Remove-Item -Recurse -Force $mdir -ErrorAction SilentlyContinue
  Copy-Item -Recurse $d $mdir
  & (Join-Path $mdir 'magick.exe') -version | Select-Object -First 1
}

Step 'qpdf' {
  $url = Get-LatestAsset 'qpdf/qpdf' 'msvc64\.zip$'
  $d = Get-Archive $url 'qpdf.zip'
  Get-ChildItem $d -Recurse -File | Where-Object { $_.DirectoryName -match '\\bin$' } | Copy-Item -Destination $bin -Force
}

Step 'Poppler' {
  $url = Get-LatestAsset 'oschwartz10612/poppler-windows' '^Release-.*\.zip$'
  $d = Get-Archive $url 'poppler.zip'
  Get-ChildItem $d -Recurse -File | Where-Object { $_.DirectoryName -match '\\Library\\bin$' } | Copy-Item -Destination $bin -Force
}

Get-ChildItem $engines -Recurse -Include ffplay.exe, *.pdb | Remove-Item -Force -ErrorAction SilentlyContinue
$mb = [math]::Round(((Get-ChildItem $engines -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB)
Write-Host "Движки: $mb МБ в $engines"
Get-ChildItem $bin -Filter *.exe | ForEach-Object { Write-Host "  $($_.Name)" }

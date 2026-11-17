# Сборка пункта нового контекстного меню Windows 11 (выполняется в CI или на ПК с Visual Studio Build Tools).
# Результат: integrations\windows\dist\ — MorphContextMenu.dll, MorphContextMenu.msix, Morph.cer
#
#   powershell -ExecutionPolicy Bypass -File integrations\windows\build-modern-menu.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $root 'modern-menu'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

# 1. Найти инструменты Windows SDK и MSVC
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Нужны Visual Studio Build Tools с компонентом C++' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$sdkBin = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.*\x64" | Sort-Object Name -Descending | Select-Object -First 1
$makeappx = Join-Path $sdkBin.FullName 'makeappx.exe'
$signtool = Join-Path $sdkBin.FullName 'signtool.exe'

# 2. Компиляция DLL
$cl = "cl /nologo /std:c++17 /EHsc /O2 /MT /LD /utf-8 `"$src\MorphContextMenu.cpp`" /link /DEF:`"$src\MorphContextMenu.def`" /OUT:`"$dist\MorphContextMenu.dll`" user32.lib shell32.lib ole32.lib shlwapi.lib runtimeobject.lib"
cmd /c "`"$vcvars`" >nul && $cl"
if ($LASTEXITCODE -ne 0) { throw 'Не удалось скомпилировать MorphContextMenu.dll' }

# 3. Пакет (только манифест и логотип — остальные файлы во внешнем расположении)
$pkg = Join-Path $dist 'pkg'
Remove-Item -Recurse -Force $pkg -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$pkg\Assets" | Out-Null
Copy-Item "$src\AppxManifest.xml" $pkg
Copy-Item (Join-Path $root '..\..\app\src-tauri\icons\128x128.png') "$pkg\Assets\logo.png"
& $makeappx pack /o /d $pkg /nv /p "$dist\MorphContextMenu.msix"
if ($LASTEXITCODE -ne 0) { throw 'makeappx завершился с ошибкой' }

# 4. Самоподписанный сертификат (издатель должен совпадать с Publisher в манифесте)
$cert = New-SelfSignedCertificate -Type Custom -Subject 'CN=Morph Local' -KeyUsage DigitalSignature `
  -FriendlyName 'Morph Local' -CertStoreLocation 'Cert:\CurrentUser\My' `
  -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
$pwd = ConvertTo-SecureString -String 'morph' -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "$dist\Morph.pfx" -Password $pwd | Out-Null
Export-Certificate -Cert $cert -FilePath "$dist\Morph.cer" | Out-Null
& $signtool sign /fd SHA256 /f "$dist\Morph.pfx" /p morph "$dist\MorphContextMenu.msix"
if ($LASTEXITCODE -ne 0) { throw 'signtool завершился с ошибкой' }
Remove-Item "$dist\Morph.pfx"
Write-Host "Готово: $dist"

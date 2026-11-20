# Asistan'ı derleyip bağlı telefona kurar ve açar.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

flutter build apk --debug
if ($LASTEXITCODE -ne 0) { throw "Derleme başarısız" }

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb install -r build\app\outputs\flutter-apk\app-debug.apk
& $adb shell am start -n com.ibrahim.jarvis_asistan/.MainActivity | Out-Null
Write-Host "Kuruldu ve açıldı."

# Builds a signed release APK for one client and runs the release gate.
#
#   powershell -ExecutionPolicy Bypass -File tool\android\build_release.ps1 -Client insideout-casa
#
# Asks for the keystore password (hidden); it is passed only to this build.
# Output: dist\<client>\DailyExpenseTracker-<client>-<version>.apk
param(
  [string]$Client = 'insideout-casa'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repo
if (Test-Path 'C:\Bibin\_tools\env.ps1') { . 'C:\Bibin\_tools\env.ps1' }

$config = "config\clients\$Client.json"
if (-not (Test-Path $config)) { throw "No client config $config" }
if (-not (Test-Path 'android\key.properties')) {
  throw 'android\key.properties missing - run tool\android\create_release_key.ps1 first.'
}

$askedForPassword = $false
if (-not $env:DET_STORE_PASSWORD) {
  $sec = Read-Host -AsSecureString 'Keystore password'
  $env:DET_STORE_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  $askedForPassword = $true
}
$ErrorActionPreference = 'Continue'   # flutter/dart print progress on stderr
try {
  flutter build apk --release --dart-define-from-file=$config
  if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
} finally {
  if ($askedForPassword) { Remove-Item Env:\DET_STORE_PASSWORD -ErrorAction SilentlyContinue }
}

$apk = 'build\app\outputs\flutter-apk\app-release.apk'
dart run tool/release_check.dart --apk $apk --config $config 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Release check FAILED - do not distribute this APK.' }

$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value).Trim().Replace('+', '-build')
$outDir = "dist\$Client"
New-Item -ItemType Directory -Force $outDir | Out-Null
$out = "$outDir\DailyExpenseTracker-$Client-$version.apk"
Copy-Item $apk $out -Force
$hash = (Get-FileHash $out -Algorithm SHA256).Hash
Write-Host ''
Write-Host "Signed release APK: $out" -ForegroundColor Green
Write-Host "File SHA-256: $hash"

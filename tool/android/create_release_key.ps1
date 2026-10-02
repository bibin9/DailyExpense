# Creates the Android release signing key for Daily Expense Tracker (BCR).
# Run ONCE. Every future update must be signed with this same key.
#
#   powershell -ExecutionPolicy Bypass -File tool\android\create_release_key.ps1
#
# - The keystore is created OUTSIDE the repository.
# - You choose the password; it is typed hidden and never written to disk.
# - android/key.properties gets only the keystore path and alias (git-ignored).
param(
  [string]$KeystorePath = "$env:USERPROFILE\.bcr-det\signing\bcr-release.keystore",
  [string]$Alias = 'bcr-release',
  [string]$DName = 'CN=BCR (BibinCutRiver), O=BCR, C=AE'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Find-Keytool {
  if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\keytool.exe")) { return "$env:JAVA_HOME\bin\keytool.exe" }
  if (Test-Path 'C:\Bibin\_tools\jdk21\bin\keytool.exe') { return 'C:\Bibin\_tools\jdk21\bin\keytool.exe' }
  $cmd = Get-Command keytool -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw 'keytool not found. Install a JDK or set JAVA_HOME.'
}

if (Test-Path $KeystorePath) {
  throw "A keystore already exists at $KeystorePath. Refusing to overwrite it: replacing the key would stop every installed copy from updating."
}
$keytool = Find-Keytool

Write-Host ''
Write-Host 'Daily Expense Tracker - create release signing key' -ForegroundColor Cyan
Write-Host "Keystore: $KeystorePath"
Write-Host "Alias:    $Alias"
Write-Host "Owner:    $DName"
Write-Host ''
Write-Host 'Choose a strong password (at least 12 characters). Write it down and keep it'
Write-Host 'with the keystore backup - if either is lost, the app can never be updated.'
Write-Host ''

if ($env:DET_STORE_PASSWORD) {
  $plain = $env:DET_STORE_PASSWORD   # non-interactive use (automation/testing)
} else {
  $p1 = Read-Host -AsSecureString 'Password'
  $p2 = Read-Host -AsSecureString 'Repeat password'
  $toPlain = { param($s) [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)) }
  $plain = & $toPlain $p1
  if ($plain -ne (& $toPlain $p2)) { throw 'The two passwords do not match. Nothing was created.' }
}
if ($plain.Length -lt 12) { throw 'Password must be at least 12 characters. Nothing was created.' }

New-Item -ItemType Directory -Force (Split-Path -Parent $KeystorePath) | Out-Null
$env:DET_KS_PW = $plain
# keytool reports progress on stderr; judge it by exit code, not stderr.
$ErrorActionPreference = 'Continue'
try {
  # PKCS12 keystore (one password for store and key), RSA 4096, ~27 years.
  & $keytool -genkeypair -noprompt -storetype PKCS12 -keystore $KeystorePath `
    -alias $Alias -keyalg RSA -keysize 4096 -validity 10000 -dname $DName `
    '-storepass:env' DET_KS_PW '-keypass:env' DET_KS_PW 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $KeystorePath)) { throw 'keytool failed; no key was created.' }
  $listing = & $keytool -list -v -keystore $KeystorePath -alias $Alias '-storepass:env' DET_KS_PW 2>&1 | ForEach-Object { "$_" }
} finally {
  $ErrorActionPreference = 'Stop'
  Remove-Item Env:\DET_KS_PW -ErrorAction SilentlyContinue
  $plain = $null
}

$propsPath = Join-Path $repo 'android\key.properties'
@(
  '# Release signing (git-ignored). Passwords are deliberately NOT stored here:'
  '# tool/android/build_release.ps1 asks for them at build time.'
  "storeFile=$($KeystorePath.Replace('\', '/'))"
  "keyAlias=$Alias"
) | Set-Content -Encoding ascii $propsPath

$sha256 = ($listing | Select-String 'SHA256:' | Select-Object -First 1).ToString().Trim()
$valid = ($listing | Select-String 'Valid from' | Select-Object -First 1).ToString().Trim()

Write-Host ''
Write-Host 'Release signing key created.' -ForegroundColor Green
Write-Host "  Keystore:  $KeystorePath"
Write-Host "  Certificate $sha256"
Write-Host "  $valid"
Write-Host "  Wrote:     $propsPath (path + alias only)"
Write-Host ''
Write-Host 'DO THIS NOW:' -ForegroundColor Yellow
Write-Host '  1. Copy the keystore file to two safe offline places (e.g. encrypted USB + a safe).'
Write-Host '  2. Store the password separately (e.g. a password manager).'
Write-Host '  3. Keep the SHA-256 above - Android developer verification asks for it.'

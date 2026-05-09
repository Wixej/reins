param(
  [string]$Flavor = "arm64-v8a"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$WorkspaceRoot = Resolve-Path (Join-Path $ProjectRoot "..\..")
$Flutter = Join-Path $WorkspaceRoot "flutter\bin\flutter.bat"
$Aapt = Join-Path $WorkspaceRoot "android-sdk\build-tools\35.0.0\aapt.exe"

$env:JAVA_HOME = Join-Path $WorkspaceRoot "jdk\current"
$env:ANDROID_HOME = Join-Path $WorkspaceRoot "android-sdk"
$env:ANDROID_SDK_ROOT = Join-Path $WorkspaceRoot "android-sdk"
$env:PUB_CACHE = Join-Path $WorkspaceRoot "pub-cache"

function Remove-DirectoryWithRetry([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      return
    } catch {
      if ($attempt -eq 5) {
        throw
      }

      Start-Sleep -Seconds 2
    }
  }
}

$pubspec = Get-Content -LiteralPath (Join-Path $ProjectRoot "pubspec.yaml") -Encoding UTF8
$versionLine = $pubspec | Where-Object { $_ -match "^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$" } | Select-Object -First 1
if (-not $versionLine) {
  throw "Cannot read version from pubspec.yaml"
}

$versionName = $Matches[1]
$buildSuffix = [int]$Matches[2]
$flutterBuildNumber = 2000 + $buildSuffix

Push-Location $ProjectRoot
try {
  $gradlew = Join-Path $ProjectRoot "android\gradlew.bat"
  if (Test-Path -LiteralPath $gradlew) {
    & $gradlew --stop
  }

  & $Flutter clean

  $buildDir = Join-Path $ProjectRoot "build"
  Remove-DirectoryWithRetry $buildDir

  & $Flutter pub get
  & $Flutter analyze
  & $Flutter build apk --release --split-per-abi --build-name=$versionName --build-number=$flutterBuildNumber

  $sourceApk = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-$Flavor-release.apk"
  if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "Built APK not found: $sourceApk"
  }

  $targetApk = Join-Path $WorkspaceRoot "app-release-v$versionName-build$buildSuffix-offline-ai-tts-clean-arm64.apk"
  Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force

  & $Aapt dump badging $targetApk | Select-String -Pattern "package:|native-code"
  Get-FileHash -LiteralPath $targetApk -Algorithm SHA1
  Get-Item -LiteralPath $targetApk | Select-Object FullName, Length, LastWriteTime
} finally {
  Pop-Location
}

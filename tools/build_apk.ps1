#!/usr/bin/env pwsh
# build_apk.ps1 — One-command phone build for Waifu Card Collector
# Godot 4.7, Android, debug keystore, adb install + monkey screenshot.

# ---------------------------------------------------------------------------
# Godot / SDK paths (update these if your tool locations change)
# ---------------------------------------------------------------------------
$GodotExe      = "E:/AI/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"
$AndroidSdk    = "E:/AI/Tools/Android/sdk"
$JavaSdk       = "E:/AI/Tools/jdk17"
$DebugKeystore = "E:/AI/Tools/Android/debug.keystore"

# ---------------------------------------------------------------------------
# Helper: write a single TOML -like key into Godot editor_settings-4.7.tres
# ---------------------------------------------------------------------------
function Write-GodotEditorSetting {
    param(
        [string]$Key,
        [string]$Value
    )
    $SettingsPath = "$env:APPDATA\Godot\editor_settings-4.7.tres"

    # Read existing file if it exists
    $Content = @()
    if (Test-Path $SettingsPath) {
        $Content = Get-Content -Path $SettingsPath -Raw -Encoding utf8
    }

    # Replace or add the key. Godot uses dotted keys like "export/android/android_sdk_path"
    # The file is effectively TOML with ; comments and = assignments.
    $Pattern = "^#?${Key}\s*="
    $NewLine = "${Key} = \"${Value}\""

    # If key exists, replace; otherwise append
    if ($Content -match "(?m)^${Key}\s*=") {
        $Content = $Content -replace "(?m)^${Key}\s*=", $NewLine}
    else {
        # Append at the end (before the final newline if any)
        if (-not $Content.EndsWith("`n")) { $Content += "`n" }
        $Content += $NewLine
    }

    $Content | Set-Content -Path $SettingsPath -Encoding utf8
}

# ---------------------------------------------------------------------------
# Step 0: Parse switches
# ---------------------------------------------------------------------------
$WindowsOnly = $false
if ($args -contains "-Windows") {
    $WindowsOnly = $true
}

if ($WindowsOnly) {
    Write-Host ">>> Exporting Windows Desktop build..."
    & "$GodotExe" --headless --path client --export-debug "Windows Desktop" "build/waifu.exe"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Godot Windows export failed (exit code $LASTEXITCODE)."
        exit 1
    }
    if (-not (Test-Path "build/waifu.exe")) {
        Write-Error "APK/EXE not found at build/waifu.exe."
        exit 1
    }
    Write-Host ">>> Windows Desktop build complete: build/waifu.exe"
    exit 0
}

# ---------------------------------------------------------------------------
# Step 1: Set env vars and Godot editor SDK/JDK paths
# ---------------------------------------------------------------------------
Write-Host ">>> Setting Godot Android export environment..."

# Set keystore env vars that Godot 4 reads at export time
$env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = $DebugKeystore
$env:GODOT_ANDROID_KEYSTORE_DEBUG_USER  = "androiddebugkey"
$env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = "android"

# Write SDK paths into Godot editor settings (only these two keys)
Write-GodotEditorSetting -Key "export/android/android_sdk_path" -Value $AndroidSdk
Write-GodotEditorSetting -Key "export/android/java_sdk_path" -Value $JavaSdk

Write-Host "    Godot editor settings updated."

# ---------------------------------------------------------------------------
# Step 2: Headless import + Android debug export
# ---------------------------------------------------------------------------
Write-Host ">>> Running Godot headless import..."
& "$GodotExe" --headless --path client --import
if ($LASTEXITCODE -ne 0) {
    Write-Error "Godot headless import failed (exit code $LASTEXITCODE). Check for SCRIPT ERROR or Parse Error."
    exit 1
}

Write-Host ">>> Exporting Android debug APK..."
& "$GodotExe" --headless --path client --export-debug "Android" "build/waifu-debug.apk"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Godot Android export failed (exit code $LASTEXITCODE). Check output for ERROR: lines."
    exit 1
}

if (-not (Test-Path "build/waifu-debug.apk")) {
    Write-Error "Exported APK not found at build/waifu-debug.apk."
    exit 1
}
Write-Host "    Android debug APK built: build/waifu-debug.apk"

# ---------------------------------------------------------------------------
# Step 3: Check for connected device via adb
# ---------------------------------------------------------------------------
Write-Host ">>> Checking for connected Android device..."
$adbResult = & "E:/AI/Tools/Android/sdk/platform-tools/adb.exe" devices
# Parse the output: first line is "List of devices", second line is the device entry
$deviceLines = $adbResult -split "`n" | Where-Object { $_ -match "^[^\s]" }
if ($deviceLines.Count -lt 1 -or $deviceLines[0] -notmatch "List") {
    Write-Error "Plug in the phone (USB debugging on) and run again"
    exit 1
}
# Check if a device is listed (skip the header line)
$hasDevice = $deviceLines | Where-Object { $_ -match "^([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\tdevice" -or $_ -match "\tdevice$" }
if (-not $hasDevice) {
    Write-Error "Plug in the phone (USB debugging on) and run again"
    exit 1
}
Write-Host "    Android device detected."

# ---------------------------------------------------------------------------
# Step 4: Install APK + monkey test + screenshot
# ---------------------------------------------------------------------------
Write-Host ">>> Installing APK..."
& "E:/AI/Tools/Android/sdk/platform-tools/adb.exe" install -r "build/waifu-debug.apk"
if ($LASTEXITCODE -ne 0) {
    Write-Error "ADB install failed. The APK may have an issue."
    exit 1
}

Write-Host ">>> Running monkey test (1 event, 15 s timeout)..."
& "E:/AI/Tools/Android/sdk/platform-tools/adb.exe" shell monkey -p com.waifudev.cardcollector 1
Start-Sleep -Seconds 15

Write-Host ">>> Capturing phone screenshot..."
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$screenshotsDir = Join-Path "pipeline" "shots" "phone"
if (-not (Test-Path $screenshotsDir)) {
    mkdir -Item $screenshotsDir -Force
}
$outPath = Join-Path $screenshotsDir "phone_$timestamp.png"
& "E:/AI/Tools/Android/sdk/platform-tools/adb.exe" exec-out screencap -p > "$outPath"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to capture screencap."
    exit 1
}
Write-Host "    Screenshot saved to: $outPath"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ">>> Build complete. APK installed, monkey test done, screenshot captured."
Write-Host "    APK:      build/waifu-debug.apk"
Write-Host "    Screenshot: $outPath"
exit 0
param(
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

function Write-Header {
    Clear-Host
    Write-Host "Android ADB/Fastboot Toolkit" -ForegroundColor Cyan
    Write-Host "For devices you own or are authorized to service. No lock/FRP bypass." -ForegroundColor DarkGray
    Write-Host ""
}

function Suspend-Toolkit {
    if (-not $NoPause) {
        Write-Host ""
        Read-Host "Press Enter to continue" | Out-Null
    }
}

function Get-ToolPath {
    param([Parameter(Mandatory)][string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $wingetPlatformTools = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\$Name.exe"
    if (Test-Path -LiteralPath $wingetPlatformTools) {
        return $wingetPlatformTools
    }

    return $null
}

function Invoke-Tool {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $path = Get-ToolPath $Tool
    if (-not $path) {
        throw "$Tool was not found. Install Android Platform Tools first."
    }

    & $path @Arguments
}

function Test-AndroidTools {
    Write-Host "Checking Android tools..." -ForegroundColor Yellow
    foreach ($tool in @("adb", "fastboot")) {
        $path = Get-ToolPath $tool
        if ($path) {
            Write-Host "${tool}: $path" -ForegroundColor Green
            Invoke-Tool $tool @("version")
        }
        else {
            Write-Host "${tool}: missing" -ForegroundColor Red
        }
        Write-Host ""
    }
}

function Confirm-Danger {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Phrase
    )

    Write-Host ""
    Write-Host $Message -ForegroundColor Red
    Write-Host "Type $Phrase to continue." -ForegroundColor Yellow
    $answer = Read-Host "Confirm"
    return $answer -eq $Phrase
}

function Read-ExistingPath {
    param([Parameter(Mandatory)][string]$Prompt)

    $path = Read-Host $Prompt
    $resolved = Resolve-Path -LiteralPath $path -ErrorAction SilentlyContinue
    if (-not $resolved) {
        throw "Path not found: $path"
    }
    return $resolved.Path
}

function Show-AdbDevices {
    Invoke-Tool adb @("devices", "-l")
}

function Show-FastbootDevices {
    Invoke-Tool fastboot @("devices")
}

function Show-DeviceInfo {
    Write-Host "Device state:" -ForegroundColor Yellow
    Invoke-Tool adb @("get-state")
    Write-Host ""

    $props = @(
        "ro.product.manufacturer",
        "ro.product.model",
        "ro.product.device",
        "ro.build.version.release",
        "ro.build.version.sdk",
        "ro.build.fingerprint",
        "ro.bootloader",
        "ro.boot.verifiedbootstate"
    )

    foreach ($prop in $props) {
        Write-Host "$prop = " -NoNewline
        Invoke-Tool adb @("shell", "getprop", $prop)
    }
}

function Install-Apk {
    $apk = Read-ExistingPath "APK path"
    Invoke-Tool adb @("install", "-r", $apk)
}



function Push-ToDevice {
    $local = Read-ExistingPath "Local file/folder path"
    $remote = Read-Host "Phone destination path, for example /sdcard/Download/"
    Invoke-Tool adb @("push", $local, $remote)
}

function Save-Logcat {
    $logDir = Join-Path $PSScriptRoot "android-logs"
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logPath = Join-Path $logDir "logcat-$stamp.txt"
    Write-Host "Capturing logcat. Press Ctrl+C to stop." -ForegroundColor Yellow
    Invoke-Tool adb @("logcat", "-v", "time") | Tee-Object -FilePath $logPath
}



function Show-FastbootInfo {
    Invoke-Tool fastboot @("getvar", "all")
}











function New-ToolkitOutputDir {
    param([Parameter(Mandatory)][string]$Name)

    $dir = Join-Path $PSScriptRoot $Name
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    return $dir
}

function Restart-AdbServer {
    Invoke-Tool adb @("kill-server")
    Invoke-Tool adb @("start-server")
    Invoke-Tool adb @("devices", "-l")
}

function Open-AdbShell {
    Write-Host "Opening adb shell. Type exit to return to this toolkit." -ForegroundColor Yellow
    Invoke-Tool adb @("shell")
}

function Show-AdbDiagnostics {
    Write-Host "Battery:" -ForegroundColor Yellow
    Invoke-Tool adb @("shell", "dumpsys", "battery")
    Write-Host ""
    Write-Host "Storage:" -ForegroundColor Yellow
    Invoke-Tool adb @("shell", "df", "-h")
}

function Save-Bugreport {
    $dir = New-ToolkitOutputDir "android-logs"
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $path = Join-Path $dir "bugreport-$stamp.zip"
    Write-Host "Creating bugreport. This can take several minutes." -ForegroundColor Yellow
    Invoke-Tool adb @("bugreport", $path)
    Write-Host "Saved to $path" -ForegroundColor Green
}

function Save-Screenshot {
    $dir = New-ToolkitOutputDir "android-captures"
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $remote = "/sdcard/toolkit-screenshot-$stamp.png"
    $local = Join-Path $dir "screenshot-$stamp.png"

    Invoke-Tool adb @("shell", "screencap", "-p", $remote)
    Invoke-Tool adb @("pull", $remote, $local)
    Invoke-Tool adb @("shell", "rm", "-f", $remote)
    Write-Host "Saved to $local" -ForegroundColor Green
}



function Backup-AccessibleStorage {
    $dir = New-ToolkitOutputDir "android-backups"
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $dir "backup-$stamp"
    New-Item -ItemType Directory -Path $backupDir | Out-Null

    Write-Host "This backs up normal accessible storage only. It cannot read locked or protected app data." -ForegroundColor Yellow
    $paths = @(
        "/sdcard/DCIM",
        "/sdcard/Download",
        "/sdcard/Pictures",
        "/sdcard/Documents",
        "/sdcard/Movies",
        "/sdcard/Music"
    )

    foreach ($path in $paths) {
        Write-Host "Pulling $path..." -ForegroundColor Cyan
        Invoke-Tool adb @("pull", $path, $backupDir)
    }

    Write-Host "Backup saved to $backupDir" -ForegroundColor Green
}



function Uninstall-Package {
    $packageName = Read-Host "Package name, for example com.example.app"
    if ([string]::IsNullOrWhiteSpace($packageName)) {
        throw "Package name is required."
    }

    $ok = Confirm-Danger "This uninstalls an app for the current user/device." "UNINSTALL"
    if (-not $ok) {
        Write-Host "Canceled."
        return
    }

    Invoke-Tool adb @("uninstall", $packageName)
}



function Show-FastbootLockInfo {
    Invoke-Tool fastboot @("getvar", "unlocked")
    Invoke-Tool fastboot @("flashing", "get_unlock_ability")
}

while ($true) {
    Write-Header
    Write-Host "1. Check ADB/Fastboot tools"
    Write-Host "2. List ADB devices"
    Write-Host "3. Read Android device info"
    Write-Host "4. Reboot via ADB"
    Write-Host "5. Install APK"
    Write-Host "6. Pull files from phone"
    Write-Host "7. Push files to phone"
    Write-Host "8. Capture logcat"
    Write-Host "9. List Fastboot devices"
    Write-Host "10. Read Fastboot info"
    Write-Host "11. Flash image with Fastboot"
    Write-Host "12. Boot image temporarily"
    Write-Host "13. Sideload OTA ZIP"
    Write-Host "14. Factory reset with Fastboot"
    Write-Host "15. Reboot from Fastboot"
    Write-Host "16. Restart ADB server"
    Write-Host "17. Open ADB shell"
    Write-Host "18. Battery and storage diagnostics"
    Write-Host "19. Save bugreport ZIP"
    Write-Host "20. Take screenshot"
    Write-Host "21. Record screen"
    Write-Host "22. Backup accessible storage"
    Write-Host "23. List installed packages"
    Write-Host "24. Uninstall package"
    Write-Host "25. Remount system if allowed"
    Write-Host "26. Fastboot lock/unlock status"
    Write-Host "0. Exit"
    Write-Host ""

    $choice = Read-Host "Choose"

    try {
        switch ($choice) {
            "1" { Test-AndroidTools }
            "2" { Show-AdbDevices }
            "3" { Show-DeviceInfo }
            "4" { Reboot-Adb }
            "5" { Install-Apk }
            "6" { Pull-FromDevice }
            "7" { Push-ToDevice }
            "8" { Save-Logcat }
            "9" { Show-FastbootDevices }
            "10" { Show-FastbootInfo }
            "11" { Flash-Image }
            "12" { Boot-Image }
            "13" { Sideload-Ota }
            "14" { Factory-ResetFastboot }
            "15" { Reboot-Fastboot }
            "16" { Restart-AdbServer }
            "17" { Open-AdbShell }
            "18" { Show-AdbDiagnostics }
            "19" { Save-Bugreport }
            "20" { Save-Screenshot }
            "21" { Record-Screen }
            "22" { Backup-AccessibleStorage }
            "23" { List-Packages }
            "24" { Uninstall-Package }
            "25" { Remount-SystemIfAllowed }
            "26" { Show-FastbootLockInfo }
            "0" { break }
            default { Write-Host "Invalid choice." -ForegroundColor Red }
        }
    }
    catch {
        Write-Host ""
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }

    Suspend-Toolkit
}

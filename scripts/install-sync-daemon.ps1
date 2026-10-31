# -*- coding: utf-8 -*-
# OpenTokenUsage 本機零接觸自適應同步守護進程安裝腳本 (Windows Zero-Touch Installer)
# 支援 Windows 開機自啟動與背景靜默執行

param(
    [switch]$Uninstall,
    [switch]$Status
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DaemonPy = Join-Path $ScriptDir "sync-desktop-daemon.py"
$PythonDir = Split-Path (Get-Command python -ErrorAction SilentlyContinue).Source -Parent
$PythonwExe = Join-Path $PythonDir "pythonw.exe"
if (-not (Test-Path $PythonwExe)) { $PythonwExe = (Get-Command python).Source }

$StartupDir = [Environment]::GetFolderPath("Startup")
$LauncherVbs = Join-Path $StartupDir "OpenTokenUsageSyncDaemon.vbs"

# 狀態檢查
if ($Status) {
    Write-Host "=== OpenTokenUsage 同步守護進程狀態檢查 ===" -ForegroundColor Cyan
    $proc = Get-CimInstance Win32_Process -Filter "Name LIKE python%" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*sync-desktop-daemon.py*"
    }
    if ($proc) {
        Write-Host "[運行中] 守護進程正在背景執行 (PID: $($proc.ProcessId))" -ForegroundColor Green
    } else {
        Write-Host "[未運行] 守護進程當前未在背景執行" -ForegroundColor Yellow
    }

    if (Test-Path $LauncherVbs) {
        Write-Host "[開機自啟] 已在 Startup 啟動項目中註冊: $LauncherVbs" -ForegroundColor Green
    } else {
        Write-Host "[開機自啟] 尚未註冊為開機自啟動" -ForegroundColor Gray
    }
    exit 0
}

# 解除安裝
if ($Uninstall) {
    Write-Host "[解除安裝] 正在移除 OpenTokenUsage 同步守護進程開機自啟動..." -ForegroundColor Yellow
    if (Test-Path $LauncherVbs) {
        Remove-Item -Path $LauncherVbs -Force
        Write-Host "[成功] 已移除開機自啟動啟動腳本" -ForegroundColor Green
    }
    # 終止運行中程序
    Get-CimInstance Win32_Process -Filter "Name LIKE python%" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.CommandLine -like "*sync-desktop-daemon.py*") {
            Stop-Process -Id $_.ProcessId -Force
            Write-Host "[終止] 已停止 PID $($_.ProcessId) 守護進程" -ForegroundColor Green
        }
    }
    exit 0
}

# 安裝開機自啟動 VBS 靜默啟動器 (無黑視窗彈出，使用 pythonw.exe)
$VbsContent = "Set WshShell = CreateObject(""WScript.Shell"")" + [Environment]::NewLine + "WshShell.Run Chr(34) & """ + $PythonwExe + """ & Chr(34) & "" "" & Chr(34) & """ + $DaemonPy + """ & Chr(34), 0, False"
[System.IO.File]::WriteAllText($LauncherVbs, $VbsContent, [System.Text.Encoding]::ASCII)
Write-Host "[安裝成功] 開機自啟動腳本已寫入: $LauncherVbs" -ForegroundColor Green

# 立即在背景啟動一次 (靜默啟動)
$running = Get-CimInstance Win32_Process -Filter "Name LIKE python%" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*sync-desktop-daemon.py*"
}

if (-not $running) {
    Start-Process -FilePath "wscript.exe" -ArgumentList "`"$LauncherVbs`""
    Write-Host "[立即啟動] 已在背景啟動同步守護進程" -ForegroundColor Green
} else {
    Write-Host "[提示] 守護進程已在背景運行中 (PID: $($running.ProcessId))" -ForegroundColor Cyan
}

Write-Host "==========================================================" -ForegroundColor DarkGray
Write-Host "零接觸保證：只要電腦開機且有網路，本機快取異動將自動同步至雲端！" -ForegroundColor Cyan

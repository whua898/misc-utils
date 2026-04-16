# 清理 CapabilityAccessManager.db-wal 文件
# 建议设置为计划任务,每周执行一次
# 需要管理员权限

$ErrorActionPreference = "Stop"

Write-Host "=== 清理 CapabilityAccessManager WAL 文件 ===" -ForegroundColor Cyan
Write-Host ""

# 可能的文件路径
$possiblePaths = @(
    "C:\ProgramData\Microsoft\Windows\CapabilityAccessManager",
    "C:\ProgramData\Microsoft\Windows\AppRepository",
    "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Windows\AppRepository",
    "C:\Users\*\AppData\Local\Microsoft\Windows\AppRepository"
)

$walFiles = @()

# 查找所有 WAL 文件
foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $files = Get-ChildItem "$path\CapabilityAccessManager.db-wal" -ErrorAction SilentlyContinue
        if ($files) {
            $walFiles += $files
        }
    }
}

if ($walFiles.Count -eq 0) {
    Write-Host "未找到 CapabilityAccessManager.db-wal 文件" -ForegroundColor Green
    exit 0
}

Write-Host "找到 $($walFiles.Count) 个 WAL 文件:" -ForegroundColor Yellow
foreach ($file in $walFiles) {
    $sizeMB = [math]::Round($file.Length / 1MB, 2)
    Write-Host "  $($file.FullName)" -ForegroundColor Gray
    Write-Host "    大小: $sizeMB MB" -ForegroundColor $(if($sizeMB -gt 100){"Red"}else{"Green"})
}
Write-Host ""

# 检查文件大小阈值
$thresholdMB = 100  # 超过100MB才清理
$needCleanup = $false

foreach ($file in $walFiles) {
    if ($file.Length / 1MB -gt $thresholdMB) {
        $needCleanup = $true
        break
    }
}

if (-not $needCleanup) {
    Write-Host "所有 WAL 文件都小于 ${thresholdMB}MB,无需清理" -ForegroundColor Green
    exit 0
}

Write-Host "警告: 发现超过 ${thresholdMB}MB 的 WAL 文件,开始清理..." -ForegroundColor Yellow
Write-Host ""

# 步骤1: 停止 CamSvc 服务
Write-Host "[1/4] 停止 Capability Access Manager 服务..." -ForegroundColor Green
try {
    Stop-Service -Name "CamSvc" -Force -ErrorAction Stop
    Start-Sleep -Seconds 2
    Write-Host "  ✓ 服务已停止" -ForegroundColor Green
} catch {
    Write-Host "  ✗ 停止服务失败: $_" -ForegroundColor Red
    Write-Host "  提示: 请以管理员身份运行此脚本" -ForegroundColor Yellow
    exit 1
}

# 步骤2: 备份主数据库文件
Write-Host "[2/4] 备份数据库文件..." -ForegroundColor Green
foreach ($walFile in $walFiles) {
    $dbFile = $walFile.FullName -replace "\.db-wal$", ".db"
    $shmFile = $walFile.FullName -replace "\.db-wal$", ".db-shm"
    
    if (Test-Path $dbFile) {
        $backupFile = "$dbFile.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        try {
            Copy-Item $dbFile $backupFile -Force
            Write-Host "  ✓ 已备份: $backupFile" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠ 备份失败: $_" -ForegroundColor Yellow
        }
    }
}

# 步骤3: 删除 WAL 和 SHM 文件
Write-Host "[3/4] 删除 WAL 和 SHM 文件..." -ForegroundColor Green
foreach ($walFile in $walFiles) {
    $shmFile = $walFile.FullName -replace "\.db-wal$", ".db-shm"
    
    try {
        if (Test-Path $walFile.FullName) {
            Remove-Item $walFile.FullName -Force
            Write-Host "  ✓ 已删除: $($walFile.FullName)" -ForegroundColor Green
        }
        
        if (Test-Path $shmFile) {
            Remove-Item $shmFile -Force
            Write-Host "  ✓ 已删除: $shmFile" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ✗ 删除失败: $_" -ForegroundColor Red
    }
}

# 步骤4: 重启服务
Write-Host "[4/4] 重启服务..." -ForegroundColor Green
try {
    Start-Service -Name "CamSvc"
    Start-Sleep -Seconds 2
    
    $service = Get-Service -Name "CamSvc"
    if ($service.Status -eq "Running") {
        Write-Host "  ✓ 服务已重启并正常运行" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ 服务状态: $($service.Status)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ✗ 重启服务失败: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "清理完成!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "建议:" -ForegroundColor Yellow
Write-Host "1. 将此脚本添加到计划任务,每周执行一次" -ForegroundColor Gray
Write-Host "2. 监控 WAL 文件大小,如果频繁增长,可能需要检查系统日志" -ForegroundColor Gray
Write-Host "3. 备份文件位于原数据库同目录,确认无问题后可手动删除" -ForegroundColor Gray
Write-Host ""

# 显示清理后的状态
Write-Host "当前状态:" -ForegroundColor Cyan
foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $remainingWal = Get-ChildItem "$path\CapabilityAccessManager.db-wal" -ErrorAction SilentlyContinue
        if ($remainingWal) {
            $sizeMB = [math]::Round($remainingWal.Length / 1MB, 2)
            Write-Host "  $($remainingWal.FullName): $sizeMB MB" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")


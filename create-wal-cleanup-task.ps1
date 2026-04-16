# 创建定期清理 CapabilityAccessManager WAL 文件的计划任务
# 需要管理员权限运行
# 使用 -Force 参数可跳过确认提示

param(
    [switch]$Force  # 强制模式,跳过确认
)

$ErrorActionPreference = "Stop"

Write-Host "=== 创建 WAL 清理计划任务 ===" -ForegroundColor Cyan
Write-Host ""

$taskName = "Cleanup-CapabilityAccessManager-WAL"
$scriptPath = "$PSScriptRoot\cleanup-capability-wal.ps1"

# 检查脚本文件是否存在
if (-not (Test-Path $scriptPath)) {
    Write-Host "错误: 找不到清理脚本: $scriptPath" -ForegroundColor Red
    Write-Host "请确保 cleanup-capability-wal.ps1 在同一目录下" -ForegroundColor Yellow
    exit 1
}

Write-Host "配置信息:" -ForegroundColor Cyan
Write-Host "  任务名称: $taskName" -ForegroundColor Gray
Write-Host "  脚本路径: $scriptPath" -ForegroundColor Gray
Write-Host "  执行频率: 每周日凌晨2点" -ForegroundColor Gray
Write-Host "  运行身份: SYSTEM (最高权限)" -ForegroundColor Gray
Write-Host ""

# 如果不是强制模式,询问用户确认
if (-not $Force) {
    $response = Read-Host "是否创建此计划任务? (Y/N)"
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "已取消" -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "强制模式: 跳过确认" -ForegroundColor Yellow
}

# 删除已存在的任务
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "发现已存在的任务,正在删除..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "已删除旧任务" -ForegroundColor Green
}

# 创建触发器(每周日凌晨2点)
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am

# 创建操作
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
    -WorkingDirectory (Split-Path $scriptPath)

# 创建设置
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable:$false `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 5)

# 创建主体(以SYSTEM身份运行)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# 注册任务
try {
    Register-ScheduledTask -TaskName $taskName `
        -Trigger $trigger `
        -Action $action `
        -Settings $settings `
        -Principal $principal `
        -Description "定期清理 CapabilityAccessManager.db-wal 文件,防止磁盘空间占用过大" `
        -Force | Out-Null
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "✓ 计划任务创建成功!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "任务详情:" -ForegroundColor Cyan
    Write-Host "  名称: $taskName" -ForegroundColor Gray
    Write-Host "  下次运行时间: $( (Get-ScheduledTaskInfo $taskName).NextRunTime )" -ForegroundColor Gray
    Write-Host ""
    Write-Host "管理命令:" -ForegroundColor Yellow
    Write-Host "  查看任务: Get-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray
    Write-Host "  立即执行: Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray
    Write-Host "  禁用任务: Disable-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray
    Write-Host "  删除任务: Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false" -ForegroundColor Gray
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "✗ 创建任务失败: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "提示:" -ForegroundColor Yellow
    Write-Host "1. 请确保以管理员身份运行此脚本" -ForegroundColor Gray
    Write-Host "2. 或者手动在任务计划程序中创建任务" -ForegroundColor Gray
    exit 1
}

Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

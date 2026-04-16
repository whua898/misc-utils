# 迁移LogiOptionsPlus和Logishrd目录到D盘并创建软连接
# 需要管理员权限运行

$ErrorActionPreference = "Stop"

$sourceDirs = @(
    "C:\ProgramData\LogiOptionsPlus",
    "C:\ProgramData\Logishrd"
)

$targetBase = "D:\ProgramData"

Write-Host "=== 开始迁移Logitech目录到D盘 ===" -ForegroundColor Cyan

foreach ($sourceDir in $sourceDirs) {
    $dirName = Split-Path $sourceDir -Leaf
    $targetDir = Join-Path $targetBase $dirName
    
    Write-Host "`n处理目录: $sourceDir" -ForegroundColor Yellow
    
    # 检查源目录是否存在
    if (-not (Test-Path $sourceDir)) {
        Write-Host "源目录不存在，跳过: $sourceDir" -ForegroundColor Gray
        continue
    }
    
    # 如果已经是软连接，跳过
    $item = Get-Item $sourceDir
    if ($item.Attributes -match "ReparsePoint") {
        Write-Host "已经是软连接，跳过: $sourceDir" -ForegroundColor Gray
        continue
    }
    
    # 步骤1: 查找并终止占用该目录的进程
    Write-Host "检查占用进程..." -ForegroundColor Green
    
    # 使用handle工具或尝试常见进程
    $processesToCheck = @("LogiOptionsPlus", "LGHUB", "lghub_agent", "lghub_updater", "LogiOverlay")
    $killedProcesses = @()
    
    foreach ($procName in $processesToCheck) {
        $processes = Get-Process | Where-Object { $_.ProcessName -like "*$procName*" }
        foreach ($proc in $processes) {
            try {
                Write-Host "  终止进程: $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Yellow
                Stop-Process -Id $proc.Id -Force
                $killedProcesses += $proc
                Start-Sleep -Milliseconds 500
            } catch {
                Write-Host "  无法终止进程 $($proc.ProcessName): $_" -ForegroundColor Red
            }
        }
    }
    
    # 等待进程完全退出
    Start-Sleep -Seconds 2
    
    # 步骤2: 创建目标目录
    Write-Host "创建目标目录: $targetDir" -ForegroundColor Green
    if (-not (Test-Path $targetBase)) {
        New-Item -ItemType Directory -Path $targetBase -Force | Out-Null
    }
    
    # 步骤3: 复制数据到D盘
    Write-Host "复制数据..." -ForegroundColor Green
    if (Test-Path $targetDir) {
        Remove-Item $targetDir -Recurse -Force
    }
    
    try {
        Copy-Item -Path $sourceDir -Destination $targetBase -Recurse -Force
        Write-Host "数据复制成功" -ForegroundColor Green
    } catch {
        Write-Host "复制失败: $_" -ForegroundColor Red
        Write-Host "请确保没有进程占用该目录" -ForegroundColor Red
        
        # 尝试再次查找占用进程
        Write-Host "`n尝试使用资源监视器查找占用..." -ForegroundColor Yellow
        Write-Host "请手动关闭所有Logitech相关程序后重试" -ForegroundColor Red
        continue
    }
    
    # 验证复制是否成功
    if (-not (Test-Path $targetDir)) {
        Write-Host "目标目录验证失败，跳过软连接创建" -ForegroundColor Red
        continue
    }
    
    # 步骤4: 删除原目录
    Write-Host "删除原目录..." -ForegroundColor Green
    try {
        Remove-Item $sourceDir -Recurse -Force
        Write-Host "原目录已删除" -ForegroundColor Green
    } catch {
        Write-Host "删除原目录失败: $_" -ForegroundColor Red
        Write-Host "请手动删除原目录后重新运行脚本" -ForegroundColor Yellow
        
        # 即使删除失败，也继续创建软连接（如果原目录已被部分删除）
        if (Test-Path $sourceDir) {
            continue
        }
    }
    
    # 步骤5: 创建软连接
    Write-Host "创建软连接: $sourceDir -> $targetDir" -ForegroundColor Green
    try {
        New-Item -ItemType SymbolicLink -Path $sourceDir -Target $targetDir -Force | Out-Null
        Write-Host "软连接创建成功！" -ForegroundColor Green
        
        # 验证软连接
        $link = Get-Item $sourceDir
        if ($link.Attributes -match "ReparsePoint") {
            Write-Host "✓ 软连接验证通过" -ForegroundColor Green
        } else {
            Write-Host "✗ 软连接验证失败" -ForegroundColor Red
        }
    } catch {
        Write-Host "创建软连接失败: $_" -ForegroundColor Red
        Write-Host "请以管理员身份运行此脚本" -ForegroundColor Red
    }
}

Write-Host "`n=== 迁移完成 ===" -ForegroundColor Cyan
Write-Host "请重新启动Logitech相关程序以验证功能正常" -ForegroundColor Yellow

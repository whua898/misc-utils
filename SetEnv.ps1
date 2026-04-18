# ==========================================
# Professional Environment Variable Setter
# Uses .NET API to avoid setx 1024 char limit
# Requires Administrator privileges
# ==========================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Professional Environment Setup Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[错误] 请以管理员身份运行此脚本！" -ForegroundColor Red
    Write-Host "右键点击脚本 -> '以管理员身份运行'" -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "[✓] 管理员权限确认" -ForegroundColor Green
Write-Host ""

# ==========================================
# 1. Set JAVA Environment Variables (Machine Level)
# ==========================================
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "Step 1: Configuring Java Environment" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray

$javaPath = "D:\Program Files\Java\jre1.8.0_251"

if (Test-Path $javaPath) {
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $javaPath, "Machine")
    
    $classpath = ".;$javaPath\lib\dt.jar;$javaPath\lib\tools.jar"
    [Environment]::SetEnvironmentVariable("classpath", $classpath, "Machine")
    
    Write-Host "[成功] JAVA_HOME = $javaPath" -ForegroundColor Green
    Write-Host "[成功] classpath 已设置" -ForegroundColor Green
} else {
    Write-Host "[警告] Java 路径不存在: $javaPath" -ForegroundColor Yellow
    Write-Host "  请确认 Java 安装路径是否正确" -ForegroundColor Yellow
}

Write-Host ""

# ==========================================
# 3. Set Siemens Kasa Environment Variables (Machine Level)
# ==========================================
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "Step 3: Configuring Siemens Kasa Environment" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray

$kasaDir = "E:\Siemens\Kasa\NX10"
$kasaRoot = "E:\Siemens\Kasa"

if (Test-Path $kasaRoot) {
    [Environment]::SetEnvironmentVariable("KASA_DIR", $kasaDir, "Machine")
    [Environment]::SetEnvironmentVariable("KASA_ROOT", $kasaRoot, "Machine")
    [Environment]::SetEnvironmentVariable("UGII_GROUP_DIR", $kasaDir, "Machine")
    
    Write-Host "[成功] KASA_DIR = $kasaDir" -ForegroundColor Green
    Write-Host "[成功] KASA_ROOT = $kasaRoot" -ForegroundColor Green
    Write-Host "[成功] UGII_GROUP_DIR = $kasaDir" -ForegroundColor Green
} else {
    Write-Host "[警告] Siemens Kasa 路径不存在: $kasaRoot" -ForegroundColor Yellow
    Write-Host "  请确认 Siemens Kasa 安装路径是否正确" -ForegroundColor Yellow
}

Write-Host ""

# ==========================================
# 4. Define paths to append (Python, Git, Java bin)
# ==========================================
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "Step 2: Preparing Path Entries" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray

$newPaths = @(
    "$javaPath\bin",
    "$javaPath\jre\bin",
    "D:\Program Files\Python313",
    "D:\Program Files\Python313\Scripts",
    "D:\Program Files\Git\bin",
    "D:\Program Files\Git\cmd",
    "D:\Program Files\Git\usr\bin"
)

Write-Host "待检查的路径数量: $($newPaths.Count)" -ForegroundColor Cyan
Write-Host ""

# ==========================================
# 5. Core Logic: Read, Deduplicate, Append
# ==========================================
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "Step 3: Processing System Path" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray

# Get current system Path from registry (Machine level)
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")

if (-not $currentPath) {
    Write-Host "[错误] 无法读取系统 Path 变量！" -ForegroundColor Red
    pause
    exit 1
}

Write-Host "当前 Path 长度: $($currentPath.Length) 字符" -ForegroundColor Cyan

# Split existing paths into array for comparison
$existingPaths = $currentPath -split ";" | Where-Object { $_ -ne "" }

Write-Host "现有 Path 条目数: $($existingPaths.Count)" -ForegroundColor Cyan
Write-Host ""

$toAdd = @()
$skipped = @()

foreach ($path in $newPaths) {
    # Normalize path for comparison (remove trailing backslash, case-insensitive)
    $cleanPath = $path.TrimEnd('\').ToLower()
    
    # Check if path already exists
    $exists = $false
    foreach ($existing in $existingPaths) {
        if ($existing.TrimEnd('\').ToLower() -eq $cleanPath) {
            $exists = $true
            break
        }
    }
    
    if (-not $exists) {
        $toAdd += $path
        Write-Host "[新增] $path" -ForegroundColor Green
    } else {
        $skipped += $path
        Write-Host "[忽略] $path (已存在)" -ForegroundColor Gray
    }
}

Write-Host ""

# ==========================================
# 6. Safe Write (No 1024 truncation risk)
# ==========================================
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "Step 4: Updating System Path" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray

if ($toAdd.Count -gt 0) {
    # Build updated path
    $updatedPath = $currentPath.TrimEnd(';') + ";" + ($toAdd -join ";")
    
    Write-Host "新增路径数量: $($toAdd.Count)" -ForegroundColor Green
    Write-Host "更新后 Path 长度: $($updatedPath.Length) 字符" -ForegroundColor Cyan
    
    # Safety check
    if ($updatedPath.Length -gt 2048) {
        Write-Host ""
        Write-Host "[警告] Path 长度超过 2048 字符！" -ForegroundColor Yellow
        Write-Host "  虽然不会截断，但建议清理无用路径" -ForegroundColor Yellow
        $confirm = Read-Host "  是否继续？(Y/N)"
        if ($confirm -ne 'Y' -and $confirm -ne 'y') {
            Write-Host "操作已取消" -ForegroundColor Yellow
            pause
            exit 0
        }
    }
    
    # Write to registry using .NET API (no truncation!)
    try {
        [Environment]::SetEnvironmentVariable("Path", $updatedPath, "Machine")
        Write-Host ""
        Write-Host "[✓ 完成] 已成功追加 $($toAdd.Count) 条路径" -ForegroundColor Green
        Write-Host "  使用 .NET API 写入，无 1024 字符限制" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "[✗ 失败] 写入 Path 时出错: $_" -ForegroundColor Red
        pause
        exit 1
    }
} else {
    Write-Host "[提示] 所有路径均已存在，未做任何修改" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "新增路径: $($toAdd.Count)" -ForegroundColor Green
Write-Host "跳过路径: $($skipped.Count)" -ForegroundColor Gray
Write-Host "总路径数: $($existingPaths.Count + $toAdd.Count)" -ForegroundColor Cyan
Write-Host ""

if ($toAdd.Count -gt 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  ✓ Environment Setup Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "重要提示:" -ForegroundColor Yellow
    Write-Host "  1. 重启 PyCharm/VSCode 等 IDE 以生效" -ForegroundColor White
    Write-Host "  2. 重新打开终端窗口以加载新变量" -ForegroundColor White
    Write-Host "  3. 验证命令:" -ForegroundColor White
    Write-Host "     - java -version" -ForegroundColor Gray
    Write-Host "     - python --version" -ForegroundColor Gray
    Write-Host "     - git --version" -ForegroundColor Gray
} else {
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  ℹ No Changes Needed" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
}

Write-Host ""
pause

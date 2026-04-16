# 导出C盘所有软连接信息到JSON文件
# 用于备份软连接配置,便于日后恢复

$ErrorActionPreference = "Stop"

Write-Host "=== 导出C盘软连接信息 ===" -ForegroundColor Cyan
Write-Host ""

$outputFile = ".\symlinks-backup.json"

$symlinksList = @()

# 定义要扫描的目录
$scanPaths = @(
    "C:\ProgramData",
    "C:\Program Files",
    "C:\Program Files (x86)",
    "C:\Users\wh898",
    "C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\WindowsApps"
)

foreach ($scanPath in $scanPaths) {
    if (Test-Path $scanPath) {
        Write-Host "扫描: $scanPath" -ForegroundColor Green
        
        try {
            $items = Get-ChildItem $scanPath -Recurse -Attributes ReparsePoint -ErrorAction SilentlyContinue
            
            foreach ($item in $items) {
                $linkInfo = @{
                    Source = $item.FullName
                    Target = if ($item.Target) { $item.Target } else { "未知" }
                    Type = if ($item.PSIsContainer) { "Directory" } else { "File" }
                    ScanPath = $scanPath
                }
                $symlinksList += $linkInfo
            }
        } catch {
            Write-Host "  警告: 扫描 $scanPath 时出错: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  跳过: $scanPath (路径不存在)" -ForegroundColor Gray
    }
}

# 导出到JSON
if ($symlinksList.Count -gt 0) {
    $symlinksList | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding UTF8
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "导出完成!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "共发现 $($symlinksList.Count) 个软连接" -ForegroundColor Yellow
    Write-Host "已保存到: $PWD\$outputFile" -ForegroundColor Green
    Write-Host ""
    
    # 显示统计信息
    $dirLinks = ($symlinksList | Where-Object { $_.Type -eq "Directory" }).Count
    $fileLinks = ($symlinksList | Where-Object { $_.Type -eq "File" }).Count
    
    Write-Host "统计:" -ForegroundColor Cyan
    Write-Host "  目录链接: $dirLinks" -ForegroundColor Gray
    Write-Host "  文件链接: $fileLinks" -ForegroundColor Gray
    Write-Host ""
    
    # 按扫描路径分组显示
    Write-Host "分布情况:" -ForegroundColor Cyan
    $grouped = $symlinksList | Group-Object ScanPath
    foreach ($group in $grouped) {
        Write-Host "  $($group.Name): $($group.Count) 个" -ForegroundColor Gray
    }
    Write-Host ""
    
    Write-Host "提示:" -ForegroundColor Yellow
    Write-Host "  1. 将此JSON文件保存到安全位置(如云盘、U盘)" -ForegroundColor Gray
    Write-Host "  2. 系统重装后,可使用 restore-symlinks.ps1 脚本恢复" -ForegroundColor Gray
    Write-Host "  3. 或手动查看此JSON文件获取所有软连接信息" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "未发现任何软连接" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# 修复Windows局域网共享访问问题
# 需要管理员权限运行

$ErrorActionPreference = "Stop"

Write-Host "=== Windows局域网共享问题修复工具 ===" -ForegroundColor Cyan
Write-Host ""

# 步骤1: 检查网络配置文件类型
Write-Host "步骤1: 检查网络配置..." -ForegroundColor Yellow
$networkProfiles = Get-NetConnectionProfile
foreach ($profile in $networkProfiles) {
    Write-Host "  网络: $($profile.Name)" -ForegroundColor White
    Write-Host "  网络类别: $($profile.NetworkCategory)" -ForegroundColor $(if($profile.NetworkCategory -eq 'Private'){'Green'}else{'Yellow'})
    
    if ($profile.NetworkCategory -ne 'Private') {
        Write-Host "  ⚠ 检测到公共网络，正在修改为专用网络..." -ForegroundColor Yellow
        try {
            Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private
            Write-Host "  ✓ 已修改为专用网络" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ 修改失败: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "  ✓ 已是专用网络" -ForegroundColor Green
    }
}

Write-Host ""

# 步骤2: 启用网络发现和文件共享
Write-Host "步骤2: 启用网络发现和文件共享..." -ForegroundColor Yellow
try {
    # 启用网络发现
    Set-NetFirewallRule -DisplayGroup "网络发现" -Enabled True -Profile Private
    Write-Host "  ✓ 网络发现已启用" -ForegroundColor Green
    
    # 启用文件和打印机共享
    Set-NetFirewallRule -DisplayGroup "文件和打印机共享" -Enabled True -Profile Private
    Write-Host "  ✓ 文件和打印机共享已启用" -ForegroundColor Green
} catch {
    Write-Host "  ✗ 配置失败: $_" -ForegroundColor Red
}

Write-Host ""

# 步骤3: 检查SMB协议支持
Write-Host "步骤3: 检查SMB协议配置..." -ForegroundColor Yellow
try {
    $smb1 = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol"
    $smb2 = Get-SmbServerConfiguration | Select-Object EnableSMB2Protocol
    
    Write-Host "  SMB1协议: $($smb1.State)" -ForegroundColor $(if($smb1.State -eq 'Enabled'){'Yellow'}else{'Green'})
    Write-Host "  SMB2协议: $($smb2.EnableSMB2Protocol)" -ForegroundColor Green
    
    if ($smb1.State -eq 'Disabled') {
        Write-Host "  ℹ SMB1已禁用（推荐保持禁用状态以提高安全性）" -ForegroundColor Gray
    }
} catch {
    Write-Host "  ⚠ 无法获取SMB配置: $_" -ForegroundColor Yellow
}

Write-Host ""

# 步骤4: 检查相关服务状态
Write-Host "步骤4: 检查共享相关服务..." -ForegroundColor Yellow
$servicesToCheck = @(
    "LanmanServer",      # Server服务
    "LanmanWorkstation", # Workstation服务
    "mrxsmb20",          # SMB 2.0 MiniRedirector
    "bowser",            # Browser服务
    "fdPHost",           # Function Discovery Provider Host
    "FDResPub"           # Function Discovery Resource Publication
)

foreach ($serviceName in $servicesToCheck) {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        $status = if ($service.Status -eq 'Running') { '✓ 运行中' } else { '✗ 未运行' }
        $color = if ($service.Status -eq 'Running') { 'Green' } else { 'Red' }
        Write-Host "  $($service.DisplayName): $status" -ForegroundColor $color
        
        if ($service.Status -ne 'Running' -and $service.StartType -ne 'Disabled') {
            Write-Host "  正在启动服务..." -ForegroundColor Yellow
            try {
                Start-Service -Name $serviceName
                Write-Host "  ✓ 服务已启动" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ 启动失败: $_" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "  $serviceName : 未找到" -ForegroundColor Gray
    }
}

Write-Host ""

# 步骤5: 检查Guest账户状态
Write-Host "步骤5: 检查Guest账户配置..." -ForegroundColor Yellow
try {
    $guestAccount = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
    if ($guestAccount) {
        Write-Host "  Guest账户状态: $(if($guestAccount.Enabled){'启用'}else{'禁用'})" -ForegroundColor $(if($guestAccount.Enabled){'Yellow'}else{'Green'})
        
        if (-not $guestAccount.Enabled) {
            Write-Host "  ℹ Guest账户已禁用（推荐，更安全）" -ForegroundColor Gray
            Write-Host "  如需启用，请手动执行: Enable-LocalUser -Name Guest" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "  ⚠ 无法检查Guest账户: $_" -ForegroundColor Yellow
}

Write-Host ""

# 步骤6: 检查Windows凭据管理器
Write-Host "步骤6: 清理旧的共享凭据（可选）..." -ForegroundColor Yellow
Write-Host "  如果需要清除保存的错误密码，请手动操作:" -ForegroundColor Gray
Write-Host "  1. 打开'控制面板' > '凭据管理器'" -ForegroundColor Gray
Write-Host "  2. 选择'Windows凭据'" -ForegroundColor Gray
Write-Host "  3. 找到目标共享路径的凭据并删除" -ForegroundColor Gray
Write-Host "  4. 重新访问共享时输入正确的用户名和密码" -ForegroundColor Gray

Write-Host ""

# 步骤7: 提供访问建议
Write-Host "=== 修复完成 ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "现在请尝试以下操作:" -ForegroundColor Yellow
Write-Host ""
Write-Host "方法1: 使用IP地址访问（推荐）" -ForegroundColor White
Write-Host "  Win + R 输入: \\192.168.x.x\共享名" -ForegroundColor Gray
Write-Host ""
Write-Host "方法2: 使用计算机名访问" -ForegroundColor White
Write-Host "  Win + R 输入: \\Mzh2\111" -ForegroundColor Gray
Write-Host ""
Write-Host "方法3: 映射网络驱动器" -ForegroundColor White
Write-Host "  右键'此电脑' > '映射网络驱动器'" -ForegroundColor Gray
Write-Host "  输入: \\Mzh2\111" -ForegroundColor Gray
Write-Host ""
Write-Host "如果仍然无法访问，请检查:" -ForegroundColor Yellow
Write-Host "  1. 目标电脑(Mzh2)的防火墙设置" -ForegroundColor White
Write-Host "  2. 目标电脑的共享权限设置" -ForegroundColor White
Write-Host "  3. 目标电脑的用户账户密码" -ForegroundColor White
Write-Host "  4. 两台电脑是否在同一网段" -ForegroundColor White
Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

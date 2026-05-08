<#
.SYNOPSIS
    恢复 C 盘符号链接（重装系统后重建符号链接用）
.DESCRIPTION
    自动将 C 盘数据迁移到 D:/F: 等目标盘，创建目录符号链接。
    功能：跳过已存在的符号链接、自动检测锁定进程、智能恢复。
.NOTES
    需要管理员权限运行。
#>

#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$WhatIf
)

$ErrorActionPreference = "Continue"

# ── 辅助函数 ──────────────────────────────────────────────────────────────────

function Write-ProgressItem {
    param([int]$Index, [int]$Total, [string]$Desc)
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "[$Index/$Total] $Desc" -ForegroundColor Cyan
}

function Write-Status($Text, $Color = "Gray") {
    Write-Host "  $Text" -ForegroundColor $Color
}

# ── 1. 数据迁移（robocopy 封装） ──────────────────────────────────────────────

function Invoke-Robocopy {
    <#
    .SYNOPSIS
        使用 robocopy 拷贝目录，返回 $true/$false
    #>
    param(
        [string]$Source,
        [string]$Dest,
        [int]$Retry = 3,
        [int]$WaitSec = 5
    )

    # 确保目标目录存在
    $parent = Split-Path $Dest -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Write-Status "从源路径复制数据..." -Color Cyan
    Write-Status "来源: $Source" -Color Gray
    Write-Status "目标: $Dest" -Color Gray

    if ($WhatIf) {
        Write-Status "[DRY RUN] 模拟 robocopy 迁移" -Color Yellow
        return $true
    }

    try {
        # 直接调用 robocopy 以便捕获输出
        $output = & robocopy $Source.TrimEnd('\') $Dest.TrimEnd('\') `
            /E /COPY:DAT "/R:$Retry" "/W:$WaitSec" /NP /NFL /NDL 2>&1

        if ($LASTEXITCODE -lt 8) {
            Write-Status "[OK] 数据迁移完成" -Color Green
            return $true
        }

        Write-Status "[WARN] robocopy 退出码: $LASTEXITCODE" -Color Yellow
        Write-Status "  输出: $($output -join '; ')" -Color Gray
        return $false
    } catch {
        Write-Status "[FAIL] 迁移异常: $_" -Color Red
        return $false
    }
}

# ── 2. 进程/服务管控 ──────────────────────────────────────────────────────────

function Stop-LockingProcesses {
    <#
    .SYNOPSIS
        尝试终止锁定指定路径的进程与服务。
        返回 $true（即使部分失败也继续）。
    #>
    param([string]$Path)

    try {
        $stopped = @()
        $pathLower = $Path.ToLower()
        $patterns = @()

        # ── 根据路径关键词匹配进程名 ──
        $keywordMap = @(
            @('*siemens*', 'ug*', 'nx*', 'solid*', 'teamcenter*'),
            @('*logitech*', 'logi*', 'lghub*'),
            @('*adobe*', 'adobe*', 'photoshop*', 'illustrator*'),
            @('*autodesk*', 'autodesk*', 'acad*', 'revit*', 'adsk*', 'adskservice*'),
            @('*android*', 'adb*', 'android*', 'emulator*'),
            @('*fiddler*', 'fiddler*'),
            @('*lmstudio*', 'lmstudio*'),
            @('*cherry*', 'cherry*'),
            @('*claude*', 'claude*'),
            @('*cline*', 'cline*'),
            @('*gemini*', 'gemini*'),
            @('*qwen*', 'qwen*'),
            @('*google*', 'google*', 'chrome*', 'crashpad*'),
            @('*lingma*', 'lingma*', 'tongyi*', 'trae*'),
            # 编辑器/IDE：限制更精确避免误杀
            @('*visualstudio*', 'devenv*'),
            @('*pycharm*', 'pycharm*'),
            @('*idea*', 'idea*'),
            # 目录名本身包含 studio/code 的再检查
            @('*studio*', 'studio*'),
            @('*code*', 'code*')
        )

        foreach ($map in $keywordMap) {
            if ($pathLower -like $map[0]) {
                for ($i = 1; $i -lt $map.Count; $i++) {
                    $patterns += $map[$i]
                }
            }
        }

        # 始终检查 explorer
        $patterns += 'explorer'

        # 去重
        $patterns = $patterns | Select-Object -Unique

        foreach ($pattern in $patterns) {
            $procs = Get-Process -Name $pattern -ErrorAction SilentlyContinue
            foreach ($p in $procs) {
                # 跳过 explorer
                if ($p.ProcessName -eq 'explorer') { continue }

                try {
                    if (-not $WhatIf) {
                        Stop-Process -Id $p.Id -Force -ErrorAction Stop
                    }
                    Write-Status "已终止: $($p.ProcessName) (PID: $($p.Id))" -Color Gray
                    $stopped += $p.Id
                } catch {
                    # 忽略已退出的进程
                }
            }
        }

        if ($patterns.Count -eq 0) {
            Write-Status "[OK] 未检测到匹配的进程模式" -Color Green
        } elseif ($stopped.Count -gt 0) {
            Write-Status "已终止 $($stopped.Count) 个进程" -Color Cyan
        } else {
            Write-Status "未找到运行中的匹配进程" -Color Gray
        }

        # ── 停止相关 Windows 服务 ──
        $svcPatterns = @()
        if ($pathLower -like '*autodesk*') {
            $svcPatterns += 'AdskLicensing*', 'Autodesk*', 'FLEXnet*'
        }
        if ($pathLower -like '*siemens*' -or $pathLower -like '*solidedge*' -or $pathLower -like '*nx*') {
            $svcPatterns += 'Siemens*', 'SolidEdge*', 'NX*'
        }
        if ($pathLower -like '*logitech*') {
            $svcPatterns += 'Logi*', 'LGHUB*'
        }

        # 缓存所有服务信息，避免重复调用 Get-Service
        $allServices = Get-Service -ErrorAction SilentlyContinue
        foreach ($pattern in $svcPatterns) {
            $svc = $allServices | Where-Object { $_.Name -like $pattern } | Select-Object -First 1
            if ($svc -and $svc.Status -eq 'Running') {
                try {
                    Write-Status "停止服务: $($svc.DisplayName)..." -Color Gray
                    if (-not $WhatIf) {
                        Stop-Service -Name $svc.Name -Force -ErrorAction Stop
                        Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
                    }
                    Write-Status "[OK] 服务已停止" -Color Green
                    # 记录以便恢复
                    $script:stoppedServices[$svc.Name] = $svc.StartType
                } catch {
                    Write-Status "[WARN] 未能停止服务: $_" -Color Yellow
                }
            }
        }

        # 等 2 秒让句柄释放
        if ($stopped.Count -gt 0) {
            Start-Sleep -Seconds 2
        }

        return $true
    } catch {
        Write-Status "[WARN] 进程检测发生异常: $_" -Color Yellow
        return $true
    }
}

function Restore-Services {
    <#
    .SYNOPSIS
        恢复之前临时禁用的服务。
    #>
    if ($script:stoppedServices.Count -eq 0) { return }

    Write-Status "恢复 $($script:stoppedServices.Count) 个服务..." -Color Cyan
    foreach ($kv in $script:stoppedServices.GetEnumerator()) {
        try {
            Set-Service -Name $kv.Key -StartupType $kv.Value -ErrorAction SilentlyContinue
            Write-Status "  $($kv.Key) → $($kv.Value)" -Color Gray
        } catch {
            Write-Status "  [WARN] 恢复 $($kv.Key) 失败: $_" -Color Yellow
        }
    }
    $script:stoppedServices.Clear()
}

# ── 3. 强制删除目录（带重试+自动终止锁定进程） ─────────────────────────────────

function Remove-DirectoryWithForce {
    <#
    .SYNOPSIS
        递归删除目录，遇到锁定自动查杀进程后重试。
    .RETURNS
        $true 删除成功 / $false 最终失败
    #>
    param([string]$Path, [int]$MaxRetries = 3)

    if ($WhatIf) {
        Write-Status "[DRY RUN] 模拟删除: $Path" -Color Yellow
        return $true
    }

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
            Start-Sleep -Seconds 1
            return $true
        } catch {
            if ($i -eq $MaxRetries) {
                Write-Status "[FAIL] 重试 $MaxRetries 次后仍无法删除: $_" -Color Red
                return $false
            }
            Write-Status "[WARN] 第 $i 次删除失败: $_" -Color Yellow
            Write-Status "尝试终止锁定进程..." -Color Cyan
            Stop-LockingProcesses -Path $Path

            # Autodesk 特殊处理：taskkill 进程树
            if ($Path -like '*autodesk*') {
                Write-Status "强制终止 Autodesk 进程树..." -Color Cyan
                & taskkill /F /IM adskflex.exe /T 2>$null
                & taskkill /F /IM AdskAccessServiceHost.exe /T 2>$null
                & taskkill /F /IM AdskLicensingService.exe /T 2>$null
                Start-Sleep -Seconds 3
            } else {
                Start-Sleep -Seconds 2
            }
        }
    }
    return $false
}

# ── 4. 创建符号链接 ──────────────────────────────────────────────────────────

function New-SymlinkWithVerify {
    <#
    .SYNOPSIS
        创建目录符号链接并验证。
    .RETURNS
        $true 成功 / $false 失败
    #>
    param([string]$Source, [string]$Target)

    # 确保 Source 的父目录存在
    $parent = Split-Path $Source -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # 如果 Source 还存在，尝试清理
    if (Test-Path $Source) {
        Write-Status "源路径存在，尝试清理..." -Color Yellow
        Stop-LockingProcesses -Path $Source
        if (-not (Remove-DirectoryWithForce -Path $Source)) {
            return $false
        }
    }

    if ($WhatIf) {
        Write-Status "[DRY RUN] 模拟创建符号链接: $Source → $Target" -Color Yellow
        return $true
    }

    try {
        $item = New-Item -ItemType SymbolicLink -Path $Source -Target $Target -Force -ErrorAction Stop

        Start-Sleep -Milliseconds 300
        $verify = Get-Item $Source -ErrorAction Stop
        if ($verify.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Write-Status "[OK] 符号链接创建成功 → $($verify.Target)" -Color Green
            return $true
        }

        Write-Status "[FAIL] 验证失败：不是重解析点" -Color Red
        return $false
    } catch {
        Write-Status "[FAIL] 创建失败: $_" -Color Red
        Write-Status "  常见原因: 未以管理员运行 / 目标路径不存在 / 进程锁定" -Color Yellow
        return $false
    }
}

# ── 处理符号链接 ──────────────────────────────────────────────────────────────

function Process-SymlinkItem {
    param(
        [hashtable]$Link,
        [int]$Index,
        [int]$Total
    )

    Write-ProgressItem -Index $Index -Total $Total -Desc $Link.Desc
    Write-Status "来源: $($Link.Source)" -Color Green
    Write-Status "目标: $($Link.Target)" -Color Green

    # ─ 场景 A：已经是符号链接 ─
    if (Test-Path $Link.Source) {
        try {
            $item = Get-Item $Link.Source -ErrorAction Stop
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                Write-Status "状态: [跳过] 符号链接已存在" -Color Green
                return @{ Result = 'skip' }
            }
        } catch {
            # 路径存在但因权限无法读取属性，按真实目录处理
            Write-Status "无法读取路径属性，按真实目录处理" -Color Yellow
        }
    }

    # ─ 场景 B：源路径是真实目录 → 需要迁移 ─
    if (Test-Path $Link.Source) {
        Write-Status "源路径是真实目录，准备迁移..." -Color Yellow

        $targetExists = Test-Path $Link.Target
        $targetNotEmpty = $targetExists -and @(Get-ChildItem $Link.Target -ErrorAction SilentlyContinue).Count -gt 0

        if (-not $targetNotEmpty) {
            if (Invoke-Robocopy -Source $Link.Source -Dest $Link.Target) {
                $script:stats.migrate++
            }
        } else {
            Write-Status "目标路径已有数据，跳过复制" -Color Cyan
        }

        # 删除源目录（自动处理锁定）
        if (-not (Remove-DirectoryWithForce -Path $Link.Source)) {
            $script:stats.fail++
            return @{ Result = 'fail' }
        }

        # 创建符号链接
        if (New-SymlinkWithVerify -Source $Link.Source -Target $Link.Target) {
            $script:stats.success++
            return @{ Result = 'success' }
        } else {
            $script:stats.fail++
            return @{ Result = 'fail' }
        }
    }

    # ─ 场景 C：源路径不存在 → 直接创建符号链接 ─
    # 卷挂载由系统管理，跳过
    if ($Link.Target -like "Volume{*") {
        Write-Status "跳过卷挂载（由系统管理）" -Color Yellow
        $script:stats.skip++
        return @{ Result = 'skip' }
    }

    # 确保目标存在
    if (-not (Test-Path $Link.Target)) {
        Write-Status "目标路径不存在，创建目录..." -Color Yellow
        try {
            if (-not $WhatIf) {
                New-Item -ItemType Directory -Path $Link.Target -Force -ErrorAction Stop | Out-Null
            }
            Write-Status "[OK] 目录已创建" -Color Green
        } catch {
            Write-Status "[FAIL] 创建目录失败: $_" -Color Red
            $script:stats.fail++
            return @{ Result = 'fail' }
        }
    }

    if (New-SymlinkWithVerify -Source $Link.Source -Target $Link.Target) {
        $script:stats.success++
        return @{ Result = 'success' }
    } else {
        $script:stats.fail++
        return @{ Result = 'fail' }
    }
}

# ── 符号链接配置 ──────────────────────────────────────────────────────────────

$symlinks = @(
    # ProgramData 目录
    @{ Source = "C:\ProgramData\Intel Package Cache {1CEAC85D-2590-4760-800F-8DE5E91F3700}"; Target = "D:\ProgramData\Intel Package Cache"; Desc = "Intel Package Cache" }
    @{ Source = "C:\ProgramData\LogiOptionsPlus";              Target = "D:\ProgramData\LogiOptionsPlus";            Desc = "Logitech Options+ 数据" }
    @{ Source = "C:\ProgramData\Logishrd";                     Target = "D:\ProgramData\Logishrd";                   Desc = "Logitech 硬件驱动数据" }
    @{ Source = "C:\ProgramData\Microsoft\VisualStudio";       Target = "D:\ProgramData\Microsoft\VisualStudio";     Desc = "Visual Studio 共享数据" }
    @{ Source = "C:\ProgramData\Package Cache";                Target = "D:\ProgramData\Package Cache";              Desc = "Windows Installer 包缓存" }
    @{ Source = "C:\ProgramData\Tongyi";                       Target = "D:\ProgramData\Tongyi";                     Desc = "TRAE/Tongyi Lingma 共享数据" }

    # Program Files 目录
    @{ Source = "C:\Program Files\Common Files\Adobe\HelpCfg"; Target = "F:\Oftenused\adobe\Photoshop\App\Program Files\Common Files\Adobe\HelpCfg"; Desc = "Adobe 帮助配置" }
    @{ Source = "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\Current"; Target = "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\15.3.0.12981"; Desc = "Autodesk 许可服务" }
    @{ Source = "C:\Program Files (x86)\Common Files\Autodesk Shared"; Target = "D:\Program Files (x86)\Common Files\Autodesk Shared"; Desc = "Autodesk 共享组件" }
    @{ Source = "C:\Program Files (x86)\Microsoft";             Target = "D:\Program Files (x86)\Microsoft";          Desc = "Microsoft x86 应用数据" }

    # 用户目录 (wh898)
    @{ Source = "C:\Users\wh898\.ai_completion";               Target = "D:\Users\wh898\.ai_completion";             Desc = "AI 代码补全" }
    @{ Source = "C:\Users\wh898\.android";                     Target = "D:\Users\wh898\.android";                   Desc = "Android SDK/模拟器" }
    @{ Source = "C:\Users\wh898\.antigravity";                 Target = "D:\Users\wh898\.antigravity";               Desc = "Antigravity AI" }
    @{ Source = "C:\Users\wh898\.antigravity_tools";           Target = "D:\Users\wh898\.antigravity_tools";         Desc = "Antigravity 工具" }
    @{ Source = "C:\Users\wh898\.cache";                       Target = "D:\Users\wh898\.cache";                     Desc = "应用缓存" }
    @{ Source = "C:\Users\wh898\.claude-code-router";          Target = "D:\Users\wh898\.claude-code-router";        Desc = "Claude Code Router" }
    @{ Source = "C:\Users\wh898\.codex";                       Target = "D:\Users\wh898\.codex";                     Desc = "Codex AI" }
    @{ Source = "C:\Users\wh898\.config";                      Target = "D:\Users\wh898\.config";                    Desc = "应用配置" }
    @{ Source = "C:\Users\wh898\.cherrystudio";                Target = "D:\Users\wh898\.cherrystudio";              Desc = "Cherry Studio" }
    @{ Source = "C:\Users\wh898\.claude";                      Target = "D:\Users\wh898\.claude";                    Desc = "Claude AI" }
    @{ Source = "C:\Users\wh898\.cline";                       Target = "D:\Users\wh898\.cline";                     Desc = "Cline AI" }
    @{ Source = "C:\Users\wh898\.continue";                    Target = "D:\Users\wh898\.continue";                  Desc = "Continue 插件" }
    @{ Source = "C:\Users\wh898\.fiddler";                     Target = "D:\Users\wh898\.fiddler";                   Desc = "Fiddler 调试代理" }
    @{ Source = "C:\Users\wh898\.gemini";                      Target = "D:\Users\wh898\.gemini";                    Desc = "Google Gemini" }
    @{ Source = "C:\Users\wh898\.hvigor";                      Target = "D:\Users\wh898\.hvigor";                    Desc = "Hvigor (HarmonyOS)" }
    @{ Source = "C:\Users\wh898\.icube-remote-ssh";            Target = "D:\Users\wh898\.icube-remote-ssh";          Desc = "iCube 远程 SSH" }
    @{ Source = "C:\Users\wh898\.InstallAnywhere";             Target = "D:\Users\wh898\.InstallAnywhere";           Desc = "InstallAnywhere" }
    @{ Source = "C:\Users\wh898\.junie";                       Target = "D:\Users\wh898\.junie";                     Desc = "Junie AI" }
    @{ Source = "C:\Users\wh898\.lingma";                      Target = "D:\Users\wh898\.lingma";                    Desc = "通义灵码" }
    @{ Source = "C:\Users\wh898\.local";                       Target = "D:\Users\wh898\.local";                     Desc = "本地数据" }
    @{ Source = "C:\Users\wh898\.matplotlib";                  Target = "D:\Users\wh898\.matplotlib";                Desc = "Matplotlib 缓存" }
    @{ Source = "C:\Users\wh898\.lmstudio";                    Target = "D:\Users\wh898\.lmstudio";                  Desc = "LM Studio" }
    @{ Source = "C:\Users\wh898\AppData\Local\lm-studio-updater"; Target = "D:\Users\wh898\AppData\Local\lm-studio-updater"; Desc = "LM Studio 更新器" }
    @{ Source = "C:\Users\wh898\.ohpm";                        Target = "D:\Users\wh898\.ohpm";                      Desc = "OpenHarmony 包管理器" }
    @{ Source = "C:\Users\wh898\.qwen";                        Target = "D:\Users\wh898\.qwen";                      Desc = "通义千问" }
    @{ Source = "C:\Users\wh898\.trae-cn";                     Target = "D:\Users\wh898\.trae-cn";                   Desc = "TRAE Solo CN" }
    @{ Source = "C:\Users\wh898\.ssh";                         Target = "D:\Users\wh898\.ssh";                       Desc = "SSH 密钥" }
    @{ Source = "C:\Users\wh898\AppData\Local\Google";         Target = "D:\Users\wh898\AppData\Local\Google";       Desc = "Google/Chrome 数据" }
    @{ Source = "C:\Users\wh898\AppData\Local\Siemens";        Target = "D:\Users\wh898\AppData\Local\Siemens";      Desc = "Siemens 软件数据 (NX/Solid Edge)" }
    @{ Source = "C:\Users\wh898\PCManger\mdfs";                Target = "Volume{d6cc17c5-1733-4085-bce7-964f1e9f5de9}\"; Desc = "腾讯电脑管家卷挂载" }
)

# ── 统计变量 ──────────────────────────────────────────────────────────────────

$script:stoppedServices = @{}
$script:stats = @{
    success   = 0
    skip      = 0
    fail      = 0
    migrate   = 0
}

# ── 入口 ──────────────────────────────────────────────────────────────────────

Clear-Host
Write-Host "=== 恢复 C 盘符号链接 ===" -ForegroundColor Cyan
if ($WhatIf) {
    Write-Host "[预览模式] 不会执行实际更改" -ForegroundColor Magenta
}
Write-Host ""
Write-Host "共 $($symlinks.Count) 项待处理" -ForegroundColor Yellow
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
    .IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "管理员权限: $isAdmin" -ForegroundColor Cyan
Write-Host "模式: 自动迁移 C → D 并创建符号链接" -ForegroundColor Green
Write-Host ""

# ── 主循环（用 try/finally 保证服务恢复） ─────────────────────────────────────

try {
    foreach ($link in $symlinks) {
        $idx = [array]::IndexOf($symlinks, $link) + 1
        $null = Process-SymlinkItem -Link $link -Index $idx -Total $symlinks.Count
    }
} finally {
    # 无论成功失败，确保恢复被禁用的服务
    Restore-Services
}

# ── 汇总 ──────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "=== 恢复完成 ===" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "  成功创建: $($script:stats.success)"   -ForegroundColor Green
Write-Host "  已存在:   $($script:stats.skip)"      -ForegroundColor Yellow
Write-Host "  迁移数据: $($script:stats.migrate)"   -ForegroundColor Cyan
Write-Host "  失败:     $($script:stats.fail)"      -ForegroundColor Red
Write-Host ""

if ($script:stats.success -gt 0) { Write-Host "✓ 成功创建 $($script:stats.success) 个符号链接" -ForegroundColor Green }
if ($script:stats.fail -gt 0)    {
    Write-Host "⚠ 有 $($script:stats.fail) 个失败，请检查上方错误信息" -ForegroundColor Red
    Write-Host "  1. 以管理员身份运行"
    Write-Host "  2. 关闭使用中路径的应用"
    Write-Host "  3. 检查目标路径是否存在"
}
if ($script:stats.fail -eq 0)    { Write-Host "所有符号链接已成功恢复！" -ForegroundColor Green }

Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
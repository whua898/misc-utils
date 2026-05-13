<#
.SYNOPSIS
    恢复 C 盘符号链接（重装系统后重建符号链接用）
.DESCRIPTION
    从 symlinks.txt 读取源路径，自动将 C: 替换为 D: 作为目标，创建目录符号链接。
    功能：跳过已存在的符号链接、自动检测锁定进程、智能恢复、强制解锁。
    自动扫描用户目录下 . 开头的未链接目录并追加到 symlinks.txt。
    
    强制解锁功能：
    - 自动检测并终止锁定文件的进程
    - 支持激进模式（终止更多进程类型）
    - 尝试使用 Sysinternals handle.exe 关闭文件句柄
    - 多次重试机制（可配置）
    - 最后尝试使用 cmd rd 命令强制删除
.PARAMETER ForceUnlock
    启用最强解锁模式：
    - 精确检测锁定进程（handle.exe / openfiles / 模块扫描）
    - 显示详细的进程信息（名称、PID、路径）
    - 强制终止所有锁定进程
    - 尝试关闭文件句柄
    - 增加重试次数和等待时间
.PARAMETER MaxRetries
    最大重试次数，默认 5 次（最强模式建议 8-10 次）
.NOTES
    需要管理员权限运行。
.EXAMPLE
    # 标准模式
    .\restore-symlinks.ps1
    
    # 强制解锁模式
    .\restore-symlinks.ps1 -ForceUnlock
    
    # 自定义重试次数
    .\restore-symlinks.ps1 -MaxRetries 10
    
    # 预览模式（不执行实际操作）
    .\restore-symlinks.ps1 -WhatIf
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$WhatIf,
    [string]$ConfigFile = "",
    [switch]$ForceUnlock,  # 强制解锁模式
    [int]$MaxRetries = 5,   # 最大重试次数（默认5次）
    [switch]$ForceMode     # 强制模式：自动选择合并复制，不询问用户
)

$ErrorActionPreference = "Continue"

# 修复：-File 模式下 $PSScriptRoot 可能为空，用脚本所在目录兜底
if (-not $ConfigFile) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ConfigFile = Join-Path $scriptDir "symlinks.txt"
}

# ── 辅助函数 ──────────────────────────────────────────────────────────────────

function Write-ProgressItem {
    param([int]$Index, [int]$Total, [string]$Desc)
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "[$Index/$Total] $Desc" -ForegroundColor Cyan
}

function Write-Status($Text, $Color = "Gray") {
    Write-Host "  $Text" -ForegroundColor $Color
}

# ── 0. 加载配置文件 ──────────────────────────────────────────────────────────

function Load-SymlinkConfig {
    <#
    .SYNOPSIS
        从 symlinks.txt 解析符号链接配置。
        格式：
          C:\source                        → 目标自动 = D:\source
          C:\source -> X:\target           → 显式目标
          # 注释                           → 跳过
    .RETURNS
        @{ Source=...; Target=...; Desc=... } 数组
    #>
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Status "[FAIL] 配置文件不存在: $Path" -Color Red
        Write-Status "  请创建 symlinks.txt，每行一个 C: 源路径" -Color Yellow
        exit 1
    }

    $result = @()
    $lines = Get-Content $Path -Encoding UTF8 | Where-Object { $_ -match '\S' }

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^#' -or $trimmed -eq '') { continue }

        $source = ''
        $target = ''

        if ($trimmed -match '^(.+?) *-> *(.+)$') {
            $source = $matches[1].Trim()
            $target = $matches[2].Trim()
        } else {
            $source = $trimmed
        }

        if (-not $source) { continue }

        # 自动推导目标：C:\ 替换为 D:\
        if (-not $target) {
            if ($source -match '^C:\\') {
                $target = $source -replace '^C:\\', 'D:\'
            } elseif ($source -match '^C:/') {
                $target = $source -replace '^C:/', 'D:/'
            } else {
                Write-Status "[WARN] 无法自动推导目标: $source" -Color Yellow
                continue
            }
        }

        $desc = Split-Path $source -Leaf

        $result += @{
            Source = $source
            Target = $target
            Desc   = $desc
        }
    }

    if ($result.Count -eq 0) {
        Write-Status "[FAIL] 配置文件中没有有效的条目" -Color Red
        exit 1
    }

    Write-Status "已加载 $($result.Count) 个配置项" -Color Cyan
    return $result
}

# ── 1. 数据迁移（robocopy 封装） ──────────────────────────────────────────────

function Invoke-Robocopy {
    <#
    .SYNOPSIS
        使用 robocopy 拷贝目录，返回 $true/$false
        注意：路径含空格时必须用双引号包裹。
    #>
    param(
        [string]$Source,
        [string]$Dest,
        [int]$Retry = 3,
        [int]$WaitSec = 5,
        [switch]$Merge
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
        # 修复：路径用双引号包裹防止空格问题；/COPY:DATS 保留 ACL 权限
        # Merge 模式：使用 /E 而非 /MIR，避免删除目标已有文件
        $robocopyMode = if ($Merge) { "/E" } else { "/E" }
        $output = & robocopy "$($Source.TrimEnd('\'))" "$($Dest.TrimEnd('\'))" `
            $robocopyMode /COPY:DATS "/R:$Retry" "/W:$WaitSec" /NP /NFL /NDL 2>&1

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
    param([string]$Path, [switch]$Aggressive)

    try {
        $stopped = @()
        $pathLower = $Path.ToLower()
        $patterns = @()

        # ── 根据路径关键词匹配进程名 ──
        $keywordMap = @(
            @('*siemens*', 'ug*', 'nx*', 'ugnx*', 'teamcenter*'),
            @('*logitech*', 'logi*', 'lghub*'),
            @('*adobe*', 'adobe*', 'photoshop*', 'illustrator*'),
            @('*autodesk*', 'autodesk*', 'acad*', 'revit*', 'adsk*'),
            @('*android*', 'adb*', 'androidemulator*'),
            @('*fiddler*', 'fiddler*'),
            @('*lmstudio*', 'lmstudio*'),
            @('*cherry*', 'cherry*'),
            @('*claude*', 'claude*', 'anthropic*'),
            @('*cline*', 'cline*'),
            @('*gemini*', 'gemini*'),
            @('*qwen*', 'qwen*', 'tongyi*', 'lingma*'),
            @('*hermes*', 'hermes*'),
            @('*google*', 'google*', 'chrome*', 'crashpad*'),
            @('*jetbrains*', 'idea*', 'pycharm*', 'webstorm*', 'rider*'),
            # 编辑器/IDE：限制更精确避免误杀
            @('*visualstudio*', 'devenv*'),
            @('*python*', 'python*', 'uvicorn*', 'node*')
        )

        foreach ($map in $keywordMap) {
            if ($pathLower -like $map[0]) {
                for ($i = 1; $i -lt $map.Count; $i++) {
                    $patterns += $map[$i]
                }
            }
        }

        # 始终检查 explorer（仅在非激进模式下跳过）
        if (-not $Aggressive) {
            $patterns += 'explorer'
        }

        # 去重
        $patterns = $patterns | Select-Object -Unique

        foreach ($pattern in $patterns) {
            # 修复：Get-Process -Name 通配符兼容性差，改用管道过滤
            $procs = Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.ProcessName -like $pattern }

            foreach ($p in $procs) {
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
        if ($pathLower -like '*\autodesk*') {
            $svcPatterns += 'AdskLicensing*', 'Autodesk*', 'FLEXnet*'
        }
        # 修复：加 \ 前缀防止误匹配 unix/lynx
        if ($pathLower -like '*\siemens*' -or $pathLower -like '*\nx*' -or $pathLower -like '*solidedge*') {
            $svcPatterns += 'Siemens*', 'SolidEdge*', 'ugnx*'
        }
        if ($pathLower -like '*\logitech*') {
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
                    $script:stoppedServices[$svc.Name] = if ($svc.StartType) { $svc.StartType } else { 'Manual' }
                } catch {
                    Write-Status "[WARN] 未能停止服务: $($_.Exception.Message)" -Color Yellow
                }
            }
        }

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
    if ($script:stoppedServices.Count -eq 0) { return }

    Write-Status "恢复 $($script:stoppedServices.Count) 个服务..." -Color Cyan
    foreach ($kv in $script:stoppedServices.GetEnumerator()) {
        try {
            Set-Service -Name $kv.Key -StartupType $kv.Value -ErrorAction SilentlyContinue
            Write-Status "  $($kv.Key) → $($kv.Value)" -Color Gray
        } catch {
            Write-Status "  [WARN] 恢复 $($kv.Key) 失败: $($_.Exception.Message)" -Color Yellow
        }
    }
    $script:stoppedServices.Clear()
}

# ── 2.3. 精确检测锁定文件的进程 ───────────────────────────────────────────────

function Find-LockingProcesses {
    <#
    .SYNOPSIS
        使用多种方法精确检测锁定指定路径的进程。
    .RETURNS
        进程信息数组 @{ProcessName; PID; Path; LockType}
    #>
    param([string]$Path)
    
    $lockingProcesses = @()
    
    try {
        # 方法 1: 使用 handle.exe（最准确）
        $handleExe = Get-Command handle.exe -ErrorAction SilentlyContinue
        if (-not $handleExe) {
            $possiblePaths = @(
                "$env:ProgramFiles\SysinternalsSuite\handle.exe",
                "$env:LOCALAPPDATA\Sysinternals\handle.exe"
            )
            foreach ($p in $possiblePaths) {
                if (Test-Path $p) {
                    $handleExe = $p
                    break
                }
            }
        }
        
        if ($handleExe) {
            Write-Status "使用 handle.exe 检测锁定进程..." -Color Cyan
            $handleOutput = & $handleExe "$Path" -accepteula 2>&1
            
            if ($handleOutput -match '(\w+\.exe)\s+pid:\s+(\d+)\s+type:\s+File') {
                $procName = $matches[1]
                $pid = [int]$matches[2]
                
                try {
                    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
                    if ($proc) {
                        $lockingProcesses += @{
                            ProcessName = $proc.ProcessName
                            PID = $pid
                            Path = $proc.Path
                            LockType = 'File Handle'
                            Method = 'handle.exe'
                        }
                        Write-Status "  发现: $($proc.ProcessName) (PID: $pid)" -Color Yellow
                        Write-Status "  路径: $($proc.Path)" -Color Gray
                    }
                } catch {}
            }
        }
        
        # 方法 2: 使用 OpenFiles 命令（Windows 内置）
        if ($lockingProcesses.Count -eq 0) {
            Write-Status "使用 openfiles 检测锁定进程..." -Color Cyan
            try {
                $openFilesOutput = & openfiles /query /fo CSV /nh 2>&1
                $csvData = $openFilesOutput | ConvertFrom-Csv
                
                foreach ($row in $csvData) {
                    if ($row.'Open File (Path\\executable)' -like "*$Path*") {
                        $lockingProcesses += @{
                            ProcessName = $row.Accessed
                            PID = [int]$row.'PID'
                            Path = ''
                            LockType = 'Open File'
                            Method = 'openfiles'
                        }
                        Write-Status "  发现: $($row.Accessed) (PID: $($row.PID))" -Color Yellow
                    }
                }
            } catch {
                Write-Status "  openfiles 检测失败" -Color Gray
            }
        }
        
        # 方法 3: 遍历所有进程检查模块（较慢但全面）
        if ($lockingProcesses.Count -eq 0) {
            Write-Status "扫描进程模块..." -Color Cyan
            $allProcesses = Get-Process -ErrorAction SilentlyContinue
            
            foreach ($proc in $allProcesses) {
                try {
                    $modules = $proc.Modules | Where-Object {
                        $_.FileName -like "$Path*"
                    }
                    
                    if ($modules) {
                        $lockingProcesses += @{
                            ProcessName = $proc.ProcessName
                            PID = $proc.Id
                            Path = $proc.Path
                            LockType = 'Module'
                            Method = 'Module Scan'
                        }
                        Write-Status "  发现: $($proc.ProcessName) (PID: $($proc.Id))" -Color Yellow
                    }
                } catch {
                    # 忽略无法访问的进程
                }
            }
        }
        
    } catch {
        Write-Status "  进程检测异常: $_" -Color Yellow
    }
    
    return $lockingProcesses
}

# ── 2.5. 尝试关闭文件句柄 ─────────────────────────────────────────────────────

function Try-CloseHandles {
    <#
    .SYNOPSIS
        尝试使用 handle.exe 或 Sysinternals 工具关闭锁定文件的句柄。
    #>
    param([string]$Path)
    
    # 检查 handle.exe 是否可用（Sysinternals 工具）
    $handleExe = Get-Command handle.exe -ErrorAction SilentlyContinue
    if (-not $handleExe) {
        # 尝试常见位置
        $possiblePaths = @(
            "$env:ProgramFiles\SysinternalsSuite\handle.exe",
            "$env:LOCALAPPDATA\Sysinternals\handle.exe",
            "C:\Windows\System32\handle.exe"
        )
        foreach ($p in $possiblePaths) {
            if (Test-Path $p) {
                $handleExe = $p
                break
            }
        }
    }
    
    if (-not $handleExe) {
        Write-Status "[INFO] handle.exe 未找到，跳过句柄关闭" -Color Gray
        return
    }
    
    try {
        Write-Status "正在查找锁定文件的句柄..." -Color Cyan
        $handleOutput = & handle.exe "$Path" 2>&1
        
        if ($handleOutput -match '(\w+\.exe)\s+pid:\s+(\d+)\s+type:\s+File\s+\w+:\s+(.+)$') {
            $processName = $matches[1]
            $pid = $matches[2]
            $handleId = $matches[3]
            
            Write-Status "发现锁定: $processName (PID: $pid, Handle: $handleId)" -Color Yellow
            Write-Status "尝试关闭句柄..." -Color Cyan
            
            # 需要管理员权限
            $closeResult = & handle.exe -c $handleId -p $pid -y 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Status "[OK] 句柄已关闭" -Color Green
                Start-Sleep -Seconds 1
            } else {
                Write-Status "[WARN] 关闭句柄失败" -Color Yellow
            }
        } else {
            Write-Status "[INFO] 未找到匹配的句柄" -Color Gray
        }
    } catch {
        Write-Status "[WARN] 句柄检测异常: $_" -Color Yellow
    }
}

# ── 3. 强制删除目录（带重试+自动终止锁定进程） ─────────────────────────────────

function Remove-DirectoryWithForce {
    <#
    .SYNOPSIS
        递归删除目录，遇到锁定自动查杀进程后重试。
        支持强制解锁模式，使用多种方法尝试删除。
    .RETURNS
        $true 删除成功 / $false 最终失败
    #>
    param([string]$Path, [int]$MaxRetriesParam)
    
    # 使用参数或全局设置
    if (-not $MaxRetriesParam) {
        $MaxRetriesParam = $MaxRetries
    }

    # 安全防护：拒绝删除系统关键路径
    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path -match '^[A-Z]:\\?$' -or
        $Path -eq "$env:SystemRoot" -or
        $Path -eq "$env:SystemRoot\") {
        Write-Status "[FATAL] 拒绝删除系统关键路径: $Path" -Color Red
        return $false
    }

    if ($WhatIf) {
        Write-Status "[DRY RUN] 模拟删除: $Path" -Color Yellow
        return $true
    }

    Write-Status "开始强制删除: $Path" -Color Cyan
    Write-Status "最大重试次数: $MaxRetriesParam" -Color Gray
    
    for ($i = 1; $i -le $MaxRetriesParam; $i++) {
        try {
            Write-Status "  第 $i/$MaxRetriesParam 次尝试..." -Color Gray
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
            Start-Sleep -Seconds 1
            Write-Status "[OK] 目录删除成功" -Color Green
            return $true
        } catch {
            Write-Status "[WARN] 删除失败: $($_.Exception.Message)" -Color Yellow
            
            if ($i -lt $MaxRetriesParam) {
                # ★ 精确检测锁定进程
                Write-Status "正在精确检测锁定进程..." -Color Cyan
                $lockers = Find-LockingProcesses -Path $Path
                
                if ($lockers.Count -gt 0) {
                    Write-Status "发现 $($lockers.Count) 个锁定进程:" -Color Yellow
                    foreach ($locker in $lockers) {
                        Write-Status "  • $($locker.ProcessName) (PID: $($locker.PID)) - $($locker.LockType)" -Color White
                        Write-Status "    路径: $($locker.Path)" -Color Gray
                    }
                    
                    # 强制终止所有锁定进程
                    Write-Status "正在强制终止锁定进程..." -Color Cyan
                    foreach ($locker in $lockers) {
                        try {
                            $proc = Get-Process -Id $locker.PID -ErrorAction SilentlyContinue
                            if ($proc) {
                                Stop-Process -Id $locker.PID -Force -ErrorAction Stop
                                Write-Status "  ✓ 已终止: $($locker.ProcessName) (PID: $($locker.PID))" -Color Green
                            }
                        } catch {
                            Write-Status "  ✗ 无法终止: $($locker.ProcessName) (PID: $($locker.PID))" -Color Red
                        }
                    }
                } else {
                    Write-Status "未检测到明确的锁定进程，尝试通用清理..." -Color Yellow
                    # 激进模式：终止更多可能的进程
                    Stop-LockingProcesses -Path $Path -Aggressive
                }
                
                # 尝试关闭文件句柄
                if ($ForceUnlock) {
                    Write-Status "尝试关闭文件句柄..." -Color Cyan
                    Try-CloseHandles -Path $Path
                }
                
                # 特定应用的强制处理
                if ($Path -like '*\autodesk*') {
                    Write-Status "强制终止 Autodesk 进程树..." -Color Cyan
                    & taskkill /F /IM adskflex.exe /T 2>$null
                    & taskkill /F /IM AdskAccessServiceHost.exe /T 2>$null
                    & taskkill /F /IM AdskLicensingService.exe /T 2>$null
                }
                
                if ($Path -like '*hermes*') {
                    Write-Status "强制终止 Hermes/Python/Node 相关进程..." -Color Cyan
                    Get-Process | Where-Object {
                        $_.ProcessName -like '*python*' -or
                        $_.ProcessName -like '*node*' -or
                        $_.ProcessName -like '*hermes*'
                    } | ForEach-Object {
                        Write-Status "  终止: $($_.ProcessName) (PID: $($_.Id))" -Color Gray
                        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                    }
                }
                
                # 等待时间递增（更强模式）
                $waitTime = [Math]::Min(3 + $i, 8)  # 从 3 秒递增到 8 秒
                Write-Status "等待 ${waitTime}秒后重试..." -Color Gray
                Start-Sleep -Seconds $waitTime
            } else {
                Write-Status "[FAIL] 重试 $MaxRetriesParam 次后仍无法删除" -Color Red
                Write-Status "  错误详情: $($_.Exception.Message)" -Color Gray
                
                # 最后一次尝试：使用 cmd 的 rd 命令
                Write-Status "尝试使用 cmd rd /s /q 强制删除..." -Color Yellow
                try {
                    $cmdResult = & cmd /c "rd /s /q `"$Path`"" 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Status "[OK] 通过 cmd rd 删除成功" -Color Green
                        return $true
                    } else {
                        Write-Status "[FAIL] cmd rd 也失败了 (退出码: $LASTEXITCODE)" -Color Red
                    }
                } catch {
                    Write-Status "[FAIL] cmd rd 异常: $_" -Color Red
                }
                
                # 终极手段：重启后删除（提示用户）
                Write-Status "" -Color White
                Write-Status "⚠️  建议操作:" -Color Yellow
                Write-Status "  1. 重启电脑" -Color White
                Write-Status "  2. 立即运行此脚本（不要打开其他程序）" -Color White
                Write-Status "  3. 或手动删除: Remove-Item '$Path' -Recurse -Force" -Color White
                Write-Status "" -Color White
                
                return $false
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

    $parent = Split-Path $Source -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

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

# ── 处理符号链接（返回结果用于主循环统计） ──────────────────────────────────

function Process-SymlinkItem {
    <#
    .SYNOPSIS
        处理单个符号链接项。
    .RETURNS
        @{ Result = 'skip'|'success'|'fail' }
        注意：统计在主循环中统一累加，避免 $script: 作用域问题。
    #>
    param(
        [hashtable]$Link,
        [int]$Index,
        [int]$Total
    )

    Write-ProgressItem -Index $Index -Total $Total -Desc $Link.Desc
    Write-Status "来源: $($Link.Source)" -Color Green
    Write-Status "目标: $($Link.Target)" -Color Green

    # ─ 场景 A：已经是符号链接 ─
    # 修复：先用 Get-Item -Force 检测损坏的符号链接（Test-Path 对损坏链接返回 $false）
    $existingItem = Get-Item $Link.Source -Force -ErrorAction SilentlyContinue
    if ($existingItem -and ($existingItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        if (Test-Path $Link.Source) {
            Write-Status "状态: [跳过] 符号链接已存在" -Color Green
            return @{ Result = 'skip' }
        } else {
            Write-Status "状态: [修复] 损坏的符号链接，重新创建" -Color Yellow
            Remove-Item $Link.Source -Force -ErrorAction SilentlyContinue
            # 继续到场景 C 重新创建
        }
    } elseif (Test-Path $Link.Source) {
        # ─ 场景 B：源路径是真实目录 → 需要迁移 ─
        Write-Status "源路径是真实目录，准备迁移..." -Color Yellow

        $targetExists = Test-Path $Link.Target
        $targetNotEmpty = $targetExists -and @(Get-ChildItem $Link.Target -ErrorAction SilentlyContinue).Count -gt 0

        # 修复：robocopy 失败时不删除源目录，防止数据丢失
        $robocopyOk = $true
        if (-not $targetNotEmpty) {
            Write-Status "目标路径为空，开始复制数据..." -Color Cyan
            $robocopyOk = Invoke-Robocopy -Source $Link.Source -Dest $Link.Target
            if (-not $robocopyOk) {
                Write-Status "[FAIL] 数据迁移失败，拒绝删除源目录以防数据丢失" -Color Red
                return @{ Result = 'fail' }
            }
        } else {
            # 目标已有数据，询问用户如何处理
            if ($script:skipAllConflicts) {
                Write-Status "全局跳过模式：保留目标现有数据" -Color Cyan
                # 直接跳过，不询问
            } else {
                Write-Status "⚠️  警告: 目标路径已有数据！" -Color Yellow
                Write-Status "  源路径: $($Link.Source)" -Color Gray
                Write-Status "  目标路径: $($Link.Target)" -Color Gray
                Write-Status "" -Color White
                Write-Status "选择操作:" -Color Cyan
                Write-Status "  [S] 跳过复制（保留目标现有数据）" -Color White
                Write-Status "  [M] 合并复制（将源数据合并到目标）" -Color White
                Write-Status "  [R] 替换目标（删除目标数据后复制）" -Color White
                Write-Status "  [A] 全部跳过（后续所有类似情况都跳过）" -Color White
                Write-Status "" -Color White
                
                # 如果没有交互模式，默认跳过（安全）
                if ($ForceMode) {
                    Write-Status "强制模式：执行合并复制" -Color Yellow
                    $choice = 'M'
                } else {
                    $choice = Read-Host "请选择 (S/M/R/A)"
                }
                
                switch ($choice.ToUpper()) {
                    'M' {
                        Write-Status "执行合并复制..." -Color Cyan
                        $robocopyOk = Invoke-Robocopy -Source $Link.Source -Dest $Link.Target -Merge
                        if (-not $robocopyOk) {
                            Write-Status "[WARN] 合并复制出现问题，但继续处理" -Color Yellow
                        }
                    }
                    'R' {
                        Write-Status "删除目标数据并重新复制..." -Color Yellow
                        Write-Status "正在清空目标目录..." -Color Cyan
                        Remove-Item "$($Link.Target)\*" -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Status "开始复制..." -Color Cyan
                        $robocopyOk = Invoke-Robocopy -Source $Link.Source -Dest $Link.Target
                        if (-not $robocopyOk) {
                            Write-Status "[FAIL] 数据复制失败" -Color Red
                            return @{ Result = 'fail' }
                        }
                    }
                    'A' {
                        Write-Status "设置全局跳过标志" -Color Yellow
                        $script:skipAllConflicts = $true
                        # 继续执行，跳过本次复制
                    }
                    default {
                        Write-Status "跳过复制，保留目标现有数据" -Color Cyan
                    }
                }
            }
        }

        # 删除源目录（自动处理锁定）
        if (-not (Remove-DirectoryWithForce -Path $Link.Source -MaxRetriesParam $MaxRetries)) {
            return @{ Result = 'fail' }
        }

        # 创建符号链接
        if (New-SymlinkWithVerify -Source $Link.Source -Target $Link.Target) {
            # 标记为迁移操作（用于统计）
            return @{ Result = 'success'; Migrate = $true }
        } else {
            return @{ Result = 'fail' }
        }
    }

    # ─ 场景 C：源路径不存在 → 直接创建符号链接 ─
    if ($Link.Target -like "Volume{*") {
        Write-Status "跳过卷挂载（由系统管理）" -Color Yellow
        return @{ Result = 'skip' }
    }

    if (-not (Test-Path $Link.Target)) {
        Write-Status "目标路径不存在，创建目录..." -Color Yellow
        try {
            if (-not $WhatIf) {
                New-Item -ItemType Directory -Path $Link.Target -Force -ErrorAction Stop | Out-Null
            }
            Write-Status "[OK] 目录已创建" -Color Green
        } catch {
            Write-Status "[FAIL] 创建目录失败: $_" -Color Red
            return @{ Result = 'fail' }
        }
    }

    if (New-SymlinkWithVerify -Source $Link.Source -Target $Link.Target) {
        return @{ Result = 'success' }
    } else {
        return @{ Result = 'fail' }
    }
}

# ── 5. 自动追加未链接的 . 开头目录 ────────────────────────────────────────────

function Add-MissingDotDirs {
    <#
    .SYNOPSIS
        扫描当前用户目录下 . 开头的真实目录，自动追加到 symlinks.txt。
    .DESCRIPTION
        仅追加未建立软连接且不在配置中的目录。
    #>
    param([string]$ConfigPath, [string]$UserDir = "$env:USERPROFILE")

    $existingLines = Get-Content $ConfigPath -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $existingLines) { return }

    $dotDirs = Get-ChildItem $UserDir -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '.*' -and
                       -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }

    if (-not $dotDirs -or $dotDirs.Count -eq 0) { return }

    $newDirs = @()
    foreach ($dir in $dotDirs) {
        $src = $dir.FullName
        $found = $false
        foreach ($line in $existingLines) {
            if ($line.Trim() -match [regex]::Escape($src)) {
                $found = $true
                break
            }
        }
        if (-not $found) {
            $newDirs += $dir.Name
        }
    }

    if ($newDirs.Count -eq 0) { return }

    Write-Status "发现 $($newDirs.Count) 个新 . 目录，正在追加到 symlinks.txt..." -Color Cyan
    $newDirs = $newDirs | Sort-Object

    $insertIndex = -1
    for ($i = 0; $i -lt $existingLines.Count; $i++) {
        if ($existingLines[$i] -match '^#\s*===\s*卷挂载') {
            $insertIndex = $i
            break
        }
    }

    if ($insertIndex -lt 0) { $insertIndex = $existingLines.Count }

    $newContent = @()
    for ($i = 0; $i -lt $insertIndex; $i++) {
        $newContent += $existingLines[$i]
    }
    foreach ($d in $newDirs) {
        # 修复：用 $env:USERPROFILE 替换硬编码用户名
        $newContent += "$env:USERPROFILE\$d"
        Write-Status "  + $d" -Color Green
    }
    if ($newContent[$newContent.Count - 1] -ne '') { $newContent += '' }
    for ($i = $insertIndex; $i -lt $existingLines.Count; $i++) {
        $newContent += $existingLines[$i]
    }

    # 修复：用 utf8NoBOM 兼容 PS5.1 和 PS7
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($ConfigPath, $newContent, $utf8NoBom)
}

# ── 符号链接配置（从 symlinks.txt 加载） ───────────────────────────────────────

if (-not $WhatIf) {
    Add-MissingDotDirs -ConfigPath $ConfigFile
}

$symlinks = Load-SymlinkConfig -Path $ConfigFile

# ── 统计变量 ──────────────────────────────────────────────────────────────────

$script:stoppedServices = @{}
$script:skipAllConflicts = $false  # 全局跳过冲突标志
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
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "管理员权限: $isAdmin" -ForegroundColor Cyan
Write-Host "模式: 自动迁移 C → D 并创建符号链接" -ForegroundColor Green
Write-Host ""

# ── 主循环（修复：统计由函数返回后在主循环统一累加） ──────────────────────────

try {
    for ($i = 0; $i -lt $symlinks.Count; $i++) {
        $result = Process-SymlinkItem -Link $symlinks[$i] -Index ($i + 1) -Total $symlinks.Count
        switch ($result.Result) {
            'success' {
                $script:stats.success++
                if ($result.Migrate) { $script:stats.migrate++ }
            }
            'skip'    { $script:stats.skip++ }
            'fail'    { $script:stats.fail++ }
        }
    }
} finally {
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
Write-Host "  迁移数据: $($script:stats.migrate)"     -ForegroundColor Cyan
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
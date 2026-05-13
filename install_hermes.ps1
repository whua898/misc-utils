# Hermes AI 安装脚本
# 此脚本会自动下载并安装 Hermes AI

[CmdletBinding()]
param(
    [string]$InstallPath = "$env:USERPROFILE\.hermes",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Hermes AI 安装程序" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查是否已安装
if (Test-Path $InstallPath) {
    if (-not $Force) {
        Write-Host "警告: Hermes 已安装在 $InstallPath" -ForegroundColor Yellow
        $overwrite = Read-Host "是否覆盖安装？(y/n)"
        if ($overwrite -ne "y") {
            Write-Host "安装已取消" -ForegroundColor Gray
            exit 0
        }
    }
    
    # 强制模式：清理旧安装
    Write-Host "正在清理旧安装..." -ForegroundColor Cyan
    try {
        Remove-Item $InstallPath -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] 旧安装已清理" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] 清理失败: $_" -ForegroundColor Red
        exit 1
    }
}

# 创建安装目录
Write-Host "正在创建安装目录..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
Write-Host "[OK] 主目录: $InstallPath" -ForegroundColor Green



# 检查 Python 环境
Write-Host "`n检查 Python 环境..." -ForegroundColor Cyan
try {
    $pythonVersion = & python --version 2>&1
    Write-Host "[OK] Python 版本: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] 未找到 Python，请先安装 Python 3.10+" -ForegroundColor Red
    Write-Host "下载地址: https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

# 检查 uv（Python 包管理器）
Write-Host "`n检查 uv 包管理器..." -ForegroundColor Cyan
try {
    $uvVersion = & uv --version 2>&1
    Write-Host "[OK] uv 版本: $uvVersion" -ForegroundColor Green
} catch {
    Write-Host "[WARN] uv 未安装，正在安装..." -ForegroundColor Yellow
    try {
        powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
        Write-Host "[OK] uv 安装成功" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] uv 安装失败，请手动安装" -ForegroundColor Red
        exit 1
    }
}

# 配置 Git 凭证
Write-Host "`n配置 Git 凭证..." -ForegroundColor Cyan
try {
    & git config --global credential.helper manager-core 2>&1 | Out-Null
    Write-Host "[OK] Git 凭证已配置" -ForegroundColor Green
} catch {
    Write-Host "[WARN] Git 凭证配置失败" -ForegroundColor Yellow
}

# 克隆 Hermes 仓库
Write-Host "`n克隆 Hermes 仓库..." -ForegroundColor Cyan
try {
    # 尝试多个可能的仓库地址
    $repoUrls = @(
        "https://github.com/NousResearch/hermes-agent.git",
        "https://github.com/NousResearch/Hermes-3.git",
        "https://github.com/NousResearch/hermes-function-calling.git"
    )
    
    $cloned = $false
    foreach ($url in $repoUrls) {
        Write-Host "`n  尝试: $url" -ForegroundColor Gray
        
        try {
            # 清理目标目录
            if (Test-Path $InstallPath) {
                Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # 直接克隆，不捕获输出，让 git 直接显示
            Write-Host "  开始克隆..." -ForegroundColor Cyan
            
            # 增加 Git 缓冲区，避免大仓库 SSL 错误
            $env:GIT_HTTP_MAX_REQUESTS = "10"
            & git config --global http.postBuffer 524288000 2>$null
            & git config --global core.compression 0 2>$null
            
            # 使用浅克隆先获取基础，然后加深
            & git clone --depth 1 $url $InstallPath
            
            if ($LASTEXITCODE -eq 0) {
                # 检查是否有 pyproject.toml
                if (Test-Path "$InstallPath\pyproject.toml") {
                    Write-Host "  [OK] 仓库克隆成功（包含 pyproject.toml）" -ForegroundColor Green
                    $cloned = $true
                    break
                } else {
                    Write-Host "  [WARN] 克隆成功但缺少 pyproject.toml，继续尝试其他仓库" -ForegroundColor Yellow
                    Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            } else {
                Write-Host "  [FAIL] 克隆失败 (退出码: $LASTEXITCODE)" -ForegroundColor Red
            }
        } catch {
            Write-Host "  [FAIL] 异常: $_" -ForegroundColor Red
            continue
        }
    }
    
    if (-not $cloned) {
        Write-Host "`n[ERROR] 所有预设仓库地址都失败！" -ForegroundColor Red
        Write-Host "`n请手动指定仓库地址：" -ForegroundColor Yellow
        $customUrl = Read-Host "输入 GitHub 仓库 URL（直接回车跳过）"
        if ($customUrl -and $customUrl.Trim() -ne "") {
            # 清理目标目录
            if (Test-Path $InstallPath) {
                Write-Host "  正在清理目标目录..." -ForegroundColor Cyan
                Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            Write-Host "`n  尝试克隆: $customUrl" -ForegroundColor Cyan
            & git clone $customUrl.Trim() $InstallPath
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] 仓库克隆成功" -ForegroundColor Green
                $cloned = $true
            } else {
                Write-Host "  [ERROR] 克隆失败" -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "已跳过仓库克隆" -ForegroundColor Gray
            exit 0
        }
    }
} catch {
    Write-Host "[ERROR] 仓库克隆异常: $_" -ForegroundColor Red
    exit 1
}

# 安装依赖
Write-Host "`n安装 Python 依赖..." -ForegroundColor Cyan
Set-Location $InstallPath
try {
    if (-not (Test-Path "pyproject.toml")) {
        Write-Host "[ERROR] 找不到 pyproject.toml，仓库可能不完整" -ForegroundColor Red
        exit 1
    }
    & uv sync
    Write-Host "[OK] 依赖安装成功" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] 依赖安装失败: $_" -ForegroundColor Red
    exit 1
}



# 创建启动脚本
Write-Host "`n创建启动脚本..." -ForegroundColor Cyan

$startScript = @"
# Hermes AI 启动脚本
`$env:HERMES_HOME = "$InstallPath"
Set-Location "$InstallPath"
& uv run hermes chat
"@

$startScript | Out-File -FilePath "$InstallPath\start-hermes.ps1" -Encoding UTF8
Write-Host "[OK] 启动脚本: $InstallPath\start-hermes.ps1" -ForegroundColor Green

# 创建全局命令脚本（hermes.cmd）
Write-Host "`n配置全局 hermes 命令..." -ForegroundColor Cyan
$hermesCmd = @"
@echo off
cd /d "%~dp0"
uv run hermes %*
"@
$hermesCmd | Out-File -FilePath "$InstallPath\hermes.cmd" -Encoding ASCII
Write-Host "[OK] 全局命令脚本: $InstallPath\hermes.cmd" -ForegroundColor Green

# 添加到 PATH
try {
    $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($currentPath -notlike "*$InstallPath*") {
        [Environment]::SetEnvironmentVariable('Path', "$currentPath;$InstallPath", 'User')
        Write-Host "[OK] 已将 $InstallPath 添加到用户 PATH" -ForegroundColor Green
        Write-Host "     ⚠️  请重启 PowerShell 使更改生效" -ForegroundColor Yellow
    } else {
        Write-Host "[OK] PATH 已包含安装目录" -ForegroundColor Gray
    }
} catch {
    Write-Host "[WARN] 无法自动添加到 PATH，请手动添加: $InstallPath" -ForegroundColor Yellow
}




# 完成
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  安装完成！" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📁 安装位置:" -ForegroundColor Yellow
Write-Host "  主程序: $InstallPath" -ForegroundColor White
Write-Host ""
Write-Host "🚀 启动方式:" -ForegroundColor Yellow
Write-Host "  方式 1: hermes chat (推荐，全局命令)" -ForegroundColor White
Write-Host "  方式 2: $InstallPath\start-hermes.ps1" -ForegroundColor White
Write-Host ""
Write-Host "⚠️  注意: 首次使用需要重启 PowerShell 使全局命令生效" -ForegroundColor Yellow
Write-Host ""
Write-Host "📖 文档: https://github.com/hermes-agent/hermes" -ForegroundColor Yellow
Write-Host ""


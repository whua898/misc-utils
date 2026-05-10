# Hermes AI 安装脚本
# 此脚本会自动下载并安装 Hermes AI 及其 Web UI

[CmdletBinding()]
param(
    [string]$InstallPath = "$env:USERPROFILE\.hermes",
    [string]$WebUIPath = "$env:USERPROFILE\.hermes-web-ui",
    [switch]$SkipWebUI,
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

if (-not $SkipWebUI) {
    New-Item -ItemType Directory -Path $WebUIPath -Force | Out-Null
    Write-Host "[OK] Web UI 目录: $WebUIPath" -ForegroundColor Green
}

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

# 克隆 Hermes 仓库
Write-Host "`n克隆 Hermes 仓库..." -ForegroundColor Cyan
try {
    # 尝试多个可能的仓库地址
    $repoUrls = @(
        "https://github.com/NousResearch/Hermes-3.git",
        "https://github.com/NousResearch/hermes-function-calling.git",
        "https://github.com/weaviate/hermes.git"
    )
    
    $cloned = $false
    foreach ($url in $repoUrls) {
        Write-Host "  尝试: $url" -ForegroundColor Gray
        try {
            & git clone $url $InstallPath 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] 仓库克隆成功: $url" -ForegroundColor Green
                $cloned = $true
                break
            }
        } catch {
            continue
        }
    }
    
    if (-not $cloned) {
        Write-Host "[ERROR] 所有仓库地址都失败，请手动检查仓库地址" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[ERROR] 仓库克隆失败: $_" -ForegroundColor Red
    exit 1
}

# 安装依赖
Write-Host "`n安装 Python 依赖..." -ForegroundColor Cyan
Set-Location $InstallPath
try {
    & uv sync
    Write-Host "[OK] 依赖安装成功" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] 依赖安装失败: $_" -ForegroundColor Red
    exit 1
}

# 安装 Web UI（如果未跳过）
if (-not $SkipWebUI) {
    Write-Host "`n安装 Hermes Web UI..." -ForegroundColor Cyan
    try {
        # 清理并重新克隆
        if (Test-Path $WebUIPath) {
            Remove-Item $WebUIPath -Recurse -Force
        }
        New-Item -ItemType Directory -Path $WebUIPath -Force | Out-Null
        Set-Location $WebUIPath
        & git clone https://github.com/hermes-agent/hermes-web-ui.git .
        & uv sync
        Write-Host "[OK] Web UI 安装成功" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Web UI 安装失败: $_" -ForegroundColor Yellow
    }
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

if (-not $SkipWebUI -and (Test-Path "$WebUIPath\package.json")) {
    $webUIStartScript = @"
# Hermes Web UI 启动脚本
Set-Location "$WebUIPath"
npm run dev
"@
    $webUIStartScript | Out-File -FilePath "$WebUIPath\start-webui.ps1" -Encoding UTF8
    Write-Host "[OK] Web UI 启动脚本: $WebUIPath\start-webui.ps1" -ForegroundColor Green
}


# 完成
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  安装完成！" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📁 安装位置:" -ForegroundColor Yellow
Write-Host "  主程序: $InstallPath" -ForegroundColor White
if (-not $SkipWebUI) {
    Write-Host "  Web UI: $WebUIPath" -ForegroundColor White
}
Write-Host ""
Write-Host "🚀 启动方式:" -ForegroundColor Yellow
Write-Host "  1. 运行: $InstallPath\start-hermes.ps1" -ForegroundColor White
if (-not $SkipWebUI -and (Test-Path "$WebUIPath\start-webui.ps1")) {
    Write-Host "  2. 运行: $WebUIPath\start-webui.ps1" -ForegroundColor White
}
Write-Host ""
Write-Host "📖 文档: https://github.com/hermes-agent/hermes" -ForegroundColor Yellow
Write-Host ""


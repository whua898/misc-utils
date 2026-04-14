# GitHub 仓库创建和推送脚本
# 使用方法: .\push-to-github.ps1 -Username "your-github-username" -RepoName "misc-utils" -IsPrivate:$true

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [string]$RepoName = "misc-utils",
    
    [Parameter(Mandatory=$false)]
    [switch]$IsPrivate = $true
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== GitHub 仓库推送脚本 ===" -ForegroundColor Cyan
Write-Host "用户名: $Username" -ForegroundColor Yellow
Write-Host "仓库名: $RepoName" -ForegroundColor Yellow
Write-Host "私有仓库: $IsPrivate" -ForegroundColor Yellow
Write-Host ""

# 检查是否已存在远程仓库
$existingRemote = git remote get-url origin 2>$null
if ($existingRemote) {
    Write-Host "[警告] 已存在远程仓库: $existingRemote" -ForegroundColor Yellow
    $confirm = Read-Host "是否覆盖？(y/n)"
    if ($confirm -ne 'y') {
        Write-Host "操作已取消" -ForegroundColor Red
        exit
    }
    git remote remove origin
}

# 构建仓库 URL
$repoUrl = "https://github.com/$Username/$RepoName.git"

Write-Host "`n请按照以下步骤操作:" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host ""
Write-Host "1. 在浏览器中打开: https://github.com/new" -ForegroundColor White
Write-Host "2. 创建名为 '$RepoName' 的仓库" -ForegroundColor White
Write-Host "3. 设置为 $(if($IsPrivate){'私有'}else{'公开'}) 仓库" -ForegroundColor White
Write-Host "4. 不要初始化 README、.gitignore 或 license" -ForegroundColor White
Write-Host "5. 点击 'Create repository'" -ForegroundColor White
Write-Host ""
Write-Host "按任意键继续..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# 添加远程仓库
Write-Host "`n添加远程仓库..." -ForegroundColor Cyan
git remote add origin $repoUrl

# 重命名分支为 main
Write-Host "重命名分支为 main..." -ForegroundColor Cyan
git branch -M main

# 推送
Write-Host "推送到 GitHub..." -ForegroundColor Cyan
git push -u origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ 成功！仓库已推送到 GitHub" -ForegroundColor Green
    Write-Host "访问: https://github.com/$Username/$RepoName" -ForegroundColor Green
} else {
    Write-Host "`n❌ 推送失败，请检查错误信息" -ForegroundColor Red
    Write-Host "可能的原因:" -ForegroundColor Yellow
    Write-Host "  - 仓库尚未在 GitHub 上创建" -ForegroundColor Yellow
    Write-Host "  - 认证失败（可能需要配置 Git 凭据）" -ForegroundColor Yellow
    Write-Host "  - 网络连接问题" -ForegroundColor Yellow
}

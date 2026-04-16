# Restore C drive symlinks
# Requires administrator privileges
# Used after system reinstallation to quickly rebuild all symlinks

$ErrorActionPreference = "Stop"

Write-Host "=== Restoring C Drive Symlinks ===" -ForegroundColor Cyan
Write-Host ""

# Define all symlink configurations
$symlinks = @(
    # ProgramData directories
    @{
        Source = "C:\ProgramData\Intel Package Cache {1CEAC85D-2590-4760-800F-8DE5E91F3700}"
        Target = "D:\ProgramData\Intel Package Cache"
        Description = "Intel Package Cache"
    },
    @{
        Source = "C:\ProgramData\LogiOptionsPlus"
        Target = "D:\ProgramData\LogiOptionsPlus"
        Description = "Logitech Options+ data directory"
    },
    @{
        Source = "C:\ProgramData\Logishrd"
        Target = "D:\ProgramData\Logishrd"
        Description = "Logitech hardware driver data"
    },
    @{
        Source = "C:\ProgramData\Microsoft\VisualStudio"
        Target = "D:\ProgramData\Microsoft\VisualStudio"
        Description = "Visual Studio shared data"
    },
    @{
        Source = "C:\ProgramData\Package Cache"
        Target = "D:\ProgramData\Package Cache"
        Description = "Windows Installer Package Cache"
    },

    # Program Files directories
    @{
        Source = "C:\Program Files\Common Files\Adobe\HelpCfg"
        Target = "F:\Oftenused\adobe\Photoshop\App\Program Files\Common Files\Adobe\HelpCfg"
        Description = "Adobe Help configuration"
    },
    @{
        Source = "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\Current"
        Target = "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\15.3.0.12981"
        Description = "Autodesk licensing service"
    },
    @{
        Source = "C:\Program Files (x86)\Common Files\Autodesk Shared\Network License Manager\.logger"
        Target = "UNKNOWN"
        Description = "Autodesk network license manager log (needs manual verification)"
        ManualCheck = $true
    },

    # User directories (wh898)
    @{
        Source = "C:\Users\wh898\.android"
        Target = "D:\Users\wh898\.android"
        Description = "Android SDK/Emulator data"
    },
    @{
        Source = "C:\Users\wh898\.antigravity"
        Target = "D:\Users\wh898\.antigravity"
        Description = "Antigravity AI tool configuration"
    },
    @{
        Source = "C:\Users\wh898\.antigravity_tools"
        Target = "D:\Users\wh898\.antigravity_tools"
        Description = "Antigravity tools"
    },
    @{
        Source = "C:\Users\wh898\.cache"
        Target = "D:\Users\wh898\.cache"
        Description = "Application cache"
    },
    @{
        Source = "C:\Users\wh898\.cherrystudio"
        Target = "D:\Users\wh898\.cherrystudio"
        Description = "Cherry Studio LLM client"
    },
    @{
        Source = "C:\Users\wh898\.claude"
        Target = "D:\Users\wh898\.claude"
        Description = "Claude AI configuration"
    },
    @{
        Source = "C:\Users\wh898\.cline"
        Target = "D:\Users\wh898\.cline"
        Description = "Cline AI programming assistant"
    },
    @{
        Source = "C:\Users\wh898\.continue"
        Target = "D:\Users\wh898\.continue"
        Description = "Continue AI programming plugin"
    },
    @{
        Source = "C:\Users\wh898\.fiddler"
        Target = "D:\Users\wh898\.fiddler"
        Description = "Fiddler web debugging proxy"
    },
    @{
        Source = "C:\Users\wh898\.gemini"
        Target = "D:\Users\wh898\.gemini"
        Description = "Google Gemini AI configuration"
    },
    @{
        Source = "C:\Users\wh898\.hvigor"
        Target = "D:\Users\wh898\.hvigor"
        Description = "Hvigor build tool (HarmonyOS)"
    },
    @{
        Source = "C:\Users\wh898\.lingma"
        Target = "D:\Users\wh898\.lingma"
        Description = "Tongyi Lingma AI assistant"
    },
    @{
        Source = "C:\Users\wh898\.lmstudio"
        Target = "D:\Users\wh898\.lmstudio"
        Description = "LM Studio AI models and configs"
    },
    @{
        Source = "C:\Users\wh898\.ohpm"
        Target = "D:\Users\wh898\.ohpm"
        Description = "OpenHarmony package manager"
    },
    @{
        Source = "C:\Users\wh898\.qwen"
        Target = "D:\Users\wh898\.qwen"
        Description = "Tongyi Qwen AI configuration"
    },
    @{
        Source = "C:\Users\wh898\.ssh"
        Target = "D:\Users\wh898\.ssh"
        Description = "SSH keys and configuration"
    },
    @{
        Source = "C:\Users\wh898\PCManger\mdfs"
        Target = "Volume{d6cc17c5-1733-4085-bce7-964f1e9f5de9}\"
        Description = "Tencent PC Manager virtual filesystem (volume mount)"
    }
)

# Windows system app links (usually handled automatically by system)
$systemLinks = @(
    "C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\WindowsApps\ActionsMcpHost.exe",
    "C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\WindowsApps\MicrosoftWindows.DesktopStickerEditorCentennial.exe",
    "C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\WindowsApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\ActionsMcpHost.exe",
    "C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\WindowsApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\MicrosoftWindows.DesktopStickerEditorCentennial.exe"
)

Write-Host "Found $($symlinks.Count) symlinks to process" -ForegroundColor Yellow
Write-Host ""

# Statistics
$successCount = 0
$skipCount = 0
$failCount = 0
$manualCount = 0

foreach ($link in $symlinks) {
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "Description: $($link.Description)" -ForegroundColor Cyan

    # Check if manual confirmation is needed
    if ($link.ManualCheck) {
        Write-Host "Status: WARNING - Manual verification needed" -ForegroundColor Yellow
        Write-Host "Source: $($link.Source)" -ForegroundColor Gray
        Write-Host "Tip: Check backup to determine target path" -ForegroundColor Yellow
        $manualCount++
        continue
    }

    Write-Host "Source: $($link.Source)" -ForegroundColor Green
    Write-Host "Target: $($link.Target)" -ForegroundColor Green

    # Check if source already exists
    if (Test-Path $link.Source) {
        $item = Get-Item $link.Source
        if ($item.Attributes -match "ReparsePoint") {
            Write-Host "Status: [OK] Symlink already exists, skipping" -ForegroundColor Green
            $skipCount++
            continue
        } else {
            Write-Host "Warning: Source exists but is not a symlink!" -ForegroundColor Red
            $response = Read-Host "Delete and recreate? (Y/N)"
            if ($response -eq 'Y' -or $response -eq 'y') {
                try {
                    Remove-Item $link.Source -Recurse -Force
                    Write-Host "Deleted existing directory" -ForegroundColor Yellow
                } catch {
                    Write-Host "Delete failed: $_" -ForegroundColor Red
                    $failCount++
                    continue
                }
            } else {
                Write-Host "Skipped" -ForegroundColor Yellow
                $skipCount++
                continue
            }
        }
    }

    # Check if target exists
    if (-not (Test-Path $link.Target)) {
        Write-Host "Error: Target does not exist: $($link.Target)" -ForegroundColor Red
        Write-Host "Please ensure target data has been restored" -ForegroundColor Yellow
        $failCount++
        continue
    }

    # Create symlink
    try {
        Write-Host "Creating symlink..." -ForegroundColor Green
        New-Item -ItemType SymbolicLink -Path $link.Source -Target $link.Target -Force | Out-Null

        # Verify
        $verifyItem = Get-Item $link.Source
        if ($verifyItem.Attributes -match "ReparsePoint") {
            Write-Host "[OK] Symlink created successfully!" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "[FAIL] Symlink verification failed" -ForegroundColor Red
            $failCount++
        }
    } catch {
        Write-Host "[FAIL] Creation failed: $_" -ForegroundColor Red
        Write-Host "  Tip: Run as administrator" -ForegroundColor Yellow
        $failCount++
    }

    Write-Host ""
}

# Output summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "=== Restore Complete ===" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Successfully created: $successCount" -ForegroundColor Green
Write-Host "Already exists (skipped): $skipCount" -ForegroundColor Yellow
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host "Requires manual handling: $manualCount" -ForegroundColor Yellow
Write-Host ""

if ($manualCount -gt 0) {
    Write-Host "Note: $manualCount symlinks require manual target path verification" -ForegroundColor Yellow
    Write-Host "Recommendations:" -ForegroundColor Yellow
    Write-Host "1. Check backup for original target paths" -ForegroundColor Gray
    Write-Host "2. Or use command to view existing symlinks:" -ForegroundColor Yellow
    Write-Host '   Get-ChildItem <path> -Attributes ReparsePoint | Select-Object FullName, Target' -ForegroundColor Gray
    Write-Host ""
}

if ($failCount -gt 0) {
    Write-Host "Warning: $failCount symlinks failed to create, please check error messages" -ForegroundColor Red
}

Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

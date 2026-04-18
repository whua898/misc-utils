# Restore C drive symlinks with auto-migration
# Requires administrator privileges
# Used after system reinstallation to quickly rebuild all symlinks
# Features: Skip if exists, auto-detect locking processes, smart recovery

$ErrorActionPreference = "Continue"  # Continue on errors instead of stopping

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
        Source = "C:\Users\wh898\AppData\Local\Siemens"
        Target = "D:\Users\wh898\AppData\Local\Siemens"
        Description = "Siemens software data (NX, Solid Edge, etc.)"
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
Write-Host "Running with administrator privileges: $(([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))" -ForegroundColor Cyan
Write-Host ""
Write-Host "Mode: Auto-migrate C: data to D: and create symlinks" -ForegroundColor Green
Write-Host ""

# Statistics
$successCount = 0
$skipCount = 0
$failCount = 0
$manualCount = 0
$migrateCount = 0
$global:autoCreateDirs = $false  # Auto-create missing directories

# Function to copy directory with progress
function Copy-DirectoryWithProgress {
    param(
        [string]$SourcePath,
        [string]$TargetPath
    )
    
    Write-Host "  Starting data migration..." -ForegroundColor Cyan
    Write-Host "  From: $SourcePath" -ForegroundColor Gray
    Write-Host "  To:   $TargetPath" -ForegroundColor Gray
    
    try {
        # Create target directory if not exists
        if (-not (Test-Path $TargetPath)) {
            New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
        }
        
        # Use robocopy for reliable copy with progress
        $robocopyArgs = @(
            $SourcePath.TrimEnd('\'),
            $TargetPath.TrimEnd('\'),
            '/E',           # Copy subdirectories including empty ones
            '/COPY:DAT',    # Copy Data, Attributes, Timestamps
            '/R:3',         # Retry 3 times on failure
            '/W:5',         # Wait 5 seconds between retries
            '/NP',          # No progress (we'll show our own)
            '/NFL',         # No file list
            '/NDL'          # No directory list
        )
        
        Write-Host "  Copying files (this may take a while)..." -ForegroundColor Yellow
        $result = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -NoNewWindow -PassThru
        
        if ($result.ExitCode -lt 8) {
            Write-Host "  [OK] Data migration completed" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  [FAIL] Robocopy failed with exit code: $($result.ExitCode)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  [FAIL] Migration error: $_" -ForegroundColor Red
        return $false
    }
}

# Function to detect and kill processes using a path (optimized)
function Stop-ProcessesUsingPath {
    param(
        [string]$Path
    )
    
    Write-Host "  Checking for locking processes..." -ForegroundColor Cyan
    
    try {
        $lockingProcesses = @()
        
        # Method 1: Use openfiles command (built-in Windows tool)
        try {
            $openfilesOutput = openfiles /query /fo CSV 2>$null | ConvertFrom-Csv
            $lockingProcesses += $openfilesOutput | Where-Object {
                $_.'Accessed By' -ne 'N/A' -and 
                $_.'Open File (Path\executable)' -like "$Path*"
            } | Select-Object -Unique 'ID Process', 'Accessed By'
        } catch {
            # openfiles may not be available or enabled
        }
        
        # Method 2: Check common applications by name pattern
        if ($lockingProcesses.Count -eq 0) {
            $pathLower = $Path.ToLower()
            $processPatterns = @()
            
            # Extract keywords from path to match process names
            if ($pathLower -like '*siemens*' -or $pathLower -like '*nx*' -or $pathLower -like '*solidedge*') {
                $processPatterns += 'ug*', 'nx*', 'solid*', 'teamcenter*'
            }
            if ($pathLower -like '*logitech*' -or $pathLower -like '*logi*') {
                $processPatterns += 'logi*', 'lghub*'
            }
            if ($pathLower -like '*adobe*') {
                $processPatterns += 'adobe*', 'photoshop*', 'illustrator*'
            }
            if ($pathLower -like '*autodesk*') {
                $processPatterns += 'autodesk*', 'acad*', 'revit*'
            }
            if ($pathLower -like '*android*') {
                $processPatterns += 'adb*', 'android*', 'emulator*'
            }
            if ($pathLower -like '*java*') {
                $processPatterns += 'java*', 'jdk*'
            }
            if ($pathLower -like '*fiddler*') {
                $processPatterns += 'fiddler*'
            }
            if ($pathLower -like '*studio*' -or $pathLower -like '*code*') {
                $processPatterns += 'code*', 'studio*', 'devenv*'
            }
            if ($pathLower -like '*lingma*' -or $pathLower -like '*tongyi*') {
                $processPatterns += 'lingma*', 'tongyi*'
            }
            if ($pathLower -like '*lmstudio*') {
                $processPatterns += 'lmstudio*'
            }
            if ($pathLower -like '*cherrystudio*') {
                $processPatterns += 'cherry*', 'studio*'
            }
            if ($pathLower -like '*claude*') {
                $processPatterns += 'claude*'
            }
            if ($pathLower -like '*cline*') {
                $processPatterns += 'cline*'
            }
            if ($pathLower -like '*gemini*') {
                $processPatterns += 'gemini*'
            }
            if ($pathLower -like '*qwen*') {
                $processPatterns += 'qwen*'
            }
            
            # Always check explorer as it commonly locks folders
            $processPatterns += 'explorer'
            
            foreach ($pattern in $processPatterns) {
                $procs = Get-Process -Name $pattern -ErrorAction SilentlyContinue
                if ($procs) {
                    $lockingProcesses += $procs | Select-Object Id, ProcessName, @{N='Info';E={'Matched by name pattern'}}
                }
            }
        }
        
        if ($lockingProcesses.Count -eq 0) {
            Write-Host "  [OK] No locking processes detected" -ForegroundColor Green
            return $true
        }
        
        Write-Host "  Found $($lockingProcesses.Count) potential locking process(es):" -ForegroundColor Yellow
        foreach ($proc in $lockingProcesses) {
            $procName = if ($proc.'Accessed By') { $proc.'Accessed By' } else { $proc.ProcessName }
            $procId = if ($proc.'ID Process') { $proc.'ID Process' } else { $proc.Id }
            Write-Host "    - $procName (PID: $procId)" -ForegroundColor Gray
        }
        
        Write-Host "  Attempting to stop processes..." -ForegroundColor Cyan
        
        $stoppedCount = 0
        $failedCount = 0
        
        foreach ($proc in $lockingProcesses) {
            $procId = if ($proc.'ID Process') { [int]$proc.'ID Process' } else { $proc.Id }
            $procName = if ($proc.'Accessed By') { $proc.'Accessed By' } else { $proc.ProcessName }
            
            # Skip critical system processes
            if ($procName -eq 'explorer') {
                Write-Host "    Skipping explorer.exe (system process)" -ForegroundColor Yellow
                continue
            }
            
            try {
                Write-Host "    Stopping $procName (PID: $procId)..." -ForegroundColor Gray
                Stop-Process -Id $procId -Force -ErrorAction Stop
                
                # Wait for process to exit
                $waitCount = 0
                while ((Get-Process -Id $procId -ErrorAction SilentlyContinue) -and $waitCount -lt 10) {
                    Start-Sleep -Milliseconds 500
                    $waitCount++
                }
                
                if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) {
                    Write-Host "    [OK] Stopped successfully" -ForegroundColor Green
                    $stoppedCount++
                } else {
                    Write-Host "    [WARN] Process still running" -ForegroundColor Yellow
                    $failedCount++
                }
            } catch {
                Write-Host "    [WARN] Could not stop $procName`: $_" -ForegroundColor Yellow
                $failedCount++
            }
        }
        
        Write-Host "  Result: $stoppedCount stopped, $failedCount failed" -ForegroundColor Cyan
        
        # Wait for file handles to be released
        Start-Sleep -Seconds 2
        
        return $true
    } catch {
        Write-Host "  [WARN] Process detection error: $_" -ForegroundColor Yellow
        return $true  # Continue anyway
    }
}

foreach ($link in $symlinks) {
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "[$($symlinks.IndexOf($link) + 1)/$($symlinks.Count)] $($link.Description)" -ForegroundColor Cyan

    # Check if manual confirmation is needed
    if ($link.ManualCheck) {
        Write-Host "Status: [SKIP] Manual verification required" -ForegroundColor Yellow
        Write-Host "Source: $($link.Source)" -ForegroundColor Gray
        Write-Host "Target: $($link.Target)" -ForegroundColor Gray
        Write-Host "Tip: Check backup to determine correct target path" -ForegroundColor Yellow
        $manualCount++
        continue
    }

    Write-Host "Source: $($link.Source)" -ForegroundColor Green
    Write-Host "Target: $($link.Target)" -ForegroundColor Green

    # Check if source already exists as symlink
    if (Test-Path $link.Source) {
        try {
            $item = Get-Item $link.Source -ErrorAction Stop
            if ($item.Attributes -match "ReparsePoint") {
                Write-Host "Status: [OK] Symlink already exists, skipping" -ForegroundColor Green
                $skipCount++
                continue
            } else {
                Write-Host "Warning: Source exists but is not a symlink!" -ForegroundColor Yellow
                Write-Host "  Auto-migrating data from C: to D:..." -ForegroundColor Cyan
                
                # Check if target already has data
                $targetHasData = $false
                if (Test-Path $link.Target) {
                    $targetItems = Get-ChildItem $link.Target -ErrorAction SilentlyContinue
                    if ($targetItems) {
                        $targetHasData = $true
                    }
                }
                
                # If target doesn't have data, copy from source
                if (-not $targetHasData) {
                    Write-Host "  Copying data from C: to D:..." -ForegroundColor Cyan
                    
                    # Create target directory if needed
                    if (-not (Test-Path $link.Target)) {
                        New-Item -ItemType Directory -Path $link.Target -Force | Out-Null
                    }
                    
                    # Use robocopy to migrate data (properly quote paths with spaces)
                    $sourcePath = "`"$($link.Source.TrimEnd('\'))`""
                    $targetPath = "`"$($link.Target.TrimEnd('\'))`""
                    
                    $robocopyArgs = @(
                        $sourcePath,
                        $targetPath,
                        '/E',           # Copy subdirectories including empty ones
                        '/COPY:DAT',    # Copy Data, Attributes, Timestamps
                        '/R:2',         # Retry 2 times on failure
                        '/W:3',         # Wait 3 seconds between retries
                        '/NP',          # No progress
                        '/NFL',         # No file list
                        '/NDL'          # No directory list
                    )
                    
                    $result = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -NoNewWindow -PassThru
                    
                    if ($result.ExitCode -lt 8) {
                        Write-Host "  [OK] Data migrated successfully" -ForegroundColor Green
                        $migrateCount++
                    } else {
                        Write-Host "  [WARN] Robocopy exit code: $($result.ExitCode)" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "  Target already has data, skipping copy" -ForegroundColor Cyan
                }
                
                # Now delete the source directory
                Write-Host "  Removing source directory from C:..." -ForegroundColor Cyan
                
                $deleteSuccess = $false
                $maxRetries = 3
                
                for ($retry = 1; $retry -le $maxRetries; $retry++) {
                    try {
                        Remove-Item $link.Source -Recurse -Force -ErrorAction Stop
                        Write-Host "  Deleted source directory" -ForegroundColor Green
                        $deleteSuccess = $true
                        Start-Sleep -Seconds 1
                        break
                    } catch {
                        if ($retry -lt $maxRetries) {
                            Write-Host "  [WARN] Delete attempt $retry failed: $_" -ForegroundColor Yellow
                            Write-Host "  Attempting to stop processes and retry..." -ForegroundColor Cyan
                            
                            # More aggressive process detection
                            Stop-ProcessesUsingPath -Path $link.Source
                            
                            # Also try to find any process with the path in command line
                            $pathKeyword = Split-Path $link.Source -Leaf
                            $procs = Get-WmiObject Win32_Process | Where-Object {
                                $_.CommandLine -like "*$pathKeyword*"
                            }
                            
                            if ($procs) {
                                foreach ($proc in $procs) {
                                    try {
                                        Write-Host "    Terminating: $($proc.Name) (PID: $($proc.ProcessId))" -ForegroundColor Gray
                                        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                                        Start-Sleep -Milliseconds 500
                                    } catch {
                                        # Ignore errors
                                    }
                                }
                            }
                            
                            Write-Host "  Retry $retry/$maxRetries..." -ForegroundColor Cyan
                            Start-Sleep -Seconds 2
                        } else {
                            Write-Host "  [FAIL] Could not delete after $maxRetries attempts: $_" -ForegroundColor Red
                            Write-Host "  Please manually close applications using: $pathKeyword" -ForegroundColor Yellow
                            Write-Host "  Skipping this item" -ForegroundColor Yellow
                            $failCount++
                            continue
                        }
                    }
                }
                
                if (-not $deleteSuccess) {
                    continue
                }
            }
        } catch {
            Write-Host "Warning: Could not check source path: $_" -ForegroundColor Yellow
        }
    }

    # Check if target exists, create if not
    if (-not (Test-Path $link.Target)) {
        Write-Host "Warning: Target does not exist: $($link.Target)" -ForegroundColor Yellow
        
        # For volume mounts, skip creation
        if ($link.Target -like "Volume{*") {
            Write-Host "  Skipping volume mount creation (system managed)" -ForegroundColor Cyan
            $failCount++
            continue
        }
        
        # Auto-create empty directory (no prompt)
        Write-Host "  Creating directory for future use..." -ForegroundColor Cyan
        try {
            New-Item -ItemType Directory -Path $link.Target -Force -ErrorAction Stop | Out-Null
            Write-Host "  [OK] Directory created: $($link.Target)" -ForegroundColor Green
        } catch {
            Write-Host "  [FAIL] Could not create directory: $_" -ForegroundColor Red
            $failCount++
            continue
        }
    }

    # Create symlink
    try {
        Write-Host "Creating symlink..." -ForegroundColor Green
        
        # Before creating symlink, check if anything is blocking
        if (Test-Path $link.Source) {
            Write-Host "  Warning: Source path still exists, attempting to clear..." -ForegroundColor Yellow
            Stop-ProcessesUsingPath -Path $link.Source
            
            try {
                Remove-Item $link.Source -Recurse -Force -ErrorAction Stop
                Write-Host "  Cleared existing path" -ForegroundColor Green
                Start-Sleep -Seconds 1
            } catch {
                Write-Host "  [WARN] Could not remove existing path: $_" -ForegroundColor Yellow
                Write-Host "  Will attempt to create symlink anyway..." -ForegroundColor Yellow
            }
        }
        
        # Create the symlink with force flag
        $symlinkResult = New-Item -ItemType SymbolicLink -Path $link.Source -Target $link.Target -Force -ErrorAction Stop

        # Verify the symlink was created correctly
        Start-Sleep -Milliseconds 500
        $verifyItem = Get-Item $link.Source -ErrorAction Stop
        if ($verifyItem.Attributes -match "ReparsePoint") {
            $actualTarget = $verifyItem.Target
            Write-Host "[OK] Symlink created successfully!" -ForegroundColor Green
            Write-Host "  Points to: $actualTarget" -ForegroundColor Gray
            $successCount++
        } else {
            Write-Host "[FAIL] Symlink verification failed - not a reparse point" -ForegroundColor Red
            $failCount++
        }
    } catch {
        Write-Host "[FAIL] Creation failed: $_" -ForegroundColor Red
        Write-Host "  Common solutions:" -ForegroundColor Yellow
        Write-Host "    1. Run as Administrator" -ForegroundColor Gray
        Write-Host "    2. Close applications using this path" -ForegroundColor Gray
        Write-Host "    3. Check if target path exists" -ForegroundColor Gray
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
Write-Host "Summary:" -ForegroundColor White
Write-Host "  Successfully created : $successCount" -ForegroundColor Green
Write-Host "  Already exists      : $skipCount" -ForegroundColor Yellow
Write-Host "  Failed              : $failCount" -ForegroundColor Red
Write-Host "  Manual handling     : $manualCount" -ForegroundColor Yellow
Write-Host "  Data migrated       : $migrateCount" -ForegroundColor Cyan
Write-Host ""

if ($successCount -gt 0) {
    Write-Host "✓ Successfully restored $successCount symlinks" -ForegroundColor Green
}

if ($manualCount -gt 0) {
    Write-Host "Note: $manualCount symlink(s) require manual target path verification" -ForegroundColor Yellow
    Write-Host "Recommendations:" -ForegroundColor Yellow
    Write-Host "  1. Check backup for original target paths" -ForegroundColor Gray
    Write-Host "  2. Or use command to view existing symlinks:" -ForegroundColor Yellow
    Write-Host '     Get-ChildItem <path> -Attributes ReparsePoint | Select-Object FullName, Target' -ForegroundColor Gray
    Write-Host ""
}

if ($failCount -gt 0) {
    Write-Host "Warning: $failCount symlink(s) failed to create" -ForegroundColor Red
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Run script as Administrator" -ForegroundColor Gray
    Write-Host "  2. Close applications that may be using these paths" -ForegroundColor Gray
    Write-Host "  3. Manually check error messages above" -ForegroundColor Gray
    Write-Host ""
}

if ($failCount -eq 0 -and $manualCount -eq 0) {
    Write-Host "All symlinks restored successfully!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

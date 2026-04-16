# Migrate LM Studio and VisualStudio directories to D drive with symbolic links
# Requires administrator privileges

$ErrorActionPreference = "Stop"

Write-Host "=== Start migrating large directories to D drive ===" -ForegroundColor Cyan
Write-Host ""

$migrations = @(
    @{
        Source = "C:\Users\wh898\.lmstudio"
        TargetBase = "D:\Users\wh898"
        Description = "LM Studio AI models and configs"
    },
    @{
        Source = "C:\ProgramData\Microsoft\VisualStudio"
        TargetBase = "D:\ProgramData\Microsoft"
        Description = "Visual Studio shared data"
    }
)

foreach ($migration in $migrations) {
    $sourceDir = $migration.Source
    $dirName = Split-Path $sourceDir -Leaf
    $targetDir = Join-Path $migration.TargetBase $dirName
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Processing: $($migration.Description)" -ForegroundColor Yellow
    Write-Host "Source: $sourceDir" -ForegroundColor Gray
    Write-Host "Target: $targetDir" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if source directory exists
    if (-not (Test-Path $sourceDir)) {
        Write-Host "Source directory does not exist, skipping" -ForegroundColor Gray
        Write-Host ""
        continue
    }
    
    # Check if already a symlink
    $item = Get-Item $sourceDir
    if ($item.Attributes -match "ReparsePoint") {
        Write-Host "Already a symbolic link, skipping" -ForegroundColor Gray
        Write-Host ""
        continue
    }
    
    # Calculate source directory size
    $sizeGB = [math]::Round((Get-ChildItem $sourceDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
    Write-Host "Directory size: $sizeGB GB" -ForegroundColor Green
    Write-Host ""
    
    # Step 1: Find and terminate占用 processes
    Write-Host "[1/5] Checking for locking processes..." -ForegroundColor Green
    
    $processesToCheck = @()
    if ($dirName -eq ".lmstudio") {
        $processesToCheck = @("LM Studio", "lmstudio", "lm-studio")
    } elseif ($dirName -eq "VisualStudio") {
        $processesToCheck = @("devenv", "VisualStudio", "ServiceHub", "VSHub", "Microsoft.ServiceHub")
    }
    
    foreach ($procName in $processesToCheck) {
        $processes = Get-Process | Where-Object { $_.ProcessName -like "*$procName*" -or $_.MainWindowTitle -like "*$procName*" }
        foreach ($proc in $processes) {
            try {
                Write-Host "  Terminating: $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Yellow
                Stop-Process -Id $proc.Id -Force
                Start-Sleep -Milliseconds 500
            } catch {
                Write-Host "  Cannot terminate $($proc.ProcessName): $_" -ForegroundColor Red
            }
        }
    }
    
    Write-Host "  Waiting for processes to exit..." -ForegroundColor Gray
    Start-Sleep -Seconds 3
    
    # Step 2: Create target directory
    Write-Host "[2/5] Creating target directory..." -ForegroundColor Green
    if (-not (Test-Path $migration.TargetBase)) {
        New-Item -ItemType Directory -Path $migration.TargetBase -Force | Out-Null
        Write-Host "  Created: $($migration.TargetBase)" -ForegroundColor Green
    }
    
    # Step 3: Copy data to D drive
    Write-Host "[3/5] Copying data to D drive (this may take a few minutes)..." -ForegroundColor Green
    if (Test-Path $targetDir) {
        Write-Host "  Warning: Target directory exists, will be deleted first" -ForegroundColor Yellow
        Remove-Item $targetDir -Recurse -Force
    }
    
    try {
        $robocopyArgs = @("`"$sourceDir`"", "`"$targetDir`"", "/E", "/COPY:DAT", "/R:3", "/W:5", "/NFL", "/NDL", "/NP")
        Write-Host "  Copying..." -ForegroundColor Gray
        $result = Start-Process "robocopy.exe" -ArgumentList $robocopyArgs -Wait -NoNewWindow -PassThru
        
        if ($result.ExitCode -lt 8) {
            Write-Host "  [OK] Data copied successfully" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] Robocopy exit code: $($result.ExitCode)" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [FAIL] Copy failed: $_" -ForegroundColor Red
        Write-Host "  Trying Copy-Item..." -ForegroundColor Yellow
        
        try {
            Copy-Item -Path "$sourceDir\*" -Destination $targetDir -Recurse -Force
            Write-Host "  [OK] Data copied (Copy-Item)" -ForegroundColor Green
        } catch {
            Write-Host "  [FAIL] Copy failed: $_" -ForegroundColor Red
            Write-Host "  Please close related programs manually and retry" -ForegroundColor Red
            Write-Host ""
            continue
        }
    }
    
    # Verify copy success
    if (-not (Test-Path $targetDir)) {
        Write-Host "  [FAIL] Target directory verification failed, skipping" -ForegroundColor Red
        Write-Host ""
        continue
    }
    
    # Verify file size
    $targetSizeGB = [math]::Round((Get-ChildItem $targetDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
    Write-Host "  Target directory size: $targetSizeGB GB" -ForegroundColor Gray
    
    $sizeDiff = [math]::Abs($sizeGB - $targetSizeGB)
    if ($sizeDiff -gt 1) {
        Write-Host "  [WARN] Size difference is large ($([math]::Round($sizeDiff, 2)) GB)" -ForegroundColor Yellow
    } else {
        Write-Host "  [OK] File size verified" -ForegroundColor Green
    }
    
    # Step 4: Delete original directory
    Write-Host "[4/5] Deleting original directory..." -ForegroundColor Green
    try {
        Remove-Item $sourceDir -Recurse -Force
        Write-Host "  [OK] Original directory deleted" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] Failed to delete original directory: $_" -ForegroundColor Red
        Write-Host "  Please delete manually and rerun script" -ForegroundColor Yellow
        
        if (Test-Path $sourceDir) {
            Write-Host ""
            continue
        }
    }
    
    # Step 5: Create symbolic link
    Write-Host "[5/5] Creating symbolic link..." -ForegroundColor Green
    try {
        New-Item -ItemType SymbolicLink -Path $sourceDir -Target $targetDir -Force | Out-Null
        Write-Host "  [OK] Symbolic link created!" -ForegroundColor Green
        
        # Verify symlink
        $link = Get-Item $sourceDir
        if ($link.Attributes -match "ReparsePoint") {
            Write-Host "  [OK] Symlink verified" -ForegroundColor Green
            Write-Host "  $sourceDir -> $targetDir" -ForegroundColor Gray
        } else {
            Write-Host "  [FAIL] Symlink verification failed" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [FAIL] Failed to create symlink: $_" -ForegroundColor Red
        Write-Host "  Please run as administrator" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "=== Migration Complete ===" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Recommendations:" -ForegroundColor Yellow
Write-Host "1. Restart related applications to verify functionality" -ForegroundColor Gray
Write-Host "2. Check D drive space usage" -ForegroundColor Gray
Write-Host "3. If issues occur, delete symlinks and restore data" -ForegroundColor Gray
Write-Host ""

# Show final status
Write-Host "Current symlink status:" -ForegroundColor Cyan
foreach ($migration in $migrations) {
    $sourceDir = $migration.Source
    if (Test-Path $sourceDir) {
        $item = Get-Item $sourceDir
        if ($item.Attributes -match "ReparsePoint") {
            Write-Host "  [OK] $sourceDir" -ForegroundColor Green
            Write-Host "    -> $($item.Target)" -ForegroundColor Gray
        } else {
            Write-Host "  [FAIL] $sourceDir (not a symlink)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [?] $sourceDir (does not exist)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

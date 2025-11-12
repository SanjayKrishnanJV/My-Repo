# Requires PowerShell 5.1 or later
Add-Type -AssemblyName System.Collections

# Prompt user for inputs
$SourcePath = Read-Host "Enter the source folder path"
$LastAccessDuration = Read-Host "Enter the last access duration in days"
$MoveOrDelete = Read-Host "Choose an option`n1. Move`n2. Delete"
$DryRun = Read-Host "Enable Dry-Run mode? (Y/N)"
$Resume = Read-Host "Resume from previous run? (Y/N)"

if ($MoveOrDelete -eq "1") {
    $TargetPath = Read-Host "Enter the target folder path for moved files"
}

# Validate inputs
if (-Not (Test-Path $SourcePath)) { Write-Host "Source folder does not exist."; exit }
if ($MoveOrDelete -ne "1" -and $MoveOrDelete -ne "2") { Write-Host "Invalid option."; exit }
if ($MoveOrDelete -eq "1" -and (-Not $TargetPath)) { Write-Host "Target path required."; exit }
if ($MoveOrDelete -eq "1" -and (-Not (Test-Path $TargetPath))) { New-Item -Path $TargetPath -ItemType Directory }

$ThresholdDate = (Get-Date).AddDays(-[int]$LastAccessDuration)
$LogFile = Join-Path $SourcePath "FileCleanupLog.txt"
$StateFile = Join-Path $SourcePath "FileCleanupState.txt"

Write-Host "Logging actions to: $LogFile"
Write-Host "State tracking file: $StateFile"

# Thread-safe counters
$MovedCount = [System.Threading.Interlocked]::Increment(0)
$DeletedCount = [System.Threading.Interlocked]::Increment(0)

# Collect all files
$Files = Get-ChildItem -Path $SourcePath -File -Recurse
$TotalFiles = $Files.Count
$StartTime = Get-Date

# Resume logic
$ProcessedFiles = 0
$ProcessedSet = @{}
if ($Resume -eq "Y" -and (Test-Path $StateFile)) {
    $ProcessedSet = Get-Content $StateFile | ForEach-Object { $_ }
    Write-Host "Resuming from previous run. Skipping $($ProcessedSet.Count) files..."
    $Files = $Files | Where-Object { $_.FullName -notin $ProcessedSet }
    $TotalFiles = $Files.Count
}

# Chunking logic
$ChunkSize = 5000
$Chunks = [System.Collections.Generic.List[object]]::new()
for ($i = 0; $i -lt $TotalFiles; $i += $ChunkSize) {
    $Chunks.Add($Files[$i..([Math]::Min($i + $ChunkSize - 1, $TotalFiles - 1))])
}

# Create Runspace Pool
$MaxThreads = 20
$RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads)
$RunspacePool.Open()

foreach ($Chunk in $Chunks) {
    $Jobs = @()
    foreach ($File in $Chunk) {
        $PowerShell = [powershell]::Create()
        $PowerShell.RunspacePool = $RunspacePool

        $PowerShell.AddScript({
            param($File, $MoveOrDelete, $TargetPath, $ThresholdDate, $DryRun, $LogFile, $StateFile)

            if ($File.LastAccessTime -lt $ThresholdDate) {
                $FileSizeMB = [math]::Round($File.Length / 1MB, 2)
                $LastAccess = $File.LastAccessTime.ToString('yyyy-MM-dd HH:mm:ss')

                if ($DryRun -eq "Y") {
                    $logEntry = "Dry-Run: Would $((if ($MoveOrDelete -eq '1') {'Move'} else {'Delete'})) -> $($File.FullName) | Size: ${FileSizeMB}MB | LastAccess: $LastAccess"
                    Add-Content -Path $LogFile -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) | $logEntry"
                } else {
                    try {
                        if ($MoveOrDelete -eq "1") {
                            Move-Item -Path $File.FullName -Destination $TargetPath -Force
                            [System.Threading.Interlocked]::Increment([ref]$using:MovedCount)
                        } elseif ($MoveOrDelete -eq "2") {
                            Remove-Item -Path $File.FullName -Force
                            [System.Threading.Interlocked]::Increment([ref]$using:DeletedCount)
                        }
                        $logEntry = "$((if ($MoveOrDelete -eq '1') {'Moved'} else {'Deleted'})): $($File.FullName) | Size: ${FileSizeMB}MB | LastAccess: $LastAccess"
                        Add-Content -Path $LogFile -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) | $logEntry"
                    } catch {
                        $errorEntry = "Error processing file: $($File.FullName) - $($_.Exception.Message)"
                        Add-Content -Path $LogFile -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) | $errorEntry"
                    }
                }
                # Mark file as processed
                Add-Content -Path $StateFile -Value $File.FullName
            }
        }).AddArgument($File).AddArgument($MoveOrDelete).AddArgument($TargetPath).AddArgument($ThresholdDate).AddArgument($DryRun).AddArgument($LogFile).AddArgument($StateFile)

        $Jobs += [PSCustomObject]@{ Pipe = $PowerShell; Handle = $PowerShell.BeginInvoke() }
    }

    foreach ($Job in $Jobs) {
        $Job.Pipe.EndInvoke($Job.Handle)
        $Job.Pipe.Dispose()
        $ProcessedFiles++
        # Real-time dashboard
        $Elapsed = (Get-Date) - $StartTime
        $Rate = if ($ProcessedFiles -gt 0) { $Elapsed.TotalSeconds / $ProcessedFiles } else { 0 }
        $Remaining = $TotalFiles - $ProcessedFiles
        $ETA = if ($Rate -gt 0) { [TimeSpan]::FromSeconds($Remaining * $Rate) } else { [TimeSpan]::Zero }
        $Speed = if ($Elapsed.TotalSeconds -gt 0) { [math]::Round($ProcessedFiles / $Elapsed.TotalSeconds, 2) } else { 0 }
        Write-Progress -Activity "Processing Files" -Status "Processed: $ProcessedFiles / $TotalFiles | Speed: $Speed files/sec | ETA: $($ETA.ToString())" -PercentComplete (($ProcessedFiles / $TotalFiles) * 100)
    }
}

$RunspacePool.Close()
$RunspacePool.Dispose()

# Delete empty folders after cleanup
Write-Host "Deleting empty folders..."
Get-ChildItem -Path $SourcePath -Directory -Recurse | Where-Object { (Get-ChildItem $_.FullName -Force).Count -eq 0 } | Remove-Item -Force

# Summary
$Summary = @"
Operation Completed:
--------------------
Dry-Run Mode: $DryRun
Total Files Moved: $MovedCount
Total Files Deleted: $DeletedCount
Log File: $LogFile
State File: $StateFile
"@
Write-Host $Summary -ForegroundColor Cyan
Add-Content -Path $LogFile -Value $Summary
# Prompt user for inputs
$SourcePath = Read-Host "Enter the source folder path"
$LastAccessDuration = Read-Host "Enter the last access duration in days"
$MoveOrDelete = Read-Host "Choose an option`n1. Move`n2. Delete"
$DryRun = Read-Host "Enable Dry-Run mode? (Y/N)"

# If operation is "Move," prompt for target path
if ($MoveOrDelete -eq "1") {
    $TargetPath = Read-Host "Enter the target folder path for moved files"
}

# Validate inputs
if (-Not (Test-Path $SourcePath)) {
    Write-Host "The source folder does not exist. Please check the path."
    exit
}

if ($MoveOrDelete -ne "1" -and $MoveOrDelete -ne "2") {
    Write-Host "Invalid operation specified. Use 1 to move the files to a specific folder or 2 to delete the files."
    exit
}

if ($MoveOrDelete -eq "1" -and (-Not $TargetPath)) {
    Write-Host "Target path is required for Move operation. Please provide a valid path." 
    exit
}

# Create target folder if it doesn't exist (for Move operation)
if ($MoveOrDelete -eq "1" -and (-Not (Test-Path $TargetPath))) {
    Write-Host "The target folder does not exist. Creating it..."
    New-Item -Path $TargetPath -ItemType Directory
}

# Calculate threshold date based on last access duration
$ThresholdDate = (Get-Date).AddDays(-[int]$LastAccessDuration)

# Prepare log file
$LogFile = Join-Path $SourcePath "FileCleanupLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
Write-Host "Logging actions to: $LogFile"

# Initialize counters
$MovedCount = 0
$DeletedCount = 0

# Perform operation (Move/Delete) recursively
Get-ChildItem -Path $SourcePath -File -Recurse | ForEach-Object {
    if ($_.LastAccessTime -lt $ThresholdDate) {
        $FileSizeMB = [math]::Round($_.Length / 1MB, 2)
        $LastAccess = $_.LastAccessTime.ToString('yyyy-MM-dd HH:mm:ss')

        if ($DryRun -eq "Y") {
            $logEntry = "Dry-Run: Would $((if ($MoveOrDelete -eq '1') {'Move'} else {'Delete'})) -> $($_.FullName) | Size: ${FileSizeMB}MB | LastAccess: $LastAccess"
            Write-Host $logEntry -ForegroundColor Yellow
            Add-Content -Path $LogFile -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) | $logEntry"
        } else {
            try {
                if ($MoveOrDelete -eq "1") {
                    Move-Item -Path $_.FullName -Destination $TargetPath -Force
                    $logEntry = "Moved: $($_.FullName) | Size: ${FileSizeMB}MB | LastAccess: $LastAccess -> $TargetPath"
                    Write-Host $logEntry -ForegroundColor Green
                    $MovedCount++
                } elseif ($MoveOrDelete -eq "2") {
                    Remove-Item -Path $_.FullName -Force
                    $logEntry = "Deleted: $($_.FullName) | Size: ${FileSizeMB}MB | LastAccess: $LastAccess"
                    Write-Host $logEntry -ForegroundColor Red
                    $DeletedCount++
                }
                Add-Content -Path $LogFile -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) | $logEntry"
            } catch {
                $errorEntry = "Error processing file: $($_.FullName) - $($_.Exception.Message)"
                Write-Host $errorEntry -ForegroundColor Yellow
                Add-Content -Path $LogFile -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) | $errorEntry"
            }
        }
    }
}

# Summary
$Summary = @"
Operation Completed:
--------------------
Dry-Run Mode: $DryRun
Total Files Moved: $MovedCount
Total Files Deleted: $DeletedCount
Log File: $LogFile
"@
Write-Host $Summary -ForegroundColor Cyan
Add-Content -Path $LogFile -Value $Summary
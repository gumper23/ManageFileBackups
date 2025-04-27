param (
    [Parameter(Mandatory=$true)]
    [int]$NumberOfFilesToKeep,
    [Parameter(Mandatory=$true)]
    [string]$DirectoryPath,
    [Parameter(Mandatory=$true)]
    [string]$FileSpec,
    [int]$SleepSeconds = 60
)
# Returns a list of files in the specified directory with the specified extension
function Get-FilesByExtension {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DirectoryPath,
        [Parameter(Mandatory=$true)]
        [string]$Extension
    )
    
    # Validate directory exists
    if (-not (Test-Path $DirectoryPath)) {
        throw "Directory '$DirectoryPath' does not exist"
    }
    
    # Clean extension input (remove * if present, ensure . prefix)
    $Extension = $Extension -replace '^\*', ''
    if (-not $Extension.StartsWith('.')) {
        $Extension = ".$Extension"
    }
    
    # Get matching files
    Get-ChildItem -Path $DirectoryPath -File | 
        Where-Object { $_.Extension -eq $Extension } |
        Select-Object -ExpandProperty FullName
}

# Function to check if a string ends with 14 digits
function Test-14DigitEnd {
    param ([string]$FileName)
    return $FileName -match '\d{14}$'
}

# Function to remove old backups for a specific base filename
function Remove-FilesOld {
    param (
        [string]$DirectoryPath, 
        [int]$NumberOfFilesToKeep,
        [string]$BaseFileName
    )
    # Get backup files for this base filename ending with 14 digits
    $files = Get-ChildItem -Path $DirectoryPath -File | 
             Where-Object { ($_.BaseName -eq $BaseFileName) -and (Test-14DigitEnd -FileName $_.Name) }

    # Sort by LastWriteTime (oldest first)
    $sortedFiles = $files | Sort-Object -Property LastWriteTime

    # Calculate how many files to delete
    $filesToDeleteCount = $sortedFiles.Count - $NumberOfFilesToKeep

    if ($filesToDeleteCount -gt 0) {
        # Select the oldest files to delete
        $filesToDelete = $sortedFiles | Select-Object -First $filesToDeleteCount

        # Delete the selected files
        $filesToDelete | Remove-Item -Force

        $fileString = $filesToDeleteCount -eq 1 ? "file" : "files"
        Write-Output "Deleted $filesToDeleteCount $fileString for $BaseFileName."
    }
}

# Function to compare two files binary-wise
function Compare-FilesBinary {
    param (
        [Parameter(Mandatory=$true)]
        [string]$File1,
        [Parameter(Mandatory=$true)]
        [string]$File2,
        [uint32]$bufferSize = 524288
    )

    $file1Info = Get-Item $File1
    $file2Info = Get-Item $File2
    if ($file1Info.Length -ne $file2Info.Length) {
        return $false
    }

    if ($bufferSize -eq 0) {
        $bufferSize = 524288
    }

    $fs1 = $file1Info.OpenRead()
    $fs2 = $file2Info.OpenRead()
    $one = New-Object byte[] $bufferSize
    $two = New-Object byte[] $bufferSize
    $equal = $true

    try {
        do {
            $bytesRead = $fs1.Read($one, 0, $bufferSize)
            $fs2.Read($two, 0, $bufferSize) | Out-Null
            if (-Not [System.Linq.Enumerable]::SequenceEqual($one, $two)) {
                $equal = $false
                break
            }
        } while ($bytesRead -eq $bufferSize)
    }
    finally {
        $fs1.Close()
        $fs2.Close()
    }

    return $equal
}

# Function to handle backup creation for a single file

function Backup-File {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FullFileName
    )

    $compareToFileName = Join-Path -Path $DirectoryPath -ChildPath $FileName
    $files = Get-ChildItem -Path $DirectoryPath -File | Where-Object { Test-14DigitEnd -FileName $_.Name }
    $sortedFiles = $files | Sort-Object -Property LastWriteTime -Descending

    if ($sortedFiles.Count -gt 0) {
        $mostRecentFile = $sortedFiles[0].FullName
        $areEqual = Compare-FilesBinary -File1 $compareToFileName -File2 $mostRecentFile
        if (-Not $areEqual) {
            $dateTime = Get-Date -Format "yyyyMMddHHmmss"
            $newFileName = $compareToFileName + "." + $dateTime
            Copy-Item -Path $compareToFileName -Destination $newFileName
            Write-Output "Copied $compareToFileName to $newFileName."
        }
    } else {
        # Create initial backup if no previous backups exist
        $dateTime = Get-Date -Format "yyyyMMddHHmmss"
        $newFileName = $compareToFileName + "." + $dateTime
        Copy-Item -Path $compareToFileName -Destination $newFileName
        Write-Output "Created initial backup: $compareToFileName to $newFileName."
    }

    # Compare the most recent backup file with the current file. If they are not equal, create a new backup file and exit.
    $mostRecentBackup = $backupFiles[0].FullName
    $areEqual = Compare-FilesBinary -File1 $FullFileName -File2 $mostRecentBackup
    if (-not $areEqual) {
        Write-Output "$fileName differs from latest backup. Creating new backup."
        $fileInfo.CopyTo($backupFilePath, $true)
        return
    } 
}

while ($true) {
    $filesToBeBackedup = Get-FilesByExtension -DirectoryPath $DirectoryPath -Extension $FileSpec
    foreach ($file in $filesToBeBackedup) {
        Write-Output "Processing file: $file"
        Backup-File -FullFileName $file
        Remove-FilesOld -DirectoryPath $DirectoryPath -NumberOfFilesToKeep $NumberOfFilesToKeep -BaseFileName Split-Path $file
    }
    Start-Sleep -Seconds $SleepSeconds
}
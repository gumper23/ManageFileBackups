param (
    [Parameter(Mandatory=$true)]
    [int]$NumberOfFilesToKeep,
    [Parameter(Mandatory=$true)]
    [string]$DirectoryPath,
    [Parameter(Mandatory=$true)]
    [string]$FileName,
    [int]$SleepSeconds = 60
)

# Function to check if a string ends with 14 digits
function Test-14DigitEnd {
    param ([string]$FileName)
    return $FileName -match '\d{14}$'
}

# Function to remove old files based on the number of files to keep
function Remove-FilesOld {
    param ([string]$DirectoryPath, [int]$NumberOfFilesToKeep)
    # Get the list of files that end with 14 digits
    $files = Get-ChildItem -Path $DirectoryPath -File | Where-Object { Test-14DigitEnd -FileName $_.Name }

    # Sort files by LastWriteTime (oldest first)
    $sortedFiles = $files | Sort-Object -Property LastWriteTime

    # Calculate how many files to delete
    $filesToDeleteCount = $sortedFiles.Count - $NumberOfFilesToKeep

    if ($filesToDeleteCount -gt 0) {
        # Select the oldest files to delete
        $filesToDelete = $sortedFiles | Select-Object -First $filesToDeleteCount

        # Delete the selected files
        $filesToDelete | Remove-Item -Force

        if ($filesToDeleteCount -eq 1) {
            $fileString = "file"
        } else {
            $fileString = "files"
        }
        Write-Output "Deleted $($filesToDeleteCount) $fileString."
    } else {
        Write-Output "No files need to be deleted; the directory already contains $($NumberOfFilesToKeep) or fewer files."
    }
}

function Compare-FilesBinary {
    param (
        [Parameter(Mandatory=$true)]
        [string]$File1,
        [Parameter(Mandatory=$true)]
        [string]$File2,
        [uint32]$bufferSize = 524288 # 512 KB buffer size, can be adjusted
    )

    # Check if file sizes are different first for a quick comparison
    $file1Info = Get-Item $File1
    $file2Info = Get-Item $File2
    if ($file1Info.Length -ne $file2Info.Length) {
        return $false
    }

    # If bufferSize is 0, set a default
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

# Compare the passed in file with the most recent file ending in a 14 digit number
function CopyFileIfDifferent {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FileName,
        [Parameter(Mandatory=$true)]
        [string]$DirectoryPath
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
}

while ($true) {
    # Example call:
    #  D:\Projects\git\github.com\gumper23\ManageFileBackups\ManageFileBackups.ps1 -NumberOfFilesToKeep 10 -DirectoryPath "C:\Users\rsmith\AppData\LocalLow\RedCandleGames\NineSols\saveslot1" -FileName "flags.sav" -SleepSeconds 120
    # Linting:
    # Invoke-ScriptAnalyzer -Path "D:\Projects\git\github.com\gumper23\ManageFileBackups\ManageFileBackups.ps1"

    # Copies the file if it is different from the most recent backup file
    CopyFileIfDifferent -FileName $FileName -DirectoryPath $DirectoryPath

    # Removes 0 or more backup files
    Remove-FilesOld -DirectoryPath $DirectoryPath -NumberOfFilesToKeep $NumberOfFilesToKeep

    # Display remaining files for verification
    Get-ChildItem -Path $DirectoryPath -File | Where-Object { Test-14DigitEnd -FileName $_.Name } | Sort-Object -Property LastWriteTime -Descending

    # Sleep for $SleepSeconds (default 1 minute) before checking again
    Start-Sleep -Seconds $SleepSeconds
}
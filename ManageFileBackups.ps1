param (
    [Parameter(Mandatory=$true)]
    [int]$NumberOfFilesToKeep,
    [Parameter(Mandatory=$true)]
    [string]$DirectoryPath,
    [Parameter(Mandatory=$true)]
    [string]$SaveFileName,
    [int]$SleepSeconds = 60
)

# Function to check if a string ends with 14 digits
function Test-14DigitEnd {
    param ([string]$SaveFileName)
    return $SaveFileName -match '\d{14}$'
}

# Function to remove old files based on the number of files to keep
function Remove-OldFiles {
    param ([string]$DirectoryPath, [int]$NumberOfFilesToKeep)
    # Get the list of files that end with 14 digits
    $files = Get-ChildItem -Path $DirectoryPath -File | Where-Object { Test-14DigitEnd -SaveFileName $_.Name }

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

function Compare-BinaryFiles {
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
function Copy-SaveGameFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SaveFileName,
        [Parameter(Mandatory=$true)]
        [string]$DirectoryPath
    )

    # Construct the full path to the file to compare with
    $compareToSaveFilename = Join-Path -Path $DirectoryPath -ChildPath $SaveFileName

    # Get the list of files that end with 14 digits
    $files = Get-ChildItem -Path $DirectoryPath -File | Where-Object { Test-14DigitEnd -SaveFileName $_.Name }

    # Sort files by LastWriteTime (most recent first)
    $sortedFiles = $files | Sort-Object -Property LastWriteTime -Descending

    if ($sortedFiles.Count -gt 0) {
        $mostRecentFile = $sortedFiles[0].FullName
        $areEqual = Compare-BinaryFiles -File1 $compareToSaveFilename -File2 $mostRecentFile
        if (-Not $areEqual) {
            $dateTime = Get-Date -Format "yyyyMMddHHmmss"
            $newSaveFileName = $compareToSaveFilename + "." + $dateTime
            Copy-Item -Path $compareToSaveFilename -Destination $newSaveFileName
            Write-Output "Copied $compareToSaveFilename to $newSaveFileName."
        }
    }
}

while ($true) {
    # Call the Copy-SaveGameFile function with the provided parameters
    Copy-SaveGameFile -SaveFileName $SaveFileName -DirectoryPath $DirectoryPath

    # Call the Remove-OldFiles function with the provided parameters
    Remove-OldFiles -DirectoryPath $DirectoryPath -NumberOfFilesToKeep $NumberOfFilesToKeep

    # Display remaining files for verification
    Get-ChildItem -Path $DirectoryPath -File | Where-Object { Test-14DigitEnd -SaveFileName $_.Name } | Sort-Object -Property LastWriteTime -Descending

    # Sleep for 1 minute before checking again
    Start-Sleep -Seconds $SleepSeconds
}
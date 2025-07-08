# S3 Directory and File Listing Generator for PowerShell
# This script generates a listing of S3 directories (and optionally files) for the search tool

param(
    [Parameter(Position=0)]
    [string[]]$Buckets,

    [switch]$All,

    [switch]$IncludeFiles,

    [string[]]$ExcludeExtensions = @(),

    [switch]$Help
)

# Show help
if ($Help) {
    Write-Host ""
    Write-Host "S3 Directory Listing Generator" -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\Generate-S3Listing.ps1 [bucket-names] [options]"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -All                List all accessible buckets"
    Write-Host "  -IncludeFiles       Include individual files (not just directories)"
    Write-Host "  -ExcludeExtensions  Comma-separated list of extensions to exclude"
    Write-Host "  -Help               Show this help message"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  # List only directories from specific bucket:"
    Write-Host "  .\Generate-S3Listing.ps1 my-bucket"
    Write-Host ""
    Write-Host "  # List directories from all buckets:"
    Write-Host "  .\Generate-S3Listing.ps1 -All"
    Write-Host ""
    Write-Host "  # Include files but exclude .tif and .tmp files:"
    Write-Host "  .\Generate-S3Listing.ps1 my-bucket -IncludeFiles -ExcludeExtensions tif,tmp"
    Write-Host ""
    Write-Host "  # Interactive mode:"
    Write-Host "  .\Generate-S3Listing.ps1"
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "S3 Directory Listing Generator" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

# Check if AWS CLI is installed
try {
    $awsVersion = aws --version 2>$null
    if (-not $awsVersion) {
        throw "AWS CLI not found"
    }
    Write-Host "AWS CLI found: $awsVersion" -ForegroundColor Green
}
catch {
    Write-Host "Error: AWS CLI is not installed. Please install it first." -ForegroundColor Red
    Write-Host "Visit: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html" -ForegroundColor Yellow
    exit 1
}

# Output file with timestamp in current directory
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputFile = "s3-listing-$timestamp.txt"
$outputPath = Join-Path -Path (Get-Location) -ChildPath $outputFile

Write-Host ""
Write-Host "Output will be saved to:" -ForegroundColor Cyan
Write-Host "  $outputPath" -ForegroundColor Yellow

# Statistics
$script:totalDirectories = 0
$script:totalFiles = 0
$script:excludedFiles = 0

# Function to extract unique directories from S3 listing
function Get-S3Directories {
    param(
        [string]$bucketName,
        [bool]$includeFiles = $false,
        [string[]]$excludeExt = @()
    )

    Write-Host ""
    Write-Host "Processing bucket: $bucketName" -ForegroundColor Yellow

    try {
        # First, get the total object count for progress tracking
        Write-Host "  Counting objects..." -ForegroundColor Gray
        $listing = aws s3 ls "s3://$bucketName" --recursive 2>$null

        if (-not $listing) {
            Write-Host "  Warning: No objects found or access denied for bucket: $bucketName" -ForegroundColor Yellow
            return $false
        }

        $totalObjects = @($listing).Count
        Write-Host "  Found $totalObjects objects to process" -ForegroundColor Cyan

        $directories = @{}
        $files = @()
        $processed = 0
        $lastProgress = 0

        foreach ($line in $listing) {
            $processed++

            # Show progress every 10%
            $currentProgress = [math]::Floor(($processed / $totalObjects) * 100)
            if ($currentProgress -ge ($lastProgress + 10)) {
                Write-Host "  Progress: $currentProgress% ($processed/$totalObjects)" -ForegroundColor Gray
                $lastProgress = $currentProgress
            }

            # Parse S3 ls output
            if ($line -match '\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+\d+\s+(.+)$') {
                $fullPath = $matches[1]

                # Extract all directory levels
                $pathParts = $fullPath -split '/'

                # Add each directory level
                for ($i = 0; $i -lt ($pathParts.Count - 1); $i++) {
                    $dirPath = ($pathParts[0..$i] -join '/')
                    if ($dirPath -and -not $directories.ContainsKey($dirPath)) {
                        $directories[$dirPath] = $true
                        $script:totalDirectories++
                    }
                }

                # Handle file if requested
                if ($includeFiles) {
                    $fileName = $pathParts[-1]
                    $shouldInclude = $true

                    # Check exclusions
                    if ($excludeExt.Count -gt 0) {
                        $extension = [System.IO.Path]::GetExtension($fileName).TrimStart('.')
                        if ($extension -and ($excludeExt -contains $extension)) {
                            $shouldInclude = $false
                            $script:excludedFiles++
                        }
                    }

                    if ($shouldInclude) {
                        $files += $fullPath
                        $script:totalFiles++
                    }
                }
            }
        }

        Write-Host "  Progress: 100% ($processed/$totalObjects) - Complete!" -ForegroundColor Green
        Write-Host "  Found $($directories.Count) unique directories" -ForegroundColor Green

        # Write results
        Write-Host "  Writing to file..." -ForegroundColor Gray

        # Write directories first
        $sortedDirs = $directories.Keys | Sort-Object
        foreach ($dir in $sortedDirs) {
            Add-Content -Path $outputFile -Value "$bucketName/$dir/" -Encoding UTF8
        }

        # Write files if requested
        if ($includeFiles) {
            Write-Host "  Found $($files.Count) files (excluded $script:excludedFiles)" -ForegroundColor Green
            $sortedFiles = $files | Sort-Object
            foreach ($file in $sortedFiles) {
                Add-Content -Path $outputFile -Value "$bucketName/$file" -Encoding UTF8
            }
        }

        Write-Host "  Bucket complete!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  Error accessing bucket: $bucketName - $_" -ForegroundColor Red
        return $false
    }
}

# Interactive mode if no parameters
if ((-not $Buckets) -and (-not $All)) {
    Write-Host ""
    Write-Host "No parameters specified. Starting interactive mode..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "What would you like to list?" -ForegroundColor Cyan
    Write-Host "1 = Directories only (default)"
    Write-Host "2 = Directories and files"
    Write-Host "3 = Exit"

    $listChoice = Read-Host "Choose option (1-3) [1]"
    if (-not $listChoice) { $listChoice = "1" }

    switch ($listChoice) {
        "2" {
            $IncludeFiles = $true
        }
        "3" {
            Write-Host "Exiting..." -ForegroundColor Yellow
            exit 0
        }
        default {
            # Default to directories only
        }
    }

    if ($IncludeFiles) {
        Write-Host ""
        $excludeInput = Read-Host "Enter file extensions to exclude (comma-separated, e.g., tif,tmp,log) [none]"
        if ($excludeInput) {
            $ExcludeExtensions = $excludeInput -split ',' | ForEach-Object { $_.Trim() }
        }
    }

    Write-Host ""
    Write-Host "Which buckets would you like to list?" -ForegroundColor Cyan
    Write-Host "1 = All accessible buckets"
    Write-Host "2 = Specific bucket(s)"
    Write-Host "3 = Exit"

    $bucketChoice = Read-Host "Choose option (1-3)"

    switch ($bucketChoice) {
        "1" {
            $All = $true
        }
        "2" {
            $bucketInput = Read-Host "Enter bucket names (space-separated)"
            $Buckets = $bucketInput -split '\s+' | Where-Object { $_ }
        }
        "3" {
            Write-Host "Exiting..." -ForegroundColor Yellow
            exit 0
        }
        default {
            Write-Host "Invalid option" -ForegroundColor Red
            exit 1
        }
    }
}

# Display current settings
Write-Host ""
Write-Host "Settings:" -ForegroundColor Cyan
if ($IncludeFiles) {
    Write-Host "  Mode: Directories and Files"
} else {
    Write-Host "  Mode: Directories Only"
}

if ($IncludeFiles -and ($ExcludeExtensions.Count -gt 0)) {
    $excludeList = $ExcludeExtensions -join ', '
    Write-Host "  Excluding extensions: $excludeList"
}

# Process buckets
$successCount = 0
$bucketList = @()

if ($All) {
    Write-Host ""
    Write-Host "Fetching all accessible buckets..." -ForegroundColor Cyan
    $allBucketsOutput = aws s3 ls
    foreach ($line in $allBucketsOutput) {
        if ($line -match '\s+(\S+)$') {
            $bucketList += $matches[1]
        }
    }
    Write-Host "Found $($bucketList.Count) buckets to process" -ForegroundColor Cyan
} else {
    $bucketList = $Buckets
    Write-Host ""
    Write-Host "Processing $($bucketList.Count) bucket(s)" -ForegroundColor Cyan
}

# Track overall progress
$totalBuckets = $bucketList.Count
$currentBucket = 0

foreach ($bucket in $bucketList) {
    $currentBucket++
    Write-Host ""
    Write-Host "[$currentBucket/$totalBuckets] " -NoNewline -ForegroundColor Magenta

    $result = Get-S3Directories -bucketName $bucket -includeFiles $IncludeFiles -excludeExt $ExcludeExtensions
    if ($result) {
        $successCount++
    }
}

# Final report
if (($successCount -gt 0) -and (Test-Path $outputFile)) {
    $lineCount = (Get-Content $outputFile | Measure-Object -Line).Lines

    Write-Host ""
    Write-Host "Success! S3 listing saved to: $outputFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "Statistics:" -ForegroundColor Cyan
    Write-Host "  Total buckets processed: $successCount"
    Write-Host "  Total unique directories: $script:totalDirectories"
    if ($IncludeFiles) {
        Write-Host "  Total files included: $script:totalFiles"
        if ($script:excludedFiles -gt 0) {
            Write-Host "  Total files excluded: $script:excludedFiles"
        }
    }
    Write-Host "  Total entries in file: $lineCount"

    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Open the S3 Semantic Search tool (HTML file) in your browser"
    Write-Host "2. Upload this file: $outputFile"
    Write-Host "3. Start searching!"

    # Show file location
    $fullPath = (Get-Item $outputFile).FullName
    Write-Host ""
    Write-Host "File location:" -ForegroundColor Yellow
    Write-Host "  $fullPath" -ForegroundColor White

    # Copy path to clipboard if possible
    try {
        $fullPath | Set-Clipboard
        Write-Host "  (Path copied to clipboard!)" -ForegroundColor Gray
    }
    catch {
        # Clipboard not available, ignore
    }

    # Show sample of output
    Write-Host ""
    Write-Host "Sample output (first 5 lines):" -ForegroundColor Gray
    $sampleLines = Get-Content $outputFile -TotalCount 5
    foreach ($line in $sampleLines) {
        Write-Host "  $line" -ForegroundColor DarkGray
    }
} else {
    Write-Host ""
    Write-Host "Error: No data was collected." -ForegroundColor Red
    if (Test-Path $outputFile) {
        Remove-Item $outputFile -ErrorAction SilentlyContinue
    }
    exit 1
}


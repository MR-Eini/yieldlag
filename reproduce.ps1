param(
    [string]$Crop = "barley",
    [int]$HarvestMonth = 6,
    [int]$LastYieldYear = 2018,
    [int]$PredictThrough = 2019,
    [string]$OutputDirectory = "outputs/package_reference"
)

$ErrorActionPreference = "Stop"
$ProjectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$RscriptCandidates = @(
    (Get-Command Rscript.exe -ErrorAction SilentlyContinue).Source,
    "C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

if (-not $RscriptCandidates) {
    throw "Rscript was not found. Install R 4.2 or newer, or add Rscript.exe to PATH."
}

$RscriptExecutable = @($RscriptCandidates)[0]
$RExecutable = Join-Path (Split-Path -Parent $RscriptExecutable) "R.exe"
$LibraryDirectory = Join-Path $ProjectDirectory ".repro-library"
New-Item -ItemType Directory -Force -Path $LibraryDirectory | Out-Null

$PreviousRLibrary = $env:R_LIBS_USER
$PreviousLang = $env:LANG
$PreviousLcAll = $env:LC_ALL
$PreviousLcType = $env:LC_CTYPE
try {
    Remove-Item Env:LANG -ErrorAction SilentlyContinue
    Remove-Item Env:LC_ALL -ErrorAction SilentlyContinue
    Remove-Item Env:LC_CTYPE -ErrorAction SilentlyContinue
    $Version = ((Get-Content -LiteralPath (Join-Path $ProjectDirectory "DESCRIPTION")) |
        Where-Object { $_ -match '^Version:\s*' }) -replace '^Version:\s*', ''
    $PackageArchive = Join-Path $ProjectDirectory "yieldlag_$Version.tar.gz"
    if (Test-Path -LiteralPath $PackageArchive) {
        Remove-Item -LiteralPath $PackageArchive -Force
    }
    Push-Location $ProjectDirectory
    try {
        & $RExecutable CMD build --no-build-vignettes $ProjectDirectory
        if ($LASTEXITCODE -ne 0) {
            throw "Package build failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
    & $RExecutable CMD INSTALL --library=$LibraryDirectory $PackageArchive
    if ($LASTEXITCODE -ne 0) {
        throw "Package installation failed with exit code $LASTEXITCODE."
    }
    $env:R_LIBS_USER = $LibraryDirectory
    & $RscriptExecutable (Join-Path $ProjectDirectory "analysis/reproduce_poland.R") `
        "--crop=$Crop" `
        "--harvest-month=$HarvestMonth" `
        "--last-yield-year=$LastYieldYear" `
        "--predict-through=$PredictThrough" `
        "--output-dir=$OutputDirectory"
    if ($LASTEXITCODE -ne 0) {
        throw "Reproduction failed with exit code $LASTEXITCODE."
    }
}
finally {
    $env:R_LIBS_USER = $PreviousRLibrary
    $env:LANG = $PreviousLang
    $env:LC_ALL = $PreviousLcAll
    $env:LC_CTYPE = $PreviousLcType
}

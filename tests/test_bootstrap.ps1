# Test Script for bootstrap.ps1
# This script tests the core logic of the bootstrap process using a dedicated test WSL instance.

param(
    [switch]$Fresh
)

# Move to TEMP directory immediately to suppress path translation warnings for all WSL calls
Set-Location $env:TEMP

# Configuration for Test Distro
$TestDistro = "Ubuntu-24.04-test"
$TestUser = "testuser"
$TestLocation = "$env:USERPROFILE\WSL-Test\distro"
$RootfsPath = "$env:USERPROFILE\WSL-Test\ubuntu-base-24.04.tar.gz"
$RootfsUrl = "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.4-base-amd64.tar.gz"
$TestRepoUrl = "https://github.com/thomashan-leaveplus/developer-onboarding.git"

# Path to the script we are testing
$WorkspaceRoot = "\\wsl.localhost\Ubuntu-24.04\home\thomashan\git\developer-onboarding"
$BootstrapPath = Join-Path $WorkspaceRoot "bootstrap.ps1"

# 1. Setup Test Environment
if ($Fresh) {
    Write-Host "--- [FRESH] Cleaning up existing test instance ---" -ForegroundColor Yellow
    wsl --unregister $TestDistro 2>$null
}

Write-Host "--- Setting up Test Instance ($TestDistro) ---" -ForegroundColor Cyan

if (-not (Test-Path "$env:USERPROFILE\WSL-Test")) {
    New-Item -ItemType Directory -Path "$env:USERPROFILE\WSL-Test" -Force | Out-Null
}

# Download fresh rootfs if not already present
if (-not (Test-Path $RootfsPath)) {
    Write-Host "Downloading fresh Ubuntu 24.04 base rootfs..." -ForegroundColor Yellow
    $oldProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $RootfsUrl -OutFile $RootfsPath -ErrorAction Stop
    } finally {
        $ProgressPreference = $oldProgressPreference
    }
}

# Create test instance via import if it doesn't exist
$existingDistros = wsl --list --quiet | ForEach-Object { $_.Trim().Replace("`0", "") } | Where-Object { $_ -ne "" }

if ($existingDistros -notcontains $TestDistro) {
    Write-Host "Importing fresh instance as $TestDistro..."
    if (-not (Test-Path $TestLocation)) { New-Item -ItemType Directory -Path $TestLocation -Force | Out-Null }
    wsl --import $TestDistro $TestLocation $RootfsPath

    # Create a user in the new distro
    Write-Host "Creating user '$TestUser' in $TestDistro..."
    wsl --cd ~ -d $TestDistro -u root bash -c "useradd -m -s /bin/bash $TestUser && echo '$TestUser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers"

    # Set default user for the distro via registry
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    $DistroGuid = Get-ChildItem $RegPath | Get-ItemProperty | Where-Object { $_.DistributionName -eq $TestDistro } | Select-Object -ExpandProperty PSChildName
    if ($DistroGuid) {
        Set-ItemProperty -Path "$RegPath\$DistroGuid" -Name "DefaultUid" -Value 1000
    }
} else {
    Write-Host "Test instance $TestDistro already exists." -ForegroundColor Green
}

# 2. Loading and Patching bootstrap.ps1
Write-Host "`n--- Loading and Patching bootstrap.ps1 ---" -ForegroundColor Cyan

$scriptContent = Get-Content $BootstrapPath -Raw
$functionsOnly = $scriptContent -replace '(?s)# Execution.*', ''

# Patch the functions to be test-friendly
$functionsOnly = $functionsOnly -replace '(?m)^\$WslDistro = Read-Host.*', ''
$functionsOnly = $functionsOnly -replace '(?m)^if \(\[string\]::IsNullOrWhiteSpace\(\$WslDistro\)\).*', ''

# Define the mock functions and inject the distro name
$patchBlock = @"
`$WslDistro = "$TestDistro"
Function Confirm-STAgentToken { Write-Host "[MOCK] Skipping STAgent Token Confirmation" -ForegroundColor Gray }
Function Check-Admin { Write-Host "[MOCK] Skipping Admin Check" -ForegroundColor Gray }
Function Install-Git { Write-Host "[MOCK] Skipping Git Installation" -ForegroundColor Gray }
Function Install-WSL { Write-Host "[MOCK] Skipping WSL Installation" -ForegroundColor Gray }
"@

$testScriptContent = $patchBlock + "`n" + $functionsOnly

# Save to a temporary test file in local Windows TEMP
$tempTestFile = Join-Path $env:TEMP "temp_bootstrap_functions.ps1"
$testScriptContent | Set-Content $tempTestFile

# Dot-source the functions
. $tempTestFile

# 3. Execute Core Functions for Testing
try {
    Write-Host "`n--- Testing Bootstrap-Ansible ---" -ForegroundColor Cyan
    Bootstrap-Ansible

    Write-Host "`n--- Testing Configure-WSLGitCredentials ---" -ForegroundColor Cyan
    Configure-WSLGitCredentials
    
    Write-Host "--- Verifying Git Config ---"
    $configValue = wsl -d $TestDistro -u $TestUser git config --global credential.helper
    Write-Host "Configured Helper: $configValue"
    if ($configValue -notmatch '^!?".*"$') {
        Write-Error "CRITICAL: Git credential.helper is not correctly quoted! Value: $configValue. This will cause interactive hangs."
        exit 1
    }

    Write-Host "`n--- Testing Initialize-WSLRepository ---" -ForegroundColor Cyan
    if (Initialize-WSLRepository -RepoUrl $TestRepoUrl) {
        Write-Host "SUCCESS: Repository initialization passed." -ForegroundColor Green
    } else {
        Write-Host "FAILURE: Repository initialization returned false." -ForegroundColor Red
    }

    Write-Host "`n--- Testing Execute-WSLPlaybook ---" -ForegroundColor Cyan
    Execute-WSLPlaybook
}
catch {
    Write-Error "Test execution failed: $_"
}
finally {
    # Remove temp file
    Remove-Item $tempTestFile -ErrorAction SilentlyContinue
}

Write-Host "`n--- Test Complete ---" -ForegroundColor Cyan
Write-Host "Instance '$TestDistro' has been kept for manual verification." -ForegroundColor Yellow
Write-Host "To remove it, run: wsl --unregister $TestDistro" -ForegroundColor Gray

# Bootstrap Script for Developer Onboarding
# This script installs Git and WSL as the initial steps for automation.

$DefaultDistro = "Ubuntu-24.04"
$DefaultRepoUrl = "https://github.com/thomashan-leaveplus/developer-onboarding.git"

$WslDistro = Read-Host "Enter the WSL distribution name (default: $DefaultDistro)"
if ([string]::IsNullOrWhiteSpace($WslDistro)) { $WslDistro = $DefaultDistro }
Write-Host "Using distribution: $WslDistro" -ForegroundColor Cyan

# --- Path & Execution Helper Functions ---

# Returns a raw path suitable for Windows/PowerShell (Test-Path, etc.)
Function Get-WinPath {
    param([string]$Path)
    return $Path.Trim('"').Trim("'")
}

# Returns a path formatted for Linux/Bash, including literal quotes if it contains spaces.
Function Get-LinuxPath {
    param([string]$Path)
    $cleanPath = $Path.Trim('"').Trim("'")
    if ($cleanPath -match ' ') {
        return "`"$cleanPath`""
    }
    return $cleanPath
}

# Executes a script in WSL via temporary file to bypass PowerShell pipeline CRLF issues.
Function Run-WSLScript {
    param(
        [Parameter(Mandatory=$true)][string]$Script,
        [Parameter(Mandatory=$true)][string]$User
    )
    # 1. Force Unix line endings
    $unixScript = ($Script -split '\r?\n') -join "`n"
    
    # 2. Write to a temporary file in Windows TEMP
    $tempFile = Join-Path $env:TEMP "wsl_bootstrap_script.sh"
    [System.IO.File]::WriteAllText($tempFile, $unixScript)
    
    # 3. Convert Windows path to WSL path (e.g. C:\Users... -> /mnt/c/Users/...)
    $winPath = (Get-Item $tempFile).FullName
    $drive = $winPath.Substring(0,1).ToLower()
    $rest = $winPath.Substring(3).Replace('\', '/')
    $wslPath = "/mnt/$drive/$rest"
    
    # 4. Execute via WSL
    wsl --cd ~ -d $WslDistro -u $User bash "$wslPath"
    
    # 5. Cleanup
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
}

# --- Core Functions ---

Function Confirm-STAgentToken {
    Write-Host "`n[IMPORTANT] Verification Required" -ForegroundColor Yellow
    Write-Host "Has the infra team confirmed that the 'auth token for WSL STAgent installation' is enabled for you?" -ForegroundColor White
    $confirmation = Read-Host "Enter 'yes' to continue or 'no' to exit"
    
    if ($confirmation -ne "yes") {
        Write-Host "`nSetup aborted. Please ensure the infra team has enabled your auth token before running this script." -ForegroundColor Red
        exit 1
    }
    Write-Host "Confirmation received. Proceeding with setup..." -ForegroundColor Green
}

Function Check-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This script MUST be run as an Administrator. Please restart PowerShell with elevated privileges."
        exit 1
    }
}

Function Install-Git {
    Write-Host "--- Installing Git for Windows ---" -ForegroundColor Cyan
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "Git is already installed." -ForegroundColor Green
    } else {
        Write-Host "Installing Git via winget..."
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Git installed successfully." -ForegroundColor Green
        } else {
            Write-Error "Failed to install Git."
        }
    }
}

Function Install-WSL {
    Write-Host "`n--- Checking WSL ($WslDistro) ---" -ForegroundColor Cyan
    
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Host "WSL feature not found. Initiating full WSL installation..." -ForegroundColor Yellow
        wsl --install -d $WslDistro
        Write-Host "`n[REQUIRED] System reboot needed to enable WSL. Please restart and run this script again." -ForegroundColor Red
        return
    }

    $installedDistros = wsl --list --quiet | ForEach-Object { $_.Trim().Replace("`0", "") } | Where-Object { $_ -ne "" }
    if ($installedDistros -contains $WslDistro) {
        Write-Host "$WslDistro is already installed." -ForegroundColor Green
    } else {
        Write-Host "$WslDistro not found. Installing..." -ForegroundColor Yellow
        wsl --install -d $WslDistro
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "`nRestarting WSL to finalize distribution setup..." -ForegroundColor Cyan
            wsl --shutdown
            Start-Sleep -Seconds 8
            Write-Host "WSL restarted successfully." -ForegroundColor Green
        } else {
            Write-Error "Failed to install $WslDistro."
        }
    }
}

Function Bootstrap-Ansible {
    Write-Host "`n--- Bootstrapping Ansible in WSL ($WslDistro) ---" -ForegroundColor Cyan

    Write-Host "Ensuring WSL is initialized and installing Ansible..."
    
    $script = @'
for i in {1..3}; do
    echo "Attempt $i: Updating and installing packages..."
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' ansible git && \
    break || sleep 5
done
'@
    
    Run-WSLScript -Script $script -User "root"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Ansible and Git installed successfully in WSL." -ForegroundColor Green
    } else {
        Write-Error "Failed to install dependencies in WSL after multiple attempts."
        exit 1
    }
}

Function Configure-WSLGitCredentials {
    Write-Host "`n--- Configuring Git Credentials in WSL ---" -ForegroundColor Cyan

    $sysGcmWin = "C:\Program Files\Git\mingw64\bin\git-credential-manager.exe"
    $localGcmWin = "$env:LOCALAPPDATA\Programs\Git\mingw64\bin\git-credential-manager.exe"
    $rawPath = ""

    if (Test-Path (Get-WinPath $sysGcmWin)) {
        $rawPath = "/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
    }
    elseif (Test-Path (Get-WinPath $localGcmWin)) {
        $winUser = (cmd.exe /c echo %USERNAME%).Trim()
        $rawPath = "/mnt/c/Users/$winUser/AppData/Local/Programs/Git/mingw64/bin/git-credential-manager.exe"
    }

    if (-not [string]::IsNullOrWhiteSpace($rawPath)) {
        Write-Host "Setting up Git Credential Manager: $rawPath"

        $wslUserOutput = wsl --cd ~ -d $WslDistro bash -c "id -un 1000 2>/dev/null || whoami"
        $wslUser = $wslUserOutput.Trim()

        # Build a script that correctly quotes the path for Git/sh
        # Using '!' tells Git to execute the string via /bin/sh
        $script = @"
git config --global credential.helper '!"$rawPath"'
git config --global credential.useHttpPath true
"@

        Write-Host "Configuring for root..."
        Run-WSLScript -Script $script -User "root"

        if ($wslUser -ne "root") {
            Write-Host "Configuring for $wslUser..."
            Run-WSLScript -Script $script -User $wslUser
        }
    } else {
        Write-Warning "Git Credential Manager not found on Windows."
    }
}
Function Initialize-WSLRepository {
    param([string]$RepoUrl)
    Write-Host "`n--- Step 1: Cloning Repository in WSL ---" -ForegroundColor Cyan

    $targetDir = "developer-onboarding"
    $wslUserOutput = wsl --cd ~ -d $WslDistro bash -c "id -un 1000 2>/dev/null || whoami"
    $wslUser = $wslUserOutput.Trim()

    Write-Host "Cloning $RepoUrl into home directory of user: $wslUser"

    $script = @"
if [ ! -d "`$HOME/$targetDir" ]; then
    GIT_TERMINAL_PROMPT=0 git clone "$RepoUrl" "`$HOME/$targetDir"
else
    echo "Repository already exists."
fi
"@

    Run-WSLScript -Script $script -User $wslUser

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Repository initialized successfully." -ForegroundColor Green
        return $true
    } else {
        Write-Error "Failed to clone repository. Please check your URL and WSL internet connection."
        return $false
    }
}

Function Execute-WSLPlaybook {
    Write-Host "`n--- Step 2: Running Ansible Playbook ---" -ForegroundColor Cyan
    $targetDir = "developer-onboarding"
    $wslUserOutput = wsl --cd ~ -d $WslDistro bash -c "id -un 1000 2>/dev/null || whoami"
    $wslUser = $wslUserOutput.Trim()

    Write-Host "Executing playbook as user: $wslUser"
    
    # We use a script even for this simple command to maintain consistency and avoid quoting issues
    $script = "cd `$HOME/$targetDir && ansible-playbook -i localhost, ansible/wsl_setup.yml"
    Run-WSLScript -Script $script -User $wslUser

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nSetup complete! You can now access your environment by running 'wsl' and 'cd ~/$targetDir'." -ForegroundColor Green
    } else {
        Write-Warning "`nPlaybook execution failed. You may need to enter your WSL password for sudo tasks if prompted."
    }
}

# Execution
Confirm-STAgentToken
Check-Admin
Install-Git
Install-WSL
Bootstrap-Ansible
Configure-WSLGitCredentials

Write-Host "`n--- Environment Ready ---" -ForegroundColor Green
$choice = Read-Host "Would you like to clone the onboarding repo and run the setup playbook now? (y/n)"

if ($choice -eq "y") {
    $detectedUrl = ""
    try { $detectedUrl = git remote get-url origin 2>$null } catch {}
    if ([string]::IsNullOrWhiteSpace($detectedUrl)) { $detectedUrl = $DefaultRepoUrl }
    
    $repoUrl = Read-Host "Enter the onboarding Git repository URL" -DefaultValue $detectedUrl
    
    if (-not [string]::IsNullOrWhiteSpace($repoUrl)) {
        if (Initialize-WSLRepository -RepoUrl $repoUrl) {
            Execute-WSLPlaybook
        }
    } else {
        Write-Warning "No repository URL provided. Skipping final setup."
    }
} else {
    Write-Host "`nTo finish setup manually, open WSL and run:" -ForegroundColor Yellow
    Write-Host "1. git clone <repo-url> ~/developer-onboarding"
    Write-Host "2. cd ~/developer-onboarding && ansible-playbook ansible/wsl_setup.yml"
}

Write-Host "`n--- Bootstrap Phase Complete ---" -ForegroundColor Cyan

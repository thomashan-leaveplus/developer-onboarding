$WslDistro = 'Ubuntu-24.04-test'
# Bootstrap Script for Developer Onboarding
# This script installs Git and WSL as the initial steps for automation.

$DefaultDistro = "Ubuntu-24.04"
$DefaultRepoUrl = "https://github.com/thomashan-leaveplus/developer-onboarding.git"



Write-Host "Using distribution: $WslDistro" -ForegroundColor Cyan

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
    
    # 1. Check if WSL is installed at all
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Host "WSL feature not found. Initiating full WSL installation..." -ForegroundColor Yellow
        wsl --install -d $WslDistro
        Write-Host "`n[REQUIRED] System reboot needed to enable WSL. Please restart and run this script again." -ForegroundColor Red
        return
    }

    # 2. Check if the specified distribution is installed
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
    # We use -u root to ensure we can install packages without being blocked by sudo prompts.
    $aptCmd = "DEBIAN_FRONTEND=noninteractive apt-get update && " +
              "DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' ansible git"
    
    wsl --cd ~ -d $WslDistro -u root bash -c "$aptCmd"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Ansible and Git installed successfully in WSL." -ForegroundColor Green
    } else {
        Write-Error "Failed to install dependencies in WSL."
        exit 1
    }
}

Function Configure-WSLGitCredentials {
    Write-Host "`n--- Configuring Git Credentials in WSL ---" -ForegroundColor Cyan
    
    # Detect GCM path on Windows
    $sysGcm = "C:\Program Files\Git\mingw64\bin\git-credential-manager.exe"
    $localGcm = "$env:LOCALAPPDATA\Programs\Git\mingw64\bin\git-credential-manager.exe"
    $gcmPath = ""

    if (Test-Path $sysGcm) { $gcmPath = "/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe" }
    elseif (Test-Path $localGcm) { 
        $winUser = (cmd.exe /c echo %USERNAME%).Trim()
        $gcmPath = "/mnt/c/Users/$winUser/AppData/Local/Programs/Git/mingw64/bin/git-credential-manager.exe"
    }

    if (-not [string]::IsNullOrWhiteSpace($gcmPath)) {
        Write-Host "Setting up Git Credential Manager: $gcmPath"
        # Detect the non-root user
        $wslUserOutput = wsl -d $WslDistro bash -c "id -un 1000 2>/dev/null || whoami"
        $wslUser = $wslUserOutput.Trim()

        # Build command with single quotes around the double-quoted path for bash
        $gitCmd = "git config --global credential.helper '`"$gcmPath`"' && git config --global credential.useHttpPath true"
        
        # Apply to root
        wsl --cd ~ -d $WslDistro -u root bash -c "$gitCmd"
        
        # Apply to user
        if ($wslUser -ne "root") {
            wsl --cd ~ -d $WslDistro -u $wslUser bash -c "$gitCmd"
        }
    } else {
        Write-Warning "Git Credential Manager not found on Windows."
    }
}

Function Initialize-WSLRepository {
    param([string]$RepoUrl)
    Write-Host "`n--- Step 1: Cloning Repository in WSL ---" -ForegroundColor Cyan
    
    $targetDir = "developer-onboarding"
    $wslUserOutput = wsl -d $WslDistro bash -c "id -un 1000 2>/dev/null || whoami"
    $wslUser = $wslUserOutput.Trim()
    
    Write-Host "Cloning $RepoUrl into home directory of user: $wslUser"
    
    wsl --cd ~ -d $WslDistro -u $wslUser bash -c "if [ ! -d '~/`$targetDir' ]; then git clone `$RepoUrl ~/`$targetDir; else echo 'Repository already exists.'; fi"

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
    $wslUserOutput = wsl -d $WslDistro bash -c "id -un 1000 2>/dev/null || whoami"
    $wslUser = $wslUserOutput.Trim()

    Write-Host "Executing playbook as user: $wslUser"
    wsl --cd ~ -d $WslDistro -u $wslUser bash -c "cd ~/`$targetDir && ansible-playbook -i localhost, ansible/wsl_setup.yml"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nSetup complete! You can now access your environment by running 'wsl' and 'cd ~/`$targetDir'." -ForegroundColor Green
    } else {
        Write-Warning "`nPlaybook execution failed. You may need to enter your WSL password for sudo tasks if prompted."
    }
}



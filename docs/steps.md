To achieve the automation described in docs/ansible.md from a clean Windows machine with no pre-installed software, you
would follow a "Day 0" bootstrap flow. This flow bridges the gap from a raw Windows
installation to a state where Ansible can take over.

Phase 1: The "Day 0" Bootstrapper (PowerShell)
Since winget is built into modern Windows (10/11), it serves as the entry point. You would run a single PowerShell
script (as Administrator) to prepare the environment.

Initial Steps:

1. Elevate Privileges: Request Local Admin access (as per docs/new_device_setup.md).
2. Run Bootstrapper: Execute a command like the following to install the minimum required tools:

1 # Install Git to pull the automation repository
2 winget install -e --id Git.Git --silent --accept-source-agreements --accept-package-agreements
3
4 # Install WSL2 (This will trigger a reboot)
5 wsl --install -d Ubuntu-24.04

Phase 2: Post-Reboot Configuration
After the machine restarts and WSL is initialized, the script (or a follow-up) would:

1. Configure WinRM (Local): Allow Ansible (running in WSL) to communicate with the Windows host via localhost.

1 # Enable WinRM for local Ansible control
2 winrm quickconfig -quiet
3 Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true
4     Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true

2. Install Ansible in WSL:
   1 sudo apt update && sudo apt install -y ansible

Phase 3: Ansible Execution
Once the control node (WSL) is ready, you can run the playbooks defined in docs/ansible.md.

1. Clone the Onboarding Repo:
   1 git clone <repo-url> ~/developer-onboarding
   2 cd ~/developer-onboarding
2. Run Windows Playbook: (From WSL targeting the Windows host)
   1 ansible-playbook -i inventories/local.ini playbooks/windows_setup.yml
3. Run WSL Playbook: (Local execution within WSL)

1 ansible-playbook -i localhost, -c local playbooks/wsl_setup.yml

Summary of Bootstrapping Requirements
To move from manual to automated, you need to create these "glue" files:

* bootstrap.ps1: The Windows-side entry point (installs Git, WSL, and configures WinRM).
* ansible.cfg & inventory.ini: Configured to allow WSL to talk back to 127.0.0.1 (Windows host).
* windows_setup.yml: Using ansible.windows and community.windows modules.
* wsl_setup.yml: Using standard Linux modules.
1. Windows Configuration (Ansible Windows Modules)
   These tasks can be automated using Ansible's community.windows and ansible.windows collections.

    * Environment Variables:
        * Set SSL_CERT_FILE to C:\Users\Public\netskope\nscacert_combined.pem.
        * Set REQUESTS_CA_BUNDLE (mentioned in troubleshooting for Azure CLI).
    * Software Installation (via Winget or Chocolatey):
        * Git for Windows.
        * Azure Functions Core Tools: winget install -e --id Microsoft.AzureFunctionsCoreTools.
        * Azure CLI: winget install -e --id Microsoft.AzureCLI.
        * VS Code.
        * Python (via MSI/Official installer to avoid MS Store issues).
    * WSL Setup:
        * Enable WSL feature and install Ubuntu: wsl --install -d Ubuntu-24.04.
    * VS Code Extensions:
        * Bulk install extensions: Azure Functions, Azurite, Python, Apollo GraphQL, Ruff, REST Client, SCSS
          Intellisense, GitHub CoPilot, Prettier, ESLint, alexkrechik.cucumberautocomplete,
          streetsidesoftware.code-spell-checker, HashiCorp Terraform, YAML.
    * Configuration Files:
        * Manage Windows Terminal settings.json.
        * Manage VS Code settings.json (JSON patching).

2. WSL / Linux Configuration (Ansible Core/Linux Modules)
   These tasks would be run within the WSL instance once it is provisioned.

* Package Management (APT):
    * Install sshd.
    * Install Azure CLI (following the Microsoft repository setup).
* Tool Installation Scripts:
    * Docker: Install Docker Engine on Ubuntu.
    * NVM & Node.js: Install Node Version Manager and Node.js v20.
    * UV: Install the uv python package manager.
    * Netskope Agent: Install the STAgent.
    * MOB: curl -sL https://github.com/remotemobprogramming/mob/releases/latest/download/install.sh | sudo sh.
* Git Configuration:
    * Set user.name and user.email.
    * Configure Git Credential Manager for Windows SSO integration.
* WSL System Tweaks:
    * Apply the DNS resolution workaround (/etc/wsl.conf or /etc/resolv.conf changes).

3. Manual Steps (Non-Ansibliseable)
   These items require human intervention, external approvals, or interactive authentication and should be excluded from
   the playbook (or handled via manual prompts/documentation):

* Requesting Local Admin Access via Helpdesk.
* Requesting ADO, Azure, Miro, and Datadog access.
* "Ask infra team to enable auth token" (Process step).
* Manual Windows reboots.
* Initial WSL username/password creation.
* Browser extension installations (Edge/Chrome).
* Signing into VS Code for Settings Sync/Copilot.

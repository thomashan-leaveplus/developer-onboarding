12falsedefaultlisttrue


Overview

This aims to streamline the setup process for a developer laptop. This expands
on the already established documentation on the backend guide but ordered for an
easier step-through process. The end goal is that a new developer can follow
this guide step by step and be ready with minimal assistance.




Access Requests


Local Admin Access

A LOT OF THE SETUP PROCESS WILL REQUIRE ELEVATED PRIVILEGES.

Many of the systems which need to be set up will require local admin access on
your device. You can request for temporary access within the LeavePlus IT
Helpdesk [https://helpdesk.leaveplus.com.au/app/itdesk/ui/ssp/pages/home].

CREATE A NEW TICKET (REQUEST A SERVICE)

UNDER “USER ADMINISTRATION”, SELECT “PRIVILEGED ACCESS REQUEST”



FILL OUT A DESCRIPTION CONTAINING THE REASON FOR ACCESS (E.G. REQUIRED FOR
DEVELOPMENT SETUP)


Azure DevOps (ADO)

Azure DevOps is used to host our repositories here:
https://dev.azure.com/leaveplus [https://dev.azure.com/leaveplus]

If you do not have access to ADO, speak to to request access.


GitHub Co-Pilot

Ask for GitHub Co-Pilot for VSCode integration.


Azure

Raise a ticket with LeavePlus Helpdesk
[https://helpdesk.leaveplus.com.au/app/itdesk/ui/ssp/pages/home] to provide you
access to Azure. Reference any other person that you will perform a similar role
as for them as reference on what type of permissions you would require (e.g., I
need Azure access with a similar role as 'X').


Miro

Miro is used for diagramming and brainstorming: https://miro.com/app/dashboard/
[https://miro.com/app/dashboard/]

If Miro is not already set up for you, speak to to request access.




Datadog

Datadog is a monitoring and analytics tool for information technology (IT)
services- https://us3.datadoghq.com/dashboard/lists
[https://us3.datadoghq.com/dashboard/lists]

Try logging into the above links, raise a request with LeavePlus Helpdesk
[https://helpdesk.leaveplus.com.au/app/itdesk/ui/ssp/pages/home] if there any
issues in accessing it by requesting to get added to the correct AD groups.


Windows certificates

Set us User Environment Variable in Windows

SSL_CERT_FILE=C:\Users\Public\netskope\nscacert_combined.pem

This should let you use uv for python development on Windows, if you ever need
to.

Note There are multiple versions of that PEM file on various laptops, some of
them are known to work, some are known to not work. Please reach out if
uv/python/pip gives you certificate issuer troubles.

at some point it would be good to get to the bottom of these differences.


Setting up WSL


WSL distro install

If this is your first time installing WSL on your PC you will need to start the
PS or CMD as Admin for the below command.

Otherwise (subsequent distro [re]install) the command can be run from normal PS
or CMD prompt.

nonewide760

Note other distros “might work”, but were not tested with these instructions.

Reboot the laptop if asked to do so, after the reboot the wsl setup terminal
should automatically restart. Otherwise start wsl yourself by typing wsl in the
CMD / PS prompt.

WSL will ask for a username then password. These don’t need to match Windows,
and they don’t change periodically. You can use your firstnamelastname for
username, or anything else, as long as it’s unique among devs. I used voytek for
mine, as unique enough. For password, choose something you will not forget, it’s
your Ubuntu admin password you might sometimes need in the future to install /
upgrade tools in WSL.

After that you should land with a bash terminal prompt.


Re-install the WSL distro

It’s possible to blow away the whole distro and start from scratch. BEWARE it
will remove all your files inside the distro filesystem, so make sure you pushed
your git repos beforehand and preserved any other files that you don’t want
lost, e.g. .env files.

You can preserve everything in Windows, including installed packages and configs
by running the following in PowerShell:

wsl --export Ubuntu-24.04 C:\Users\<your name>\wsl_backup.tar

Exit all WSL terminals, then from windows “Installed apps” uninstall the distro,
then from PS or CMD run:

wide760

After that you can restart from WSL distro install
[https://coinvestwiki.atlassian.net/wiki/spaces/DPD/pages/2705719331/New+Device+Quick+Setup#WSL-distro-install]
above


Set up Windows Terminal to use WSL Ubuntu (optional)

Windows Terminal by default uses PowerShell. Open up the settings, and under
Startup, set the default profile to the new WSL distro just set.


Install dev tools


Disable Windows Docker Desktop integration with WSL

If you have Docker Desktop installed in windows, it can interfere with wsl
docker. Make sure the WSL 2 integration is disabled for your distro, in the
Windows Docker Desktop, under “Settings/Resources/WSL Integration”. There are
two separate settings, one for default distro, and one per-distro, disable both.


Install

 1. Install Git on Windows.

 2. Ask infra team to “enable auth token for WSL STAgent installation”, and wait
    for their confirmation, before proceeding.

 3. Copy / paste below script into wsl terminal and ENTER. (This installs
    docker, sshd, nvm, nodejs 20, uv, netskope agent and configures git to use
    your name, email and Windows SSO integration for ADO.)

Note it uses Node Version Manager (NVM) [https://github.com/nvm-sh/nvm]for
installation and switching of different node versions. The script below installs
version 20. You can tweak it before running the script (copy into notepad,
change the version, before pasting into WSL).

```bash
WSL_INIT=~/wsl-init.sh
cat << WSL_EOF > $WSL_INIT
COMPLETE_MSG="WSL developer setup READY"

echo '*****************************************************************'
echo WSL developer setup starting.
echo Expect to see a \"\$COMPLETE_MSG\" message at the end.
echo If you don\'t - something went wrong.
echo '*****************************************************************'

echo Setting timezone ...
sudo ln -sf /usr/share/zoneinfo/Australia/Melbourne /etc/localtime || exit 1
echo Done

echo Adding docker ppa
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || exit 1
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo "\$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list
echo Done

echo Adding git ppa
sudo add-apt-repository --yes ppa:git-core/ppa || exit 1
echo Done

echo Updating ubuntu
sudo apt-get update || exit 1
sudo apt-get upgrade -y || exit 1
echo Done

echo Installing misc tools
sudo apt-get install -y ca-certificates openssh-server unzip libnss3 || exit 1
echo Done

echo Installing docker
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || exit 1
sudo usermod -aG docker \$USER
echo Done

echo Installing astral uv ...
curl -LsSf https://astral.sh/uv/0.6.7/install.sh | sh
echo Done

echo Installing node.js
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
. ~/.nvm/nvm.sh
nvm install 20
echo Done

echo Configuring git ...
git config --global credential.useHttpPath true
WIN_USERNAME=`whoami.exe | tr -d '\r' | cut '-d\' -f2`
WIN_USERNAME_CAP=`echo $WIN_USERNAME | sed -E 's/(^|\.)([a-z])/\1\u\2/g'` 
WIN_NAME=`echo $WIN_USERNAME_CAP | sed 's/\./ /'`
WIN_EMAIL=`whoami.exe /UPN`
git config --global user.name "$WIN_NAME"
git config --global user.email "$WIN_EMAIL"
if [ -x /mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe ]; then
    git config --global credential.helper '"/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"'
else
    WIN_GIT_LOCAL_CRED_MANAGER="/mnt/c/Users/$WIN_USERNAME/AppData/Local/Programs/Git/mingw64/bin/git-credential-manager.exe"
    git config --global credential.helper "\"$WIN_GIT_LOCAL_CRED_MANAGER\""
fi
echo Done

echo Setting up Netskope Agent
curl https://download-coinvest.goskope.com/dlr/linux/get -o ./STAgent.run
chmod +x ./STAgent.run
sudo ./STAgent.run -H coinvest.goskope.com -o oz8f0az7H855wSOLamvn -m $WIN_EMAIL -a a57530dffa850a646ef81e5bb7f6c59d -c
rm ./STAgent.run
echo Done

. ~/.bashrc

echo === Timezone ===
ls -l /etc/localtime

echo === uv ===
uv --version || exit 1

echo === Node.js ===
node -v || exit 1

echo === npm ===
npm -v || exit 1

echo === git config ===
git config --list

echo === docker ===
docker --version || exit 1

echo \$COMPLETE_MSG
echo WSL needs full restart, with 10 seconds rest
WSL_EOF

# Use of interactive shell needed for . ~/.bashrc to actually work
bash -i $WSL_INIT
rm $WSL_INIT
```

Expect it take a couple of minutes. At the end you should see a bunch of version
numbers of the installed tools, followed by a message WSL developer setup READY.
If you don’t see this message something didn’t work as expected. Feel free to
improve, or ask around for help.

References for the script above:

docker - Ubuntu | Docker Docs [https://docs.docker.com/engine/install/ubuntu/]

uv - Standalone Installer
[https://docs.astral.sh/uv/getting-started/installation/]

Node.js - Download Node.js® [https://nodejs.org/en/download]

nvm - Node Version Manager [https://github.com/nvm-sh/nvm]

git - Git Credential Manager setup
[https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-git#git-credential-manager-setup]


Restart WSL

Exit all WSL terminals, VSCode, and the CMD / PS terminal where you started it,
wait 15 secs, then restart wsl.

Note On restart, it should take a good few seconds to start now. If it’s
immediate - exit and let it rest longer.


Test the docker installation

Inside WSL run

bashwide760

You should see a few lines of output informing you that your install was
successful.

If the above fails due to IPv6 connection failure to docker hub, run the
following workaround to change the DNS resolution behaviour inside WSL:

bashwide760

then exit wsl, then in CMD run wsl --shutdown, then restart WSL, then retry the
docker hello-world above.


Cloning from ADO in WSL

After above setup you can clone ADO repos with https URL instead of ssh, and it
will integrate with Windows SSO. No need for ssh keys in that setup.

I believe the better practice is to clone your git repos inside wsl and into the
linux filesystem, (e.g. under ~/projects) instead of the windows filesystem
under /mnt/c/Users/... . This should help us avoid CRLF issues and work faster
inside wsl.

bashwide760


Venv

uv will manage the python installation AND venv.

For projects fully switched to uv (dependencies listed in pyproject.toml) run
(first time run uv lock) uv sync where the pyproject.toml file is.

For projects still using requirements.txt use uv venv followed by uv pip install
-r requirements.txt -r requirements_dev.txt.



You can usually find the pyproject.toml or requirements.txt file under one of
the src directories. Be sure to check the readme for each repository.


Installing Azure Tools


Windows

Download the following tools for Azure (using Windows CMD line)

AZURE FUNCTION CORE TOOL
[https://github.com/Azure/azure-functions-core-tools?tab=readme-ov-file#v4-3]

wide760

AZURE CLI
[https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?tabs=winget]

wide760


WSL

Install the Azure CLI on Linux | Microsoft Learn
[https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?view=azure-cli-latest&pivots=apt]

wide760


Installing VS Code

Install VS Code from the Visual Studio Website: https://code.visualstudio.com/
[https://code.visualstudio.com/]

Once installed, add the following extensions:

 * Azure Functions

 * Azurite

 * Python

 * Apollo GraphQL

 * Ruff

 * REST Client

 * SCSS Intellisense

 * GitHub CoPilot

 * Prettier - Code Formatter

 * ESLint

 * alexkrechik.cucumberautocomplete recommended by

 * streetsidesoftware.code-spell-checker (Spell checker recommended by )

 * HashiCorp Terraform

 * YAML

 * (Optional) IntelliJ IDEA Keybindings (If you are more comfortable/familiar
   with IntelliJ suite).

Update user-preference (JSON) settings.json with the following:

wide760

Note: some recommendations above have been commented out as they might interfere
with per-project workspace settings committed with project sources in git.

In WSL, you should be able to now open a code by navigating to a repository and
running code .

Select venv python environment, while in wsl code, use 'F1/Python:Select
Interpreter' and find the right .venv/bin/python .




Installing Snyk (WSL + VS Code) (optional)

See the following guides on how to configure Snyk within WSL and VS Code.

Snyk CLI setup on VSCode in WSL - Cyber Security - Confluence

Configure Snyk on IDE-VSCode with WSL - Cyber Security - Confluence


Installing MOB (optional)

INSTALL VIA WSL [https://github.com/remotemobprogramming/mob]

bashwide760

VERIFY INSTALLATION

bashwide760


Edge/Chrome Extensions

See below for a list of useful Edge/Chrome extensions to assist with
development. Feel free to extend this list with any additional extensions you
find useful:

 * React Developer Tools
   [https://microsoftedge.microsoft.com/addons/detail/react-developer-tools/gpphkfbcpidddadnkolkpfckpihlkkil]

 * LastPass
   [https://chromewebstore.google.com/detail/lastpass-free-password-ma/hdokiejnpimakedhajhdlcegeplioahd?hl=en]


Optional: Install apps from Windows Company Portal

You are able to install software applications from Windows Company Portal.
Search ‘Company Portal’ in Windows Task bar.


Troubleshooting

Issue: Not able to connect from WSL to dev or sandbox Azure resources

RootCause: Netskope agent not running.

Fix: run nsclient show-status



Issue: The error ‘Could not find a suitable TLS CA certificate bundle’ occurs
when running AZ CLI command in Command Prompt, Windows PowerShell or WSL
terminal, e.g.

wide760

Root cause:

This MS troubleshoot page
[https://learn.microsoft.com/en-gb/cli/azure/use-azure-cli-successfully-troubleshooting?view=azure-cli-latest#work-behind-a-proxy]
explains the root cause, but its solution is incomplete.

Solution:

 * Go to http://portal.azure.com [http://portal.azure.com] using any web
   browser. If works, then check if the connection is secure.

 * Export the root full chain cert (crt or pem), NOTE: must be ‘full chain’

 * Append the exported cert to the cacert.pem mentioned in the MS troubleshoot
   page. Open the certs in any text editor, and copy paste the exported cert on
   the top of the cacert.pem.

 * Create or updateREQUESTS_CA_BUNDLEwith the full path of the appended cert in
   Environment Variables. NOTE: you need to be Admin user of your laptop.

 * Reopen the terminal (not need as Admin) and test it



Issue: The error ‘ModuleNotFoundError: No module named 'xxxxxx'’ when running
Azure Function Python code on local laptop even the module is added in
requirements.txt and is installed in your virtual environment.

Potential root cause:

The Python is installed by MS Store which sets FunctionsCoreTools to use the
default Python interpreter, not the one in your virtual environment. It cannot
be changed even you update the VS Code to use your interpreter.

Solution:

 * uninstall the python

 * reinstall it using the MSI provided by python.org

 * configure the VS Code to use the new interpreter

 * restart everything.

 * it should work.


Next Steps

Review the following development guides for Backend and Frontend:

Frontend development tools and setup

Backend development tools and setup



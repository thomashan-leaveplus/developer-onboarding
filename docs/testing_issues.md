# Testing & Exploratory Issues Log

This file documents the technical challenges, edge cases, and learnings encountered during the development of the developer onboarding automation. **Read this file before making ANY changes to scripts or tests.**

---

## 1. WSL Path Translation Warnings
- **Issue:** When running `wsl -d <distro>` from a path inside another WSL instance (e.g., `\\wsl.localhost\Ubuntu-24.04\...`), WSL attempts to translate and mount that path in the target distro. If the target distro is fresh, the path doesn't exist, causing the error: `wsl: Failed to translate '\\wsl.localhost\...'`.
- **Solution:** 
    1. Use `Set-Location $env:TEMP` in PowerShell before calling WSL to ensure the host path is a standard Windows directory.
    2. Always use the `--cd ~` flag in `wsl` commands to force execution in the Linux user's home directory.

## 2. PowerShell Variable Expansion in WSL Commands
- **Issue:** Using backticks before variables inside double-quoted strings (e.g., `` ` $targetDir ``) intended for WSL/Bash often prevents PowerShell from expanding the variable before sending it to the shell. Conversely, some Bash variables (like `~/`) need to be protected.
- **Solution:** Use standard PowerShell expansion for host-side variables and ensure the resulting string is correctly quoted for the Bash `-c` argument.

## 3. Interactive Prompts during `apt-get`
- **Issue:** Packages like `tzdata` or `postfix` trigger interactive configuration dialogues during installation, hanging automated scripts.
- **Solution:** Use `DEBIAN_FRONTEND=noninteractive` and Dpkg force-options:
  `DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" <package>`

## 4. WSL `wsl --list --quiet` Output Encoding
- **Issue:** The output of `wsl -l -q` often contains null characters (`\0`) or is UTF-16 encoded, which causes string comparisons like `-match` or `-contains` to fail in PowerShell even if the text looks identical.
- **Solution:** Sanitize the output:
  `$existing = wsl --list --quiet | ForEach-Object { $_.Trim().Replace("`0", "") } | Where-Object { $_ -ne "" }`

## 5. User Permissions & Root Cloning
- **Issue:** Importing a fresh rootfs via `wsl --import` defaults to the `root` user. Cloning repositories or running playbooks as `root` creates files with incorrect ownership, breaking future non-root development.
- **Solution:** 
    1. The test script must explicitly create a non-root user (`testuser`).
    2. Set the `DefaultUid` in the Windows Registry (`HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss`) to `1000`.
    3. Always use `wsl -u <user>` for logic-related steps.

## 6. Git Credential Manager (GCM) Pathing
- **Issue:** Git for Windows is usually installed in `C:\Program Files\Git`, which contains a space. Bash handles this poorly if not double-quoted correctly within the single-quoted `credential.helper` config.
- **Solution:** Use nested quoting: `git config --global credential.helper '"/mnt/c/Program Files/..."'`.

## 7. Test Isolation
- **Issue:** Testing against the primary `Ubuntu-24.04` distro is invalid because it is already configured.
- **Solution:** Use a dedicated `Ubuntu-24.04-test` instance created from a minimal `ubuntu-base` rootfs tarball. Ensure this instance is **always** unregistered (`wsl --unregister`) at both the start and end of the test.

## 8. PowerShell Script Execution Policy
- **Issue:** Running scripts from WSL network paths triggers "not digitally signed" errors.
- **Solution:** Always run with `-ExecutionPolicy Bypass`.

## 9. PowerShell Double-Quote Escaping
- **Issue:** Using `\"` inside a double-quoted string in PowerShell (e.g., `" '\"$path\"' "`) causes a `ParserError` or `UnexpectedToken` because `\` is not the escape character in PowerShell (backtick `` ` `` is).
- **Solution:** Use backtick-double-quote (`` `" ``) or double-double-quotes (`""`) to escape double quotes within a double-quoted string: `" '`"$path`"' "`.

## 10. Tilde (~) Expansion in Bash Commands
- **Issue:** When passing a command to `bash -c`, the tilde (`~`) is not expanded if it is enclosed in quotes (e.g., `'~/dir'`). This causes commands like `cd '~/dir'` or `[ ! -d '~/dir' ]` to fail.
- **Solution:** Use `$HOME` instead of `~` inside quotes, or ensure `~` is outside of quotes: `"$HOME/dir"`.

## 11. PowerShell vs Bash Variable Expansion
- **Issue:** In a `wsl ... bash -c "..."` command, using backticks before a variable (e.g., `` `$var ``) tells PowerShell *not* to expand it, passing the literal `$var` to Bash. If the variable is defined in PowerShell but not in Bash, it will be empty in the Bash execution.
- **Solution:** Remove backticks from PowerShell variables that need to be expanded before being sent to WSL. Use backticks ONLY for variables that Bash itself should expand (like `` `$HOME ``).

## 12. PowerShell $HOME vs Bash $HOME
- **Issue:** PowerShell has a built-in `$HOME` variable pointing to `C:\Users\<User>`. If used inside a double-quoted string in PowerShell (e.g., `"cd $HOME"`), it is expanded to the Windows path before being sent to WSL, causing Bash to fail or target the Windows filesystem (e.g., `Cloning into 'C:Users...'`).
- **Solution:** Always escape the dollar sign (`` `$HOME ``) in PowerShell double-quoted strings when the variable is intended for Bash expansion.

## 13. Nested Quoting for GCM in Bash
- **Issue:** Passing a path with spaces (like `Program Files`) through PowerShell to `bash -c` requires extreme care. Single quotes in PowerShell are literals, but double quotes are for expansion.
- **Solution:** Use escaped double quotes for the inner path and ensure the whole string is correctly handled by Bash: `git config --global credential.helper \"$gcmPath\"`.

## 14. PowerShell Double-Double Quotes ("")
- **Issue:** In some PowerShell contexts (like `bash -c`), using `""` to represent a literal `"` can lead to malformed strings when passed across the process boundary to `wsl.exe`.
- **Solution:** Use single quotes for the PowerShell string where possible, or use backtick-escaped quotes (`` `" ``) for maximum reliability when expansion is also needed.

## 15. Complex Bash Commands via wsl.exe
- **Issue:** Complex Bash logic (if/then/else) passed via `wsl ... bash -c "..."` often breaks due to how PowerShell and WSL share the command line, leading to "unexpected EOF" or syntax errors.
- **Solution:** Simplify the Bash command or use a multi-line string with very clear quoting boundaries. Prefer `$HOME` over `~` and ensure it's not expanded by PowerShell.

## 16. Persistent GCM Quoting Failure
- **Issue:** Attempts to use nested quotes like `'""$gcmPath""'` or `'\"$gcmPath\"'` resulted in Bash errors like `unexpected EOF while looking for matching ''`. This indicates the command line is being split at the space in `Program Files` despite the quotes.
- **Solution (Attempted):** 
    1. `""$gcmPath""` -> Malformed bash command.
    2. `\"$gcmPath\"` -> ParserError in PowerShell.
    3. `` `"$gcmPath`" `` -> Resulted in `Files/Git/...: line 1: unexpected EOF`.
- **Root Cause:** The interaction between PowerShell's string handling and `wsl.exe`'s argument parsing is swallowing quotes or misinterpreting the backslash.
- **Final Solution:** Use a single-quoted string for the outer command in PowerShell if no variables are needed, or use a very specific escaping sequence: `'git config --global credential.helper \"'` + $gcmPath + '\"'`.

## 17. Git Invocation of Helper with Spaces
- **Issue:** Even if `git config` succeeds, Git invokes the helper via `/bin/sh -c`. If the path in the config contains spaces but no literal quotes (e.g., `helper = /mnt/c/Program Files/...`), the shell splits the path, leading to: `/mnt/c/Program: not found`.
- **Solution:** The value stored in Git config *must* contain literal double quotes. To achieve this via PowerShell/WSL:
  `$gitCmd = "git config --global credential.helper '\"\"$gcmPath\"\"'"`
  This ensures that when Bash runs the command, it sees `git config ... '"/path/with spaces"'`, which Git then stores as a quoted string.

## 18. PowerShell String Concatenation Parser Errors
- **Issue:** Attempting to mix single quotes, double quotes, and backtick escapes in a complex concatenation (e.g., `'...' + "'\"`"$var`\"' " + '...'`) often triggers `UnexpectedToken` parser errors.
- **Solution:** Keep PowerShell strings simple. Use double quotes with backtick-escaped internal quotes (`` `" ``), or use a single-quoted string if no expansion is needed.

## 19. Bash Syntax Errors in wsl.exe bash -c
- **Issue:** Passing complex logic (if/then/else) via `bash -c` through `wsl.exe` often results in "unexpected end of file" or "syntax error" because quotes are stripped or misinterpreted by the multiple layers of shell (PowerShell -> wsl.exe -> bash).
- **Solution:** 
    1. Prefer running commands directly with `wsl -d distro -u user command args` instead of wrapping everything in `bash -c`.
    2. For complex logic, use a Here-String in PowerShell to build the bash script clearly.

## 20. Windows Process Argument Splitting
- **Issue:** When running `wsl ... bash -c $script` in PowerShell, if `$script` contains spaces (e.g. `echo "hello world"`), PowerShell passes it as multiple arguments to `wsl.exe`. Bash then only sees the first word, leading to `syntax error: unexpected end of file`.
- **Solution:** Always wrap the script variable in double-quotes in PowerShell so it is passed as a single string to the Windows process: `wsl ... bash -c "$script"`.

## 21. Dual Path Representation (Windows vs. Linux)
- **Issue:** A single variable containing a path with spaces (like `Program Files`) cannot reliably serve both PowerShell (for `Test-Path`) and Linux (for `git config`). Quoting that works for one often breaks the other during the transition through `wsl.exe`.
- **Solution:** Maintain two distinct variables:
    1. `$winPath`: A standard Windows path (e.g., `C:\Program Files\...`) used for PowerShell logic.
    2. `$linuxPath`: A string specifically formatted for Linux/Bash consumption, including literal internal quotes (e.g., `'\\"/mnt/c/Program Files/...\\"'`).
    This ensures that when Bash receives the string, it already has the quotes it needs to treat the path as a single argument.

## 22. Functional Path Transformation
- **Issue:** Manual string manipulation for different shell contexts is error-prone and leads to technical debt.
- **Solution:** Keep the "Source of Truth" string as a raw, unquoted path. Use dedicated functions (`Get-WinPath` and `Get-LinuxPath`) to wrap the string in the correct context-specific quoting/escaping.
    - `Get-WinPath $path` -> Returns standard Windows representation.
    - `Get-LinuxPath $path` -> Returns Bash-safe string with escaped quotes if necessary.

## 23. Piping Scripts via STDIN to WSL
- **Issue:** Passing complex logic as a command-line argument to `wsl.exe bash -c` is subject to Windows-side quote stripping and argument splitting at spaces.
- **Solution:** Pipe the script body into the `bash` process within WSL. This bypasses the command-line length limits and all character escaping issues on the Windows host side.
  `$script | wsl -d distro -u user bash`
  This is the most robust method for executing multi-line logic or commands with complex quoting.

## 24. Intermittent apt-get Package Discovery Failure
- **Issue:** In extremely fresh WSL distros, `apt-get install` can sometimes fail with `Unable to locate package` even immediately after an `apt-get update`. This is likely due to race conditions or incomplete mirror syncing.
- **Solution:** Combine update and install into a single retry loop or ensure multiple update attempts are made if an installation fails.

## 25. Idempotency Mandate
- **Requirement:** Every function must be safely repeatable.
- **Implementation:**
    - `Initialize-WSLRepository`: Check for directory existence before cloning.
    - `Bootstrap-Ansible`: Packages are already idempotent via `apt-get`, but logic should handle already-installed states gracefully.
    - `Configure-WSLGitCredentials`: Overwriting `git config` is inherently idempotent.

## 26. PowerShell Variable Reference with Drive (Colon Issue)
- **Issue:** Using `$var:` inside a double-quoted string in PowerShell (e.g., `"Attempt $i:"`) causes a `ParserError` because PowerShell interprets `$i:` as a variable on a drive named `i`.
- **Solution:** 
    1. Use a single-quoted string where possible.
    2. Use `${i}:` to explicitly delimit the variable name.
    3. Use a single-quoted Here-String (`@' ... '@`) for Bash scripts to ensure all characters (including `$` and `:`) are passed literally.

## 27. Windows CRLF in Piped WSL Scripts
- **Issue:** Piped scripts from PowerShell to WSL (e.g., `$script | wsl bash`) include Windows carriage returns (`\r\n`). Bash interprets `\r` as a literal character, leading to syntax errors like `syntax error near unexpected token '$'do\r''`.
- **Solution:** Force Unix line endings (`\n`) before piping.
  `$script = ($scriptContent -split '\r?\n') -join "`n"`
  `$script | wsl bash`

## 28. Unexpected EOF in Piped Scripts
- **Issue:** Even with LF line endings, piping a large string to `wsl bash` can sometimes lead to `syntax error: unexpected end of file` if the pipe is closed prematurely or if PowerShell's default encoding (UTF-16) is used.
- **Solution:** Use an array of strings (one per line) and pipe the array to WSL. PowerShell's pipe operator handles arrays by sending each element followed by a newline, which is more robust for Bash.
  `$scriptArray = $script -split '\r?\n'`
  `$scriptArray | wsl ... bash`

## 29. PowerShell Pipeline Enforces CRLF
- **Issue:** Even if you join strings with `\n` in PowerShell, when you pipe (`|`) to a native Windows process like `wsl.exe`, PowerShell often re-injects carriage returns (`\r\n`) based on the system's `$OutputEncoding` or default pipeline behavior. This leads to `syntax error near unexpected token '$'do\r''`.
- **Solution:** Avoid the pipeline for multi-line scripts. Write the script to a temporary Windows file, then use WSL to read that file:
  `[System.IO.File]::WriteAllText("$env:TEMP\script.sh", $unixScript)`
  `wsl ... bash -c "source /mnt/c/Users/.../AppData/Local/Temp/script.sh"`
  Or use `wsl bash < file.sh` (if the shell supports it).

## 30. Git Credential Helper Path Splitting at Runtime
- **Issue:** During 	est_bootstrap.ps1, the git clone command failed with `git: 'credential-/mnt/c/Program' is not a git command`. This happened even though the config appeared to have quotes: `Configured Helper: ""/mnt/c/Program Files/...""`. Git's internal execution of the helper via /bin/sh -c is still splitting the path.
- **Root Cause:** The quoting applied in Configure-WSLGitCredentials is being double-interpreted or stripped in a way that leaves the raw path with spaces exposed to the shell during Git operations.
- **Reproduction:** Run 	est_bootstrap.ps1 against a fresh distro where GCM is located in C:\Program Files\Git.

## 31. Syntax Error from Imprecise Regex Replacement
- **Issue:** Manual ootstrap.ps1 modification using regex replacement failed, leaving behind a partial code block from line 184 to 208. This caused a ParserError: Unexpected token '}'.
- **Root Cause:** The regex (?s)Function Configure-WSLGitCredentials.*?\} was too greedy or mismatched due to nested braces, failing to cleanly replace the entire old function.
- **Solution:** Use line-based filtering or a full-file rewrite with a robust PowerShell Here-String to ensure structural integrity.

## 32. Git Prepending 'credential-' to Absolute Paths
- **Issue:** During 	est_bootstrap.ps1, Git failed with git: 'credential-/mnt/c/Program Files/...' is not a git command.
- **Root Cause:** The credential.helper value was stored with literal double quotes in the Git config (e.g., helper = "/mnt/c/..."). Git only treats a helper as an absolute path if it starts with a /. Since the first character was ", Git treated it as a name and prepended credential-.
- **Solution:** Configure the helper without literal internal quotes in the git config command; git config will handle the spaces and config-level quoting automatically.
- **Interactivity Prevention:** Use GIT_TERMINAL_PROMPT=0 for all Git commands in scripts to ensure they fail immediately instead of hanging on auth prompts.

## 33. Git Config Quoting vs. Git Execution
- **Issue:** Removing literal quotes from git config fixed the credential- prefix issue but caused the path to be stored unquoted. Git then split the path at the space during execution, leading to failure.
- **Solution:** The path *must* be stored in the config with literal double quotes. The correct way to achieve this via git config is to escape the internal quotes: git config --global credential.helper '\"/path with spaces/...\"'.

## 34. Run-WSLScript File Cleanup Race Condition
- **Issue:** Occasionally, Remove-Item fails in Run-WSLScript with PathNotFound, even though the file was just created and used. This indicates a potential race condition or duplicate call.
- **Solution:** Add -ErrorAction SilentlyContinue to the cleanup step in Run-WSLScript to prevent non-critical errors from interrupting the bootstrap process.

## 35. Git Credential Helper as Shell Command (!)
- **Issue:** Even with literal quotes, Git prepends credential- to absolute paths containing spaces if they aren't perfectly formatted for its internal parser.
- **Solution:** Use the ! prefix to force Git to execute the helper via a shell. The config value must be: !"/mnt/c/Path With Spaces/...".
- **Implementation:** git config --global credential.helper '!\"\"'.

## 36. Test Script Verification Over-Strictness
- **Issue:** 	est_bootstrap.ps1 fails if the credential helper value starts with !, even though this is the correct configuration for absolute paths with spaces.
- **Solution:** Update the regex in 	est_bootstrap.ps1 to allow the optional ! prefix: ^!?".*"$.

## 37. Literal Backslashes in Git Config
- **Issue:** Using \!\" in the git config script caused literal backslashes to be stored in the config: !\"/path/...\". Git then failed to find the helper.
- **Solution:** Use single quotes around the entire helper value in the git config command to pass literal double quotes without needing backslash escapes: git config ... helper '!"/path/..."'.

## 38. Test Failures due to Uncommitted Local Changes
- **Issue:** During 	est_bootstrap.ps1, the Execute-WSLPlaybook step failed because the cloned repository in the test instance did not contain the nsible directory or the latest script changes (as they were only present in the local workspace).
- **Solution:** For local testing, mock the repository initialization in the test script to copy the local workspace files into the test instance instead of performing a git clone from the remote origin.

## 39. Missing 'sudo' in Minimal WSL Images
- **Issue:** During 	est_bootstrap.ps1 using ubuntu-base, the Ansible playbook failed because sudo was not installed: `/bin/sh: 1: sudo: not found`.
- **Solution:** Add sudo to the list of packages installed during the Bootstrap-Ansible phase in ootstrap.ps1.

## 40. SSL Certificate Verification Failure during PPA Addition
- **Issue:** The Ansible task Add Git PPA failed with `[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: self-signed certificate in certificate chain`.
- **Root Cause:** The WSL instance lacks corporate root CA certificates required to verify intercepted SSL connections during PPA metadata fetching.
- **Solution:** Add a task to install/update corporate root certificates before adding PPAs, or use alidate_certs: no if supported (though not recommended for security). Alternatively, pre-install certificates during the Bootstrap-Ansible phase.

## 41. Docker Repository Failure on Ubuntu 24.04 (noble)
- **Issue:** The Ansible task Add Docker repository succeeds, but pt update fails with `repository ... doesn't support architecture 'x86_64'` for 
oble.
- **Root Cause:** The Docker repository for Ubuntu 24.04 (
oble) is incomplete or misconfigured on the upstream server.
- **Solution:** Temporarily use the jammy (22.04) repository for Docker on 
oble systems until the upstream repository is fixed.

## 42. Robocopy Flattening Behavior with Wildcards
- **Issue:** When using `robocopy <src> <dst> /E` where `<src>` is a WSL UNC path (e.g., `\\wsl.localhost\...`), robocopy may flatten the directory structure if wildcards or certain path combinations are used.
- **Root Cause:** Inconsistent handling of WSL network shares by Windows copy tools.
- **Solution:** Use a "Middleman Strategy":
    1. Robocopy from WSL to a local Windows Temp folder.
    2. Robocopy from the local Windows Temp folder to the target WSL instance.
    This ensures that structure is preserved by avoiding direct WSL-to-WSL UNC transfers.

## 43. Conda SSL Verification Failure
- **Issue:** Conda package installation (e.g., `conda install uv`) fails with `[SSL: CERTIFICATE_VERIFY_FAILED]` in environments with intercepted SSL (corporate proxies/Netskope).
- **Solution:** Disable SSL verification specifically for the Conda command using `conda config --set ssl_verify false` before running installations. While less secure, it is necessary for bootstrapping in these environments until root certificates are fully injected into the Conda environment.

## 44. Avoid Git PPA (git-core/ppa)
- **Issue:** Previously, the git-core/ppa was added to install the latest Git version (e.g., 2.53+). 
- **Decision:** Do NOT add git-core/ppa back into the onboarding automation. The standard Ubuntu LTS repositories (e.g., Git 2.43 on Ubuntu 24.04) are sufficient for the current developer needs, and avoiding third-party PPAs reduces maintenance overhead and potential compatibility issues with corporate proxies.

## 45. PowerShell Script Execution Policy for Onboarding Setup
- **Issue:** Running `.\bootstrap.ps1` fails on fresh Windows devices with `Restricted` or `RemoteSigned` script execution policies, throwing a script execution blocked error.
- **Root Cause:** Script execution policy cannot be bypassed from within the script itself because PowerShell blocks the script before any code executes.
- **Solution:** Updated the onboarding instructions in `README.md` to instruct the developer to run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` within the process scope before executing `.\bootstrap.ps1`. This ensures the policy is only bypassed for the active terminal session and does not persist globally.


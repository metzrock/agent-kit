# Download this script, read it, then run it from an elevated PowerShell window.
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Resume,
    [switch]$SimulateMissingWsl,
    [switch]$SimulateMissingUbuntu,
    [switch]$SimulateUninitializedUbuntu
)
$ErrorActionPreference = 'Stop'
# Publish this tag before distributing the Windows bootstrap.
$KitRef = 'v0.1.2'
$BootstrapUrl = "https://raw.githubusercontent.com/metzrock/agent-kit/$KitRef/install.sh"

function Show-Action([string]$Text) {
    Write-Output "Action: $Text"
}
function Show-WslCommand([string[]]$WslArguments) {
    $QuotedArguments = @($WslArguments | ForEach-Object { "'" + $_.Replace("'", "''") + "'" })
    Show-Action ("& wsl.exe " + ($QuotedArguments -join ' '))
}
function Test-UbuntuListed([int]$ExitCode, [string[]]$Distros) {
    # WSL can return nonzero when it has no installed distributions.
    if ($ExitCode -ne 0) { return $false }
    return @($Distros | Where-Object { ($_ -replace "`0", '').Trim() -eq 'Ubuntu' }).Count -gt 0
}
function Invoke-Wsl([string[]]$WslArguments) {
    Show-WslCommand -WslArguments $WslArguments
    if (-not $DryRun) {
        & wsl.exe @WslArguments
        if ($LASTEXITCODE -ne 0 -and -not ($WslArguments[0] -eq '--install' -and $LASTEXITCODE -eq 3010)) {
            throw "WSL command failed (exit $LASTEXITCODE). Re-run this script after resolving it."
        }
    }
}

if ($Resume) { Write-Output 'Resuming agent-kit setup after restart.' }
Show-Action 'Check Windows 10 build 19041 or newer and administrator rights'
if (-not $DryRun) {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        [Environment]::OSVersion.Version.Build -lt 19041) {
        throw 'Windows 10 build 19041 or newer is required.'
    }
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Open PowerShell as administrator, then run this script again.'
    }
}

Show-Action 'Check whether wsl.exe is available'
$WslReady = -not $SimulateMissingWsl
$UbuntuReady = -not ($SimulateMissingWsl -or $SimulateMissingUbuntu)
if (-not $DryRun) {
    $WslReady = $false
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        Show-WslCommand -WslArguments @('--status')
        & wsl.exe --status
        $WslReady = ($LASTEXITCODE -eq 0)
    }
    $UbuntuReady = $false
    if ($WslReady) {
        Show-WslCommand -WslArguments @('--list', '--quiet')
        $Distros = @(& wsl.exe --list --quiet)
        $UbuntuReady = Test-UbuntuListed -ExitCode $LASTEXITCODE -Distros $Distros
    }
} elseif ($WslReady) {
    Show-WslCommand -WslArguments @('--status')
    Show-WslCommand -WslArguments @('--list', '--quiet')
}

$RunOnceKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
$SavedScript = if ($DryRun) { '<LocalAppData>\agent-kit\install.ps1' } else {
    Join-Path $env:LOCALAPPDATA 'agent-kit\install.ps1'
}
if (-not $WslReady -or -not $UbuntuReady) {
    Show-Action "Save bootstrap to $SavedScript"
    Show-Action 'Register agent-kit RunOnce entry to resume after reboot'
    if (-not $DryRun) {
        if (-not $PSCommandPath) { throw 'Save install.ps1 to a file before running it.' }
        New-Item -ItemType Directory -Path (Split-Path $SavedScript) -Force | Out-Null
        if ([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath($SavedScript)) {
            Copy-Item -LiteralPath $PSCommandPath -Destination $SavedScript -Force
        }
        # RunOnce launches an elevated process because resuming still checks admin rights.
        $QuotedScript = $SavedScript.Replace("'", "''")
        $ResumeCommand = "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$QuotedScript`" -Resume'"
        $EncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ResumeCommand))
        New-Item -Path $RunOnceKey -Force | Out-Null
        New-ItemProperty -Path $RunOnceKey -Name 'agent-kit' -PropertyType String -Force -Value (
            "powershell.exe -NoProfile -EncodedCommand $EncodedCommand"
        ) | Out-Null
    }
    Invoke-Wsl -WslArguments @('--install', '-d', 'Ubuntu')
    Write-Output 'Restart Windows if requested. The bootstrap resumes at your next sign-in; accept the administrator prompt.'
    Write-Output 'On first launch, Ubuntu asks you to choose a Linux username and password. Password typing is hidden.'
    Write-Output 'If no reboot is needed, run this script again to continue.'
    return
}

# Starting a command probes readiness without opening a shell on every re-run.
Show-WslCommand -WslArguments @('-d', 'Ubuntu', '--', 'true')
$UbuntuInitialized = -not $SimulateUninitializedUbuntu
if (-not $DryRun) {
    & wsl.exe -d Ubuntu -- true
    $UbuntuInitialized = ($LASTEXITCODE -eq 0)
}
if (-not $UbuntuInitialized) {
    Write-Output 'On first launch, Ubuntu asks for a Linux username and password. These are for Linux; password typing is hidden.'
    Write-Output 'When the Ubuntu shell is ready, type exit to continue the kit setup.'
    Invoke-Wsl -WslArguments @('-d', 'Ubuntu')
}
$LinuxCommand = @'
set -eu
installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
curl -fsSL '__URL__' -o "$installer"
AGENT_KIT_REF='__REF__' bash "$installer"
'@
$LinuxCommand = $LinuxCommand.Replace('__URL__', $BootstrapUrl).Replace('__REF__', $KitRef).Replace("`r", '')
# Windows PowerShell 5.1 can mangle quotes/newlines in native arguments.
# Only this one-line, quote-free command crosses the wsl.exe boundary.
$EncodedLinuxCommand = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($LinuxCommand))
$WslBootstrapCommand = "set -o pipefail; printf %s $EncodedLinuxCommand | base64 -d | bash"
Invoke-Wsl -WslArguments @('-d', 'Ubuntu', '--', 'bash', '-lc', $WslBootstrapCommand)
Show-Action 'Remove the agent-kit RunOnce entry after successful setup'
if (-not $DryRun) {
    Remove-ItemProperty -Path $RunOnceKey -Name 'agent-kit' -ErrorAction SilentlyContinue
}

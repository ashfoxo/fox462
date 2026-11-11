# fox-grey setup: points this PC's Syncthing at fox-red, through fox-green's
# private relay, and shares Prism Launcher's instances with it.
#
# Run AFTER Syncthing is installed (Syncthing Windows Setup, "start at logon")
# and running. In PowerShell:
#   powershell -ExecutionPolicy Bypass -File setup.ps1
#
# It asks for two secrets and stores them only in Syncthing's own config:
#   - the relay token   (laptop: see hosts/fox-green/secrets/syncthing-relay-token)
#   - the minecraft-instances folder password (Bitwarden / sops)
# Nothing secret is written to disk outside that config.

$ErrorActionPreference = 'Stop'

$FoxRedId  = 'KPXV26X-WCTDXXJ-O5YC6UW-QXPPLWN-4SSMULV-RHN3B4Z-BA5XE6Q-C4DAHQ6'
$RelayBase = 'relay://198.44.125.25:22067/?id=B4EVN6V-WCRMK2M-6BEMSFX-TJIAGEB-U2X3ZFZ-ULDLR4J-JM2X3NR-33Q5AQQ'
$Instances = Join-Path $env:APPDATA 'PrismLauncher\instances'
$Api       = 'http://127.0.0.1:8384/rest'

function Read-Secret($prompt) {
    $s = Read-Host -AsSecureString $prompt
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b).Trim() }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

# --- Syncthing's API key, from its config ---
$config = @(
    (Join-Path $env:LOCALAPPDATA 'Syncthing\config.xml'),
    (Join-Path $env:APPDATA 'Syncthing\config.xml')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $config) { throw "Syncthing's config.xml not found. Is Syncthing installed and has it run once?" }
$key = ([xml](Get-Content $config)).configuration.gui.apikey
$h = @{ 'X-API-Key' = $key }
function St($method, $path, $body) {
    $p = @{ Method = $method; Uri = "$Api$path"; Headers = $h }
    if ($null -ne $body) { $p.Body = ($body | ConvertTo-Json -Depth 10); $p.ContentType = 'application/json' }
    Invoke-RestMethod @p
}
try { $myId = (St Get '/system/status').myID }
catch { throw "Can't reach Syncthing at http://127.0.0.1:8384. Start it and run this again." }

# --- Secrets ---
$token = Read-Secret 'Relay token'
if ($token -notmatch '^[0-9a-f]{64}$') { throw 'That does not look like the relay token (64 hex characters).' }
$folderPw = Read-Secret 'minecraft-instances folder password'
if (-not $folderPw) { throw 'Empty folder password.' }

# --- Move existing instances aside, so nothing here overwrites the laptop's ---
if (Get-Process -Name prismlauncher -ErrorAction SilentlyContinue) {
    Read-Host 'Close Prism Launcher, then press Enter'
}
if ((Test-Path $Instances) -and (Get-ChildItem $Instances -Force | Select-Object -First 1)) {
    $old = "$Instances-old-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Rename-Item $Instances $old
    Write-Host "Your existing instances are in $old"
}
New-Item -ItemType Directory -Force $Instances | Out-Null

# --- Connections: only the private relay, no discovery, no public relays ---
St Patch '/config/options' @{
    listenAddresses        = @("$RelayBase&token=$token")
    globalAnnounceEnabled  = $false
    localAnnounceEnabled   = $false
    natEnabled             = $false
    relaysEnabled          = $true
    urAccepted             = -1
    crashReportingEnabled  = $false
} | Out-Null

# --- fox-red: it dials us through the relay; we only accept ---
St Put "/config/devices/$FoxRedId" @{
    deviceID  = $FoxRedId
    name      = 'fox-red'
    addresses = @('dynamic')
} | Out-Null

# --- The folder, encrypted toward fox-red (it never holds plaintext) ---
try { St Delete '/config/folders/default' $null | Out-Null } catch { }   # Syncthing's sample folder
St Put '/config/folders/minecraft-instances' @{
    id         = 'minecraft-instances'
    label      = 'Minecraft instances'
    path       = $Instances
    type       = 'sendreceive'
    devices    = @(@{ deviceID = $FoxRedId; encryptionPassword = $folderPw })
    versioning = @{ type = 'simple'; params = @{ keep = '5' } }
} | Out-Null

if ((St Get '/config/restart-required').requiresRestart) {
    St Post '/system/restart' $null | Out-Null
    Write-Host 'Restarted Syncthing to apply the settings.'
}

Write-Host ''
Write-Host 'Done. This PC''s device ID (send it to put in lib/syncthing.nix):'
Write-Host ''
Write-Host "    $myId" -ForegroundColor Green
Write-Host ''
Write-Host 'It will sync once fox-red is deployed with that ID. Wait for the folder'
Write-Host 'to show "Up to Date" at http://127.0.0.1:8384 before opening Prism, then'
Write-Host 'copy any world you want back from the instances-old folder.'
$myId | Set-Clipboard
Write-Host '(The ID is also on your clipboard.)'
Read-Host 'Press Enter to close'

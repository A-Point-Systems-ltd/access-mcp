# AccessMCP bootstrap — launches accessmcp.exe from the canonical versioned
# install, downloading and verifying it first when needed.
#
# THE CONTRACT (plugin-platforms-development-plan §2.2–§2.3):
#   * stdout belongs to the MCP protocol. This script NEVER writes to stdout;
#     everything it has to say goes to stderr.
#   * The canonical install root is versioned. A running exe is never replaced
#     in place; a new version is staged side by side and an atomic pointer
#     (current.json) flips to it. Existing processes keep their version.
#   * The local release-manifest.json (next to this script) is the PINNED
#     MINIMUM known-good version. The remote manifest check is best-effort
#     with a short timeout; offline never blocks a valid local install.
#   * Binaries are downloaded ONLY from the version-pinned URL inside the
#     manifest that was read — never through a `latest` redirect (TOCTOU).
#   * SHA256 is verified before a byte lands in versions\. After the EV
#     certificate ships, Authenticode is verified as well (see TODO below).
#   * This is public code: no secrets, no licensing logic, no internal
#     endpoints. Download-and-verify, nothing else.
#
# Requires Windows PowerShell 5.1+ (present on every supported Windows).

[CmdletBinding()]
param(
    # Everything after the script path is handed to accessmcp.exe untouched,
    # so plugin configs can pass --read-only, a database path, etc.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $ExeArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # progress bars write to stdout streams in odd hosts

function Write-Err([string] $Message) {
    [Console]::Error.WriteLine("accessmcp bootstrap: $Message")
}

function Fail([string] $Message, [int] $Code = 1) {
    Write-Err $Message
    exit $Code
}

# ---------------------------------------------------------------- platform --
# Supported: native Windows only. WSL, Remote-SSH containers, macOS and Linux
# are not supported (plan §6) — fail loudly with a pointer, never silently.
if ($env:OS -ne 'Windows_NT') {
    Fail ("AccessMCP requires native Windows with Microsoft Access installed. " +
          "This environment is not Windows. See https://access-mcp.ai/docs/supported-platforms")
}
if ($env:WSL_DISTRO_NAME) {
    Fail ("AccessMCP cannot run inside WSL — it needs native Windows COM access " +
          "to Microsoft Access. Run your MCP client on Windows itself. " +
          "See https://access-mcp.ai/docs/supported-platforms")
}

# ------------------------------------------------------------------- paths --
$Root         = Join-Path $env:LOCALAPPDATA 'Programs\AccessMCP'
$VersionsDir  = Join-Path $Root 'versions'
$CurrentJson  = Join-Path $Root 'current.json'
$CheckStamp   = Join-Path $Root 'update-check.json'
$LocalManifestPath = Join-Path $PSScriptRoot 'release-manifest.json'

$RemoteManifestUrl = 'https://github.com/A-Point-Systems-ltd/access-mcp/releases/latest/download/release-manifest.json'
$RemoteTimeoutSec  = 3
$CheckIntervalHours = 24

New-Item -ItemType Directory -Force -Path $VersionsDir | Out-Null

# ------------------------------------------------------------------ helpers --
function Read-Json([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { $null }
}

function Write-JsonAtomic([object] $Object, [string] $Path) {
    $tmp = "$Path.tmp.$PID"
    $Object | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-ExePathFor([string] $Version) {
    Join-Path (Join-Path $VersionsDir $Version) 'accessmcp.exe'
}

function Test-InstalledVersion([string] $Version) {
    ($Version) -and (Test-Path -LiteralPath (Get-ExePathFor $Version))
}

function Compare-Version([string] $A, [string] $B) {
    # -1 / 0 / 1 like CompareTo; tolerates missing parts.
    ([version] $A).CompareTo([version] $B)
}

function Assert-ManifestShape($Manifest, [string] $Origin) {
    foreach ($field in 'version', 'exe_sha256', 'exe_url') {
        if (-not ($Manifest.PSObject.Properties.Name -contains $field) -or -not $Manifest.$field) {
            throw "release manifest from $Origin is missing '$field'"
        }
    }
    if ($Manifest.exe_url -notmatch '^https://github\.com/A-Point-Systems-ltd/access-mcp/releases/download/v[^/]+/accessmcp\.exe$') {
        throw "release manifest from $Origin has an exe_url outside the pinned release pattern: $($Manifest.exe_url)"
    }
    if ($Manifest.exe_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw "release manifest from $Origin has a malformed exe_sha256 (placeholder not stamped?)"
    }
}

function Install-Version($Manifest) {
    # Stage into a temp file, verify, then move atomically into versions\<v>\.
    $version = [string] $Manifest.version
    $destDir = Join-Path $VersionsDir $version
    $destExe = Get-ExePathFor $version
    if (Test-Path -LiteralPath $destExe) { return }   # someone else won the race

    Write-Err "downloading accessmcp.exe $version ..."
    $staging = Join-Path $Root ("staging-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    try {
        $tmpExe = Join-Path $staging 'accessmcp.exe'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Manifest.exe_url -OutFile $tmpExe -UseBasicParsing

        $actual = (Get-FileHash -LiteralPath $tmpExe -Algorithm SHA256).Hash
        if ($actual -ne $Manifest.exe_sha256.ToUpperInvariant()) {
            throw "SHA256 mismatch for $($Manifest.exe_url): expected $($Manifest.exe_sha256), got $actual"
        }

        # TODO(EV certificate — plan decision ה-5): once releases are signed,
        # verify here and refuse anything unsigned:
        #   $sig = Get-AuthenticodeSignature -LiteralPath $tmpExe
        #   if ($sig.Status -ne 'Valid') { throw "Authenticode: $($sig.Status)" }

        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Move-Item -LiteralPath $tmpExe -Destination $destExe -Force
        Write-Err "installed accessmcp.exe $version"
    }
    finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Set-Current([string] $Version) {
    Write-JsonAtomic ([pscustomobject]@{
        version    = $Version
        path       = (Get-ExePathFor $Version)
        updated_at = (Get-Date).ToUniversalTime().ToString('o')
    }) $CurrentJson
}

function Get-Prop($Object, [string] $Name) {
    # StrictMode-safe property access on ConvertFrom-Json output.
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

function Get-RemoteManifest {
    # Best-effort, throttled. Never the reason a working install fails.
    $stamp = Read-Json $CheckStamp
    if ($stamp -and (Get-Prop $stamp 'checked_at')) {
        try {
            $age = (Get-Date).ToUniversalTime() - [datetime]::Parse((Get-Prop $stamp 'checked_at')).ToUniversalTime()
            if ($age.TotalHours -lt $CheckIntervalHours) { return $null }
        } catch { }
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $resp = Invoke-WebRequest -Uri $RemoteManifestUrl -UseBasicParsing -TimeoutSec $RemoteTimeoutSec
        $manifest = $resp.Content | ConvertFrom-Json
        Assert-ManifestShape $manifest 'remote'
        Write-JsonAtomic ([pscustomobject]@{ checked_at = (Get-Date).ToUniversalTime().ToString('o') }) $CheckStamp
        return $manifest
    }
    catch {
        Write-Err "update check skipped ($($_.Exception.Message)) — continuing with the local install"
        Write-JsonAtomic ([pscustomobject]@{ checked_at = (Get-Date).ToUniversalTime().ToString('o') }) $CheckStamp
        return $null
    }
}

# --------------------------------------------------------------- main logic --
$localManifest = Read-Json $LocalManifestPath
if (-not $localManifest) { Fail "missing or unreadable $LocalManifestPath — the plugin package is broken; reinstall the plugin" }
try { Assert-ManifestShape $localManifest 'the plugin' }
catch { Fail $_.Exception.Message }

$pinned = [string] $localManifest.version

# One bootstrap at a time per user — parallel clients must not race the install.
$mutex = New-Object System.Threading.Mutex($false, 'Local\AccessMCP.Bootstrap')
$null = $mutex.WaitOne()
try {
    $current = Read-Json $CurrentJson

    # 1. Make sure at least the pinned version is installed.
    $haveCurrent = ($current -and (Test-InstalledVersion (Get-Prop $current 'version')))
    $satisfiesPin = $haveCurrent -and ((Compare-Version $current.version $pinned) -ge 0)

    if (-not $satisfiesPin) {
        if (Test-InstalledVersion $pinned) {
            Set-Current $pinned
        }
        else {
            try { Install-Version $localManifest; Set-Current $pinned }
            catch {
                if ($haveCurrent) {
                    # An older-but-valid install beats no install; warn and run it.
                    Write-Err "could not install $pinned ($($_.Exception.Message)); running installed $($current.version)"
                }
                else {
                    Fail ("could not install accessmcp.exe $pinned ($($_.Exception.Message)). " +
                          "Check your network, or download it manually from " +
                          "https://github.com/A-Point-Systems-ltd/access-mcp/releases and run install-accessmcp.ps1")
                }
            }
        }
        $current = Read-Json $CurrentJson
    }

    # 2. Best-effort: is there something newer than what we run?
    $remote = Get-RemoteManifest
    if ($remote -and ((Compare-Version $remote.version $current.version) -gt 0)) {
        try { Install-Version $remote; Set-Current $remote.version; $current = Read-Json $CurrentJson }
        catch { Write-Err "staging $($remote.version) failed ($($_.Exception.Message)); staying on $($current.version)" }
    }

    # 3. Opportunistic cleanup: keep current + one previous version for rollback.
    try {
        $keep = @($current.version)
        $installed = @(Get-ChildItem -LiteralPath $VersionsDir -Directory |
            Where-Object { Test-InstalledVersion $_.Name } |
            Sort-Object { [version] $_.Name } -Descending)
        if ($installed.Count -gt 1) { $keep += $installed[1].Name }
        foreach ($dir in $installed) {
            if ($keep -notcontains $dir.Name) {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { }   # cleanup must never block a launch
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}

# ------------------------------------------------------------------- launch --
$exe = [string] $current.path
if (-not (Test-Path -LiteralPath $exe)) { Fail "current.json points at a missing exe ($exe); delete $CurrentJson and retry" }

& $exe @ExeArgs
exit $LASTEXITCODE

# AccessMCP bootstrap — launches the accessmcp.exe version this plugin is
# pinned to, from the shared version cache, downloading and verifying it
# first when needed.
#
# THE CONTRACT (plugin-platforms-development-plan §2.2–§2.3, review round 3):
#   * stdout belongs to the MCP protocol. This script NEVER writes to stdout;
#     everything it has to say goes to stderr.
#   * THREE INSTALL FAMILIES, deliberately separate:
#       plugins  → shared VERSION CACHE (%LOCALAPPDATA%\Programs\AccessMCP\
#                  versions\<v>\accessmcp.exe), each plugin runs EXACTLY the
#                  version its release-manifest.json pins. Two plugins pinned
#                  to the same version share one copy; plugins pinned to
#                  different versions are isolated — one client updating
#                  never changes what another client runs.
#       manual / install-accessmcp.ps1 → a standalone exe wherever the user
#                  put it. The bootstrap neither uses nor touches it.
#       Claude Desktop .mcpb → its own bundled exe.
#   * The pin is EXACT, not a minimum: if the pinned version cannot be run
#     or obtained, the bootstrap FAILS with instructions — it does not
#     silently run something older or newer. (Escape hatch for emergencies:
#     ACCESSMCP_PIN_FALLBACK=allow runs the newest cached version instead,
#     loudly.) Offline is never blocked once the pinned version is cached.
#   * Binaries are downloaded ONLY from the version-pinned URL inside the
#     manifest, whose embedded tag MUST equal the manifest version — never
#     through a `latest` redirect (TOCTOU).
#   * The pin is version + BYTES: SHA256 is verified before a byte lands in
#     versions\ AND on every cache hit before launch — a directory named
#     right but holding the wrong exe is quarantined and re-fetched, never
#     run. When the manifest says the release is signed (signing.status ==
#     'signed'), a Valid Authenticode signature is REQUIRED, from a cert
#     carrying the Code Signing EKU and OUR Durable Identity EKU (Azure
#     Artifact Signing rotates certs, so the pin is the durable EKU — not a
#     thumbprint), with Subject as defense-in-depth.
#   * No cache cleanup here: another plugin may pin any version. The
#     installer owns cache maintenance.
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

# -------------------------------------------------------------- constants --
$RemoteManifestUrl = 'https://github.com/A-Point-Systems-ltd/access-mcp/releases/latest/download/release-manifest.json'
$RemoteTimeoutSec  = 3
$DownloadTimeoutSec = 300
$CheckIntervalHours = 24

# ------------------------------------------------------------------ helpers --
function Get-Prop($Object, [string] $Name) {
    # StrictMode-safe property access on ConvertFrom-Json output.
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

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
        if (-not (Get-Prop $Manifest $field)) {
            throw "release manifest from $Origin is missing '$field'"
        }
    }
    $m = [regex]::Match([string] $Manifest.exe_url,
        '^https://github\.com/A-Point-Systems-ltd/access-mcp/releases/download/v([^/]+)/accessmcp\.exe$')
    if (-not $m.Success) {
        throw "release manifest from $Origin has an exe_url outside the pinned release pattern: $($Manifest.exe_url)"
    }
    # The URL's own tag must be the manifest's version — a manifest claiming
    # 2.5.0 must not hand out 2.4.0 bytes (review round 3, §8).
    if ($m.Groups[1].Value -ne [string] $Manifest.version) {
        throw "release manifest from ${Origin}: exe_url tag v$($m.Groups[1].Value) != version $($Manifest.version)"
    }
    if ($Manifest.exe_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw "release manifest from $Origin has a malformed exe_sha256 (placeholder not stamped?)"
    }
}

function Assert-ExeTrusted([string] $Path, $Manifest) {
    # The pin is version + BYTES, not "a directory with the right name
    # exists" (review round 4, §2). Applied to every candidate exe — a fresh
    # download and a cache hit alike.
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne ([string] $Manifest.exe_sha256).ToUpperInvariant()) {
        throw "SHA256 mismatch for ${Path}: expected $($Manifest.exe_sha256), got $actual"
    }
    # Once the manifest declares a signed release, an unsigned or tampered
    # exe is a hard failure — and 'Valid' alone is not enough. Azure
    # Artifact Signing rotates short-lived certificates, so a thumbprint
    # pin is useless; the stable publisher identity is the
    # subscriber-specific Durable Identity EKU Microsoft embeds in every
    # cert it issues to us. Enforcement chain:
    #   Valid Authenticode (trusted chain)
    #   → Code Signing EKU present
    #   → OUR Durable Identity EKU present (when the manifest pins one)
    #   → Subject match as defense-in-depth (when the manifest gives one)
    $signing = Get-Prop $Manifest 'signing'
    $status = if ($signing) { [string] (Get-Prop $signing 'status') } else { '' }
    if ($status -and $status -ne 'unsigned') {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path
        if ($sig.Status -ne 'Valid') {
            throw "Authenticode verification failed ($($sig.Status)) for a release the manifest says is signed"
        }
        $ekus = @(
            $sig.SignerCertificate.Extensions |
                Where-Object { $_ -is [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] } |
                ForEach-Object { $_.EnhancedKeyUsages } | ForEach-Object { $_.Value }
        )
        if ($ekus -notcontains '1.3.6.1.5.5.7.3.3') {
            throw "signer certificate lacks the Code Signing EKU"
        }
        $wantOid = [string] (Get-Prop $signing 'durable_identity_oid')
        if ($wantOid -and ($ekus -notcontains $wantOid)) {
            throw "signer certificate lacks our Durable Identity EKU ($wantOid) — signed, but not by A-Point"
        }
        $wantSubject = [string] (Get-Prop $signing 'subject')
        if ($wantSubject -and ($sig.SignerCertificate.Subject -notlike "*$wantSubject*")) {
            throw "Authenticode signer subject '$($sig.SignerCertificate.Subject)' does not match pinned '$wantSubject'"
        }
    }
}

function Test-CachedVersion($Manifest) {
    # $true only when the pinned version is cached AND its bytes verify
    # against the manifest (hash + signature pinning).
    $exe = Get-ExePathFor ([string] $Manifest.version)
    if (-not (Test-Path -LiteralPath $exe)) { return $false }
    try { Assert-ExeTrusted $exe $Manifest; $true }
    catch {
        Write-Err "cached $($Manifest.version) failed verification: $($_.Exception.Message)"
        $false
    }
}

function Invoke-QuarantineVersion([string] $Version) {
    # Move a corrupt cache entry aside (never run it, never silently delete
    # evidence). Fails if the exe is currently running — replacing bytes
    # under a live process is exactly what we refuse to do.
    $dir = Join-Path $VersionsDir $Version
    if (-not (Test-Path -LiteralPath $dir)) { return }
    $dest = Join-Path $Root ("quarantine-$Version-" + [guid]::NewGuid().ToString('N'))
    Move-Item -LiteralPath $dir -Destination $dest
    Write-Err "quarantined corrupt cache entry to $dest"
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
        Invoke-WebRequest -Uri $Manifest.exe_url -OutFile $tmpExe -UseBasicParsing -TimeoutSec $DownloadTimeoutSec

        Assert-ExeTrusted $tmpExe $Manifest

        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Move-Item -LiteralPath $tmpExe -Destination $destExe -Force
        Write-Err "installed accessmcp.exe $version"
    }
    finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-UpdateNotice([string] $PinnedVersion) {
    # Best-effort, throttled awareness only. It NEVER changes what runs —
    # updates arrive by updating the plugin (which moves the pin). Never the
    # reason a launch fails.
    try {
        $stamp = Read-Json $CheckStamp
        if ($stamp -and (Get-Prop $stamp 'checked_at')) {
            $age = (Get-Date).ToUniversalTime() - [datetime]::Parse((Get-Prop $stamp 'checked_at')).ToUniversalTime()
            if ($age.TotalHours -lt $CheckIntervalHours) { return }
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $resp = Invoke-WebRequest -Uri $RemoteManifestUrl -UseBasicParsing -TimeoutSec $RemoteTimeoutSec
        $remote = $resp.Content | ConvertFrom-Json
        Assert-ManifestShape $remote 'remote'
        Write-JsonAtomic ([pscustomobject]@{ checked_at = (Get-Date).ToUniversalTime().ToString('o') }) $CheckStamp
        if ((Compare-Version ([string] $remote.version) $PinnedVersion) -gt 0) {
            Write-Err ("a newer AccessMCP ($($remote.version)) is published; this plugin pins $PinnedVersion. " +
                       "Update the plugin to move up — https://access-mcp.ai/whats-new")
        }
    }
    catch {
        try { Write-JsonAtomic ([pscustomobject]@{ checked_at = (Get-Date).ToUniversalTime().ToString('o') }) $CheckStamp } catch { }
    }
}

# --------------------------------------------------------------- main logic --
# Test hook: dot-source the functions without running the launcher (works on
# any OS — everything below this line is Windows-only).
if ($env:ACCESSMCP_BOOTSTRAP_TEST -eq '1') { return }

# ---------------------------------------------------------------- platform --
# Supported: native Windows only. WSL, Remote-SSH containers, macOS and Linux
# are not supported (plan §6) — fail loudly with a pointer, never silently.
if ($env:OS -ne 'Windows_NT') {
    Fail ("AccessMCP requires native Windows with Microsoft Access installed. " +
          "This environment is not Windows. See https://access-mcp.ai/docs#supported-platforms")
}
if ($env:WSL_DISTRO_NAME) {
    Fail ("AccessMCP cannot run inside WSL — it needs native Windows COM access " +
          "to Microsoft Access. Run your MCP client on Windows itself. " +
          "See https://access-mcp.ai/docs#supported-platforms")
}

# ------------------------------------------------------------------- paths --
$Root         = Join-Path $env:LOCALAPPDATA 'Programs\AccessMCP'
$VersionsDir  = Join-Path $Root 'versions'
$CheckStamp   = Join-Path $Root 'update-check.json'
$LocalManifestPath = Join-Path $PSScriptRoot 'release-manifest.json'

New-Item -ItemType Directory -Force -Path $VersionsDir | Out-Null

$localManifest = Read-Json $LocalManifestPath
if (-not $localManifest) { Fail "missing or unreadable $LocalManifestPath — the plugin package is broken; reinstall the plugin" }
try { Assert-ManifestShape $localManifest 'the plugin' }
catch { Fail $_.Exception.Message }

$pinned = [string] $localManifest.version

# One bootstrap at a time per user — parallel clients must not race the
# install. An abandoned mutex (a previous bootstrap crashed while holding
# it) still counts as acquired: every on-disk mutation here is atomic, so
# the state is consistent regardless of where the holder died.
$mutex = New-Object System.Threading.Mutex($false, 'Local\AccessMCP.Bootstrap')
try { $null = $mutex.WaitOne() }
catch [System.Threading.AbandonedMutexException] { }
try {
    # Cache hit counts only if the BYTES verify — a directory named 2.3.1
    # holding the wrong exe (corruption, restore, replaced asset) is treated
    # as not installed: quarantined and re-fetched, never run.
    $cachedOk = Test-CachedVersion $localManifest
    if (-not $cachedOk -and (Test-InstalledVersion $pinned)) {
        try { Invoke-QuarantineVersion $pinned }
        catch {
            Fail ("cached accessmcp.exe $pinned failed verification but cannot be replaced " +
                  "($($_.Exception.Message)) — close clients using it and retry, or reinstall the plugin")
        }
    }
    if (-not $cachedOk) {
        try { Install-Version $localManifest }
        catch {
            $cached = @(Get-ChildItem -LiteralPath $VersionsDir -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-InstalledVersion $_.Name } |
                Sort-Object { [version] $_.Name } -Descending)
            if ($env:ACCESSMCP_PIN_FALLBACK -eq 'allow' -and $cached.Count -gt 0) {
                $pinned = $cached[0].Name
                Write-Err ("PIN FALLBACK: could not install the pinned version ($($_.Exception.Message)); " +
                           "running cached $pinned because ACCESSMCP_PIN_FALLBACK=allow")
            }
            else {
                $hint = if ($cached.Count -gt 0) {
                    "Cached versions exist (" + (($cached | ForEach-Object { $_.Name }) -join ', ') + ") but this plugin pins $pinned exactly; " +
                    "set ACCESSMCP_PIN_FALLBACK=allow only as a temporary escape hatch."
                } else { "" }
                Fail ("could not install the pinned accessmcp.exe $pinned ($($_.Exception.Message)). " + $hint +
                      " Check your network, update/reinstall the plugin, or download the exe manually from " +
                      "https://github.com/A-Point-Systems-ltd/access-mcp/releases and point your MCP config at it directly.")
            }
        }
    }
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}

Write-UpdateNotice $pinned

# ------------------------------------------------------------------- launch --
$exe = Get-ExePathFor $pinned
if (-not (Test-Path -LiteralPath $exe)) { Fail "pinned exe vanished after install ($exe) — reinstall the plugin" }

& $exe @ExeArgs
exit $LASTEXITCODE

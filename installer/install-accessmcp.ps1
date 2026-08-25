<#
.SYNOPSIS
    Installs accessmcp.exe for the current user and, optionally, registers it
    with Claude Code, Claude Desktop, Cursor and/or the OpenAI Codex CLI.

.DESCRIPTION
    Per-user, no administrator rights, Windows only (master plan v4 section 0).

    THE CONTRACT THIS SCRIPT RESPECTS
    ---------------------------------
    accessmcp.exe is the product. This script is a convenience.

    Downloading the exe, dropping it anywhere, and pointing an mcp.json at it by
    hand keeps working exactly as it does today: same file name, same arguments,
    same behaviour. Nothing this script writes -- not the PATH entry, not a
    client config, not the install directory -- is required for that exe to run.
    Uninstalling this script's work does not disable an exe someone installed by
    hand somewhere else.

    So: the exe goes to %LOCALAPPDATA%\Programs\AccessMCP (never Program Files,
    which is the thing that forces elevation), every client config points at that
    absolute path, and every config is MERGED, never overwritten -- a user with
    five other MCP servers keeps all five, and the original file is backed up
    next to itself before a single byte changes.

.PARAMETER ExePath
    Path to the accessmcp.exe you want installed. Mutually exclusive with
    -FromRelease.

.PARAMETER FromRelease
    Download the exe instead of copying a local one. Requires -ReleaseUrl: this
    script deliberately hardcodes no download URL, because a wrong URL baked
    into an installer is worse than no URL at all. Releases are published at
    https://github.com/A-Point-Systems-ltd/access-mcp/releases -- take the
    asset URL from there (or from your own internal mirror) and pass it in.

.PARAMETER ReleaseUrl
    Direct URL of the accessmcp.exe asset to download. Used only with
    -FromRelease. Must be https.

.PARAMETER InstallDir
    Where the exe goes. Default %LOCALAPPDATA%\Programs\AccessMCP. Overriding
    this to a machine-wide location will need administrator rights, which is
    exactly what the default avoids.

.PARAMETER Configure
    Which clients to register the server with:
    claude-code, claude-desktop, cursor, codex, all, none. Default none on
    install (copy the exe and stop), all on -Uninstall.

.PARAMETER ServerName
    The MCP server key written into the client configs. Default 'accessmcp'.

.PARAMETER DatabasePath
    The Access database (.accdb/.mdb/.adp) this server works on, passed as the
    first argument in every config written. Required whenever -Configure
    registers a client (v2.4.0: the server runs only against the file pinned
    here -- the safety guard against an agent opening the wrong database).
    May be omitted when no client configs are written (-Configure none, or no
    -Configure at all).

.PARAMETER ReadOnly
    Optional. Adds --read-only to the arguments in every config written.

.PARAMETER Uninstall
    Reverse what this script does: remove the server entry from the client
    configs (backing each up first), remove the install directory from the user
    PATH, and delete the installed exe. Never touches your sign-in state and
    never deletes a backup.

.PARAMETER SkipDoctor
    Do not run `accessmcp doctor` at the end. The doctor is the verification
    step; skip it only in unattended runs.

.PARAMETER DryRun
    Print every action without performing any of them. Useful before letting the
    script near a config file you care about.

.PARAMETER Force
    On -Uninstall, remove the client entry even when its command does not point
    at this install directory (that is, an entry this script did not write).

.EXAMPLE
    .\install-accessmcp.ps1 -ExePath .\accessmcp.exe -Configure all -DatabasePath "C:\Data\YourDatabase.accdb"

.EXAMPLE
    .\install-accessmcp.ps1 -FromRelease -ReleaseUrl https://example/accessmcp.exe -Configure cursor,codex -DatabasePath "C:\Data\YourDatabase.accdb"

.EXAMPLE
    .\install-accessmcp.ps1 -Uninstall

.NOTES
    Windows PowerShell 5.1 compatible (that is what ships with Windows); also
    runs on PowerShell 7 on Windows. No secrets, no telemetry, nothing that
    phones home -- the only network call this script can make is the download
    you explicitly ask for with -FromRelease -ReleaseUrl.
#>

[CmdletBinding()]
param(
    [string]   $ExePath,
    [switch]   $FromRelease,
    [string]   $ReleaseUrl,
    [string]   $InstallDir,
    [ValidateSet('claude-code', 'claude-desktop', 'cursor', 'codex', 'all', 'none')]
    [string[]] $Configure,
    [string]   $ServerName = 'accessmcp',
    [string]   $DatabasePath,
    [switch]   $ReadOnly,
    [switch]   $Uninstall,
    [switch]   $SkipDoctor,
    [switch]   $DryRun,
    [switch]   $Force
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------- output helpers

function Write-Head    { param([string]$m) Write-Host ''; Write-Host $m -ForegroundColor Cyan }
function Write-Info    { param([string]$m) Write-Host "  $m" }
function Write-Ok      { param([string]$m) Write-Host "  OK    $m" -ForegroundColor Green }
function Write-Warn2   { param([string]$m) Write-Host "  WARN  $m" -ForegroundColor Yellow }
function Write-Fail    { param([string]$m) Write-Host "  FAIL  $m" -ForegroundColor Red }

# Every step that writes, overwrites or deletes announces itself first, so a
# user reading the transcript can see what was about to happen even if it then
# failed. -DryRun stops right after the announcement.
function Write-Action {
    param([string]$m)
    if ($script:DryRun) { Write-Host "  WOULD $m" -ForegroundColor DarkGray }
    else                { Write-Host "  ..... $m" -ForegroundColor DarkGray }
}

$script:DryRun   = [bool]$DryRun
$script:Problems = New-Object System.Collections.ArrayList

function Add-Problem { param([string]$m) [void]$script:Problems.Add($m); Write-Fail $m }

# ------------------------------------------------------------------ environment

function Test-IsWindows {
    # $IsWindows exists on PowerShell 6+; on 5.1 it is undefined and 5.1 only
    # ever runs on Windows.
    if ($PSVersionTable.PSVersion.Major -le 5) { return $true }
    $v = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
    if ($null -eq $v) { return $true }
    return [bool]$v.Value
}

if (-not (Test-IsWindows)) {
    Write-Host ''
    Write-Host 'AccessMCP is Windows-only, and so is this installer.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'The server drives Microsoft Access through COM and the ACE/OLEDB provider.'
    Write-Host 'Neither exists on macOS or Linux, so there is nothing here that could be'
    Write-Host 'made to work by relaxing this check. Run it on Windows, on the machine'
    Write-Host 'where Access is installed (a Windows VM is fine).'
    Write-Host ''
    exit 1
}

if (-not $InstallDir -or $InstallDir.Trim() -eq '') {
    $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\AccessMCP'
}
$InstallDir    = $InstallDir.TrimEnd('\')
$InstalledExe  = Join-Path $InstallDir 'accessmcp.exe'
$BackupStamp   = Get-Date -Format 'yyyyMMdd-HHmmss'

# --------------------------------------------------------------- native process

# Native commands here (accessmcp doctor, claude, codex) legitimately return
# non-zero: doctor returns 1 when a check FAILs, and that is information, not a
# script error. PowerShell 7.4+ turns a non-zero native exit code into a
# terminating error when $ErrorActionPreference is Stop, so both preferences are
# neutralised inside this function only (function scope shadows script scope).
function Invoke-Native {
    param([string]$FilePath, [string[]]$Arguments = @())
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    # Out-Host, not the pipeline: the command's own output belongs on screen. If
    # it were returned, the caller's `$code = Invoke-Native ...` would collect
    # every printed line alongside the exit code.
    & $FilePath @Arguments | Out-Host
    return $LASTEXITCODE
}

function Test-CommandExists {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# ------------------------------------------------------------------- json files

# ConvertFrom-Json returns PSCustomObjects, which cannot have keys added or
# removed cleanly. Everything is converted to ordered hashtables so a merge is
# an ordinary key assignment and the surrounding content survives untouched.
function ConvertTo-OrderedHashtable {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($k in $InputObject.Keys) { $out[[string]$k] = ConvertTo-OrderedHashtable $InputObject[$k] }
        return $out
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $out = [ordered]@{}
        foreach ($p in $InputObject.PSObject.Properties) { $out[$p.Name] = ConvertTo-OrderedHashtable $p.Value }
        return $out
    }
    if ($InputObject -is [string]) { return $InputObject }
    if ($InputObject -is [System.Collections.IEnumerable]) {
        $list = @()
        foreach ($i in $InputObject) { $list += ,(ConvertTo-OrderedHashtable $i) }
        return ,$list
    }
    return $InputObject
}

function Read-JsonConfig {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($null -eq $raw -or $raw.Trim() -eq '') { return [ordered]@{} }
    # A UTF-8 BOM in front of '{' makes ConvertFrom-Json (and Electron's
    # JSON.parse) choke; strip it before parsing rather than blaming the user.
    $raw = $raw -replace '^\uFEFF', ''
    try {
        return (ConvertTo-OrderedHashtable (ConvertFrom-Json $raw))
    } catch {
        throw "cannot parse $Path as JSON ($($_.Exception.Message)). Refusing to touch it -- fix or move the file, then run this again."
    }
}

function Write-JsonConfig {
    param([string]$Path, $Data)
    # -InputObject, not the pipeline: piping avoids any question of PowerShell
    # unrolling the object before ConvertTo-Json ever sees it.
    $json = ConvertTo-Json -InputObject $Data -Depth 32
    $dir  = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        Write-Action "create directory $dir"
        if (-not $script:DryRun) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
    Write-Action "write $Path"
    if ($script:DryRun) { return }
    # UTF-8 WITHOUT a BOM. Set-Content -Encoding UTF8 on PowerShell 5.1 writes a
    # BOM, and a BOM ahead of '{' breaks JSON.parse in Electron-based clients.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Backup-ConfigFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $backup = "$Path.$BackupStamp.accessmcp.bak"
    Write-Action "back up $Path -> $(Split-Path -Leaf $backup)"
    if (-not $script:DryRun) { Copy-Item -LiteralPath $Path -Destination $backup -Force }
    return $backup
}

# ---------------------------------------------------------------- the arguments

# One argument list, used for every client, so two configs on the same machine
# can never disagree about how the exe is started.
function Get-ServerArguments {
    # Return the array PLAIN (no unary comma): every call site collects with
    # @(...), and `,$a` + @() nested the array — configs came out with
    # args: [[]] instead of args: [] (PR #1 review finding).
    [string[]]$a = @()
    if ($DatabasePath -and $DatabasePath.Trim() -ne '') { $a += $DatabasePath }
    if ($ReadOnly) { $a += '--read-only' }
    return $a
}

# --stdio is deliberately absent: accessmcp.exe speaks stdio and nothing else,
# so the flag selects nothing. The exe still accepts it as a documented no-op
# for configs already in the wild.
function New-ServerEntry {
    param([string]$Command, [switch]$IncludeType)
    $entry = [ordered]@{}
    if ($IncludeType) { $entry['type'] = 'stdio' }   # Cursor and Claude Code document this; Claude Desktop does not.
    $entry['command'] = $Command
    $entry['args']    = @(Get-ServerArguments)
    return $entry
}

# ------------------------------------------------------------- json client edit

function Set-JsonMcpServer {
    param([string]$Path, [string]$Label, [switch]$IncludeType, [switch]$CreateIfMissing)

    Write-Info "$Label -> $Path"
    $existed = Test-Path -LiteralPath $Path
    if (-not $existed -and -not $CreateIfMissing) {
        Write-Warn2 "$Label config not found and not created (this client does not look installed)"
        return $false
    }

    $config = $null
    try { $config = Read-JsonConfig -Path $Path } catch { Add-Problem $_.Exception.Message; return $false }
    if ($null -eq $config) { $config = [ordered]@{} }
    if (-not ($config -is [System.Collections.IDictionary])) {
        Add-Problem "$Path does not contain a JSON object at its root. Refusing to touch it."
        return $false
    }

    if (-not $config.Contains('mcpServers') -or $null -eq $config['mcpServers']) {
        $config['mcpServers'] = [ordered]@{}
    }
    $servers = ConvertTo-OrderedHashtable $config['mcpServers']

    $others = @($servers.Keys | Where-Object { $_ -ne $ServerName })
    if ($others.Count -gt 0) { Write-Info "keeping $($others.Count) other server(s): $($others -join ', ')" }

    if ($existed) { Backup-ConfigFile -Path $Path | Out-Null }

    $servers[$ServerName] = New-ServerEntry -Command $InstalledExe -IncludeType:$IncludeType
    $config['mcpServers'] = $servers

    try { Write-JsonConfig -Path $Path -Data $config } catch { Add-Problem "could not write $Path : $($_.Exception.Message)"; return $false }

    # The script cannot be run here, so it verifies its own output: read the file
    # back and confirm the entry survived serialisation.
    if (-not $script:DryRun) {
        try {
            $check = Read-JsonConfig -Path $Path
            $cmd = $check['mcpServers'][$ServerName]['command']
            if ($cmd -ne $InstalledExe) { Add-Problem "$Label config written but reads back wrong (command = '$cmd')"; return $false }
        } catch {
            Add-Problem "$Label config written but could not be read back: $($_.Exception.Message)"
            return $false
        }
    }
    Write-Ok "$Label configured"
    return $true
}

function Remove-JsonMcpServer {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path)) { Write-Info "$Label : no config at $Path"; return }
    $config = $null
    try { $config = Read-JsonConfig -Path $Path } catch { Add-Problem $_.Exception.Message; return }
    if ($null -eq $config -or -not ($config -is [System.Collections.IDictionary]) -or -not $config.Contains('mcpServers')) {
        Write-Info "$Label : no mcpServers section"
        return
    }

    $servers = ConvertTo-OrderedHashtable $config['mcpServers']
    if (-not $servers.Contains($ServerName)) { Write-Info "$Label : no '$ServerName' entry"; return }

    $cmd = $null
    try { $cmd = [string]$servers[$ServerName]['command'] } catch { $cmd = $null }
    if (-not $Force -and $cmd -and -not $cmd.StartsWith($InstallDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Warn2 "$Label : '$ServerName' points at '$cmd', which this installer did not write. Left in place (-Force removes it anyway)."
        return
    }

    Backup-ConfigFile -Path $Path | Out-Null
    Write-Action "remove '$ServerName' from $Path"
    if (-not $script:DryRun) {
        $servers.Remove($ServerName)
        $config['mcpServers'] = $servers
        try { Write-JsonConfig -Path $Path -Data $config } catch { Add-Problem "could not write $Path : $($_.Exception.Message)"; return }
    }
    Write-Ok "$Label : '$ServerName' removed"
}

# ---------------------------------------------------------------- claude desktop

function Get-ClaudeDesktopConfigPaths {
    # The documented location.
    $paths = @(Join-Path $env:APPDATA 'Claude\claude_desktop_config.json')

    # UNVERIFIED-BY-VENDOR, BUT REAL: an MSIX (Microsoft Store) install of Claude
    # Desktop reads a virtualised copy under %LOCALAPPDATA%\Packages\Claude_*,
    # while its own "Edit Config" button opens the %APPDATA% path -- two files
    # that never sync, so a server written to the wrong one is ignored silently
    # (anthropics/claude-code#26073). Matched by wildcard, never by a hardcoded
    # package id, and only when the directory already exists: this script does
    # not create a packaged layout that a plain install would not have.
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $pkgRoot) {
        Get-ChildItem -LiteralPath $pkgRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object {
            $dir = Join-Path $_.FullName 'LocalCache\Roaming\Claude'
            if (Test-Path -LiteralPath $dir) { $paths += (Join-Path $dir 'claude_desktop_config.json') }
        }
    }
    return ,($paths | Select-Object -Unique)
}

# ------------------------------------------------------------------------- codex

function Get-CodexConfigPath {
    $home2 = $env:CODEX_HOME
    if (-not $home2 -or $home2.Trim() -eq '') { $home2 = Join-Path $env:USERPROFILE '.codex' }
    return (Join-Path $home2 'config.toml')
}

function Format-TomlString {
    param([string]$Value)
    # A TOML literal string ('...') needs no backslash escaping, which is what a
    # Windows path wants -- but it cannot contain a single quote, and Windows
    # user names can (C:\Users\O'Brien). Fall back to a basic string then, where
    # backslashes and quotes do have to be escaped. String.Replace, not
    # -replace: a regex replacement string treats backslashes differently and
    # would double them twice over.
    if ($Value.Contains("'")) {
        $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
        return '"' + $escaped + '"'
    }
    return "'" + $Value + "'"
}

function New-CodexBlockLines {
    $lines = @("[mcp_servers.$ServerName]")
    $lines += "command = $(Format-TomlString $InstalledExe)"
    $argList = @(Get-ServerArguments)
    if ($argList.Count -eq 0) {
        $lines += 'args = []'
    } else {
        $lines += 'args = [' + (($argList | ForEach-Object { Format-TomlString $_ }) -join ', ') + ']'
    }
    return ,$lines
}

function Test-CodexInlineTable {
    param([string[]]$Lines)
    foreach ($l in $Lines) { if ($l -match '^\s*mcp_servers\s*=') { return $true } }
    return $false
}

function Get-CodexSectionRange {
    # Returns @{Start=<int>; End=<int>} for [mcp_servers.<name>] (End is
    # exclusive, at the next table header), or $null when the section is absent.
    param([string[]]$Lines, [switch]$IncludeSubTables)
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $t = $Lines[$i].Trim()
        if ($t -eq "[mcp_servers.$ServerName]" -or $t -eq "[mcp_servers.`"$ServerName`"]") { $start = $i; break }
    }
    if ($start -lt 0) { return $null }

    $end = $Lines.Count
    for ($j = $start + 1; $j -lt $Lines.Count; $j++) {
        $t = $Lines[$j].Trim()
        if ($t.StartsWith('[')) {
            # When removing, swallow this server's own sub-tables too
            # ([mcp_servers.accessmcp.env] and friends) -- leaving them behind
            # would re-declare the server with no command and break Codex.
            if ($IncludeSubTables -and ($t.StartsWith("[mcp_servers.$ServerName.") -or $t.StartsWith("[mcp_servers.`"$ServerName`"."))) { continue }
            $end = $j
            break
        }
    }
    return @{ Start = $start; End = $end }
}

function Set-CodexServer {
    $path = Get-CodexConfigPath
    Write-Info "Codex CLI -> $path"

    $blockLines = @(New-CodexBlockLines)

    if (-not (Test-Path -LiteralPath $path)) {
        $dir = Split-Path -Path $path -Parent
        Write-Action "create $path (Codex has no config.toml yet)"
        if (-not $script:DryRun) {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllLines($path, [string[]]$blockLines, $utf8NoBom)
        }
        Write-Ok 'Codex CLI configured'
        return
    }

    $lines = @(Get-Content -LiteralPath $path)
    if (Test-CodexInlineTable -Lines $lines) {
        Write-Warn2 'Codex config.toml declares mcp_servers as a top-level inline table.'
        Write-Warn2 'A targeted edit cannot rewrite that form safely, so nothing was changed. Add this by hand:'
        $blockLines | ForEach-Object { Write-Host "        $_" }
        return
    }

    $range = Get-CodexSectionRange -Lines $lines
    Backup-ConfigFile -Path $path | Out-Null

    if ($null -ne $range) {
        Write-Action "replace the existing [mcp_servers.$ServerName] block in $path (lines $($range.Start + 1)-$($range.End))"
        $new = @()
        if ($range.Start -gt 0) { $new += $lines[0..($range.Start - 1)] }
        $new += $blockLines
        if ($range.End -lt $lines.Count) { $new += $lines[$range.End..($lines.Count - 1)] }
    } else {
        Write-Action "append [mcp_servers.$ServerName] to $path (every other line untouched)"
        $new = @($lines)
        if ($new.Count -gt 0 -and $new[$new.Count - 1].Trim() -ne '') { $new += '' }
        $new += $blockLines
    }

    if (-not $script:DryRun) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($path, [string[]]$new, $utf8NoBom)
    }
    Write-Ok 'Codex CLI configured'
}

function Remove-CodexServer {
    $path = Get-CodexConfigPath
    if (-not (Test-Path -LiteralPath $path)) { Write-Info "Codex CLI : no config at $path"; return }

    $lines = @(Get-Content -LiteralPath $path)
    if (Test-CodexInlineTable -Lines $lines) {
        Write-Warn2 "Codex config.toml uses an inline mcp_servers table; remove '$ServerName' by hand."
        return
    }
    $range = Get-CodexSectionRange -Lines $lines -IncludeSubTables
    if ($null -eq $range) { Write-Info "Codex CLI : no [mcp_servers.$ServerName] section"; return }

    $body = ($lines[$range.Start..($range.End - 1)] -join "`n")
    if (-not $Force -and $body -notmatch [regex]::Escape($InstallDir)) {
        Write-Warn2 "Codex CLI : [mcp_servers.$ServerName] does not point at $InstallDir. Left in place (-Force removes it anyway)."
        return
    }

    Backup-ConfigFile -Path $path | Out-Null
    Write-Action "remove [mcp_servers.$ServerName] from $path (lines $($range.Start + 1)-$($range.End))"
    if (-not $script:DryRun) {
        $new = @()
        if ($range.Start -gt 0) { $new += $lines[0..($range.Start - 1)] }
        if ($range.End -lt $lines.Count) { $new += $lines[$range.End..($lines.Count - 1)] }
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($path, [string[]]$new, $utf8NoBom)
    }
    Write-Ok "Codex CLI : '$ServerName' removed"
}

# ------------------------------------------------------------------ claude code

function Set-ClaudeCodeServer {
    # ~/.claude.json holds far more than MCP servers, so this script never
    # hand-merges it: the `claude` CLI owns that file. Without the CLI, print the
    # exact command instead of guessing at the format.
    $cmdArgs = @('mcp', 'add', '--transport', 'stdio', '--scope', 'user', $ServerName, '--', $InstalledExe) + @(Get-ServerArguments)
    $shown   = 'claude ' + (($cmdArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')

    if (-not (Test-CommandExists 'claude')) {
        Write-Warn2 'Claude Code CLI (`claude`) not found on PATH. Nothing was written.'
        Write-Warn2 'Once Claude Code is installed, run:'
        Write-Host  "        $shown"
        Write-Warn2 "Or copy packaging/claude-code/mcp.template.json to .mcp.json in your project."
        return
    }

    Write-Info "Claude Code -> user scope, via the claude CLI"
    # `claude mcp add` refuses to overwrite an existing name, so removing first
    # is what makes a re-run idempotent. A failure here is expected when the
    # server was not there.
    Write-Action "run: claude mcp remove $ServerName   (ignored if absent, makes the add idempotent)"
    if (-not $script:DryRun) { Invoke-Native -FilePath 'claude' -Arguments @('mcp', 'remove', $ServerName) | Out-Null }

    Write-Action "run: $shown"
    if (-not $script:DryRun) {
        $code = Invoke-Native -FilePath 'claude' -Arguments $cmdArgs
        if ($code -ne 0) { Add-Problem "claude mcp add exited $code"; return }
    }
    Write-Ok 'Claude Code configured (verify with: claude mcp list)'
}

function Remove-ClaudeCodeServer {
    if (-not (Test-CommandExists 'claude')) {
        Write-Info ('Claude Code : the claude CLI is not on PATH; if you added the server, remove it with: claude mcp remove ' + $ServerName)
        return
    }
    Write-Action "run: claude mcp remove $ServerName"
    if (-not $script:DryRun) {
        $code = Invoke-Native -FilePath 'claude' -Arguments @('mcp', 'remove', $ServerName)
        if ($code -ne 0) { Write-Info "Claude Code : nothing to remove (claude mcp remove exited $code)"; return }
    }
    Write-Ok "Claude Code : '$ServerName' removed"
}

# ------------------------------------------------------------------- user PATH

function Get-UserPathEntry {
    # Read the RAW value, so a %USERPROFILE%-style entry is not expanded on the
    # way in and then written back expanded on the way out.
    $key = Get-Item -LiteralPath 'HKCU:\Environment'
    $kind = 'ExpandString'   # what Windows itself uses for the user Path
    if ($key.GetValueNames() -contains 'Path') { $kind = [string]$key.GetValueKind('Path') }
    $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    return @{ Raw = $raw; Kind = $kind }
}

function Set-UserPathEntry {
    param([string]$Value, [string]$Kind)
    if ($script:DryRun) { return }
    # Written through the registry rather than [Environment]::SetEnvironmentVariable
    # so REG_EXPAND_SZ stays REG_EXPAND_SZ; the .NET call can flatten it to
    # REG_SZ and silently break every %VAR% already in the user's PATH.
    Set-ItemProperty -LiteralPath 'HKCU:\Environment' -Name 'Path' -Value $Value -Type $Kind
    Publish-EnvironmentChange
}

function Publish-EnvironmentChange {
    # Tell already-running shells and Explorer that the environment changed.
    # Best effort: if it fails, the only cost is that the user opens a new
    # terminal, which the summary tells them anyway.
    try {
        if (-not ('AccessMcpInstaller.NativeMethods' -as [type])) {
            Add-Type -Namespace 'AccessMcpInstaller' -Name 'NativeMethods' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@ | Out-Null
        }
        $result = [System.UIntPtr]::Zero
        # HWND_BROADCAST = 0xffff, WM_SETTINGCHANGE = 0x1A, SMTO_ABORTIFHUNG = 2
        [void][AccessMcpInstaller.NativeMethods]::SendMessageTimeout([System.IntPtr]0xffff, 0x1A, [System.UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    } catch {
        Write-Info 'Could not broadcast the environment change; open a new terminal to pick up PATH.'
    }
}

function Test-PathContainsDir {
    param([string[]]$Entries, [string]$Dir)
    foreach ($e in $Entries) {
        if (-not $e) { continue }
        $trimmed = $e.Trim().TrimEnd('\')
        if ($trimmed -eq '') { continue }
        if ($trimmed -ieq $Dir) { return $true }
        try { if ([Environment]::ExpandEnvironmentVariables($trimmed).TrimEnd('\') -ieq $Dir) { return $true } } catch { }
    }
    return $false
}

function Add-InstallDirToUserPath {
    $current = Get-UserPathEntry
    $entries = @($current.Raw -split ';')
    if (Test-PathContainsDir -Entries $entries -Dir $InstallDir) {
        Write-Ok "user PATH already contains $InstallDir"
        return
    }
    $new = (@($entries | Where-Object { $_ -and $_.Trim() -ne '' }) + $InstallDir) -join ';'
    Write-Action "add $InstallDir to the USER PATH (HKCU\Environment; no admin rights, machine PATH untouched)"
    Set-UserPathEntry -Value $new -Kind $current.Kind
    if (-not $script:DryRun) { $env:Path = "$env:Path;$InstallDir" }
    Write-Ok "user PATH updated (open a new terminal for it to take effect)"
}

function Remove-InstallDirFromUserPath {
    $current = Get-UserPathEntry
    $entries = @($current.Raw -split ';')
    $kept = @($entries | Where-Object {
        if (-not $_ -or $_.Trim() -eq '') { return $false }
        $t = $_.Trim().TrimEnd('\')
        if ($t -ieq $InstallDir) { return $false }
        try { if ([Environment]::ExpandEnvironmentVariables($t).TrimEnd('\') -ieq $InstallDir) { return $false } } catch { }
        return $true
    })
    if ($kept.Count -eq @($entries | Where-Object { $_ -and $_.Trim() -ne '' }).Count) {
        Write-Info "user PATH does not contain $InstallDir"
        return
    }
    Write-Action "remove $InstallDir from the USER PATH"
    Set-UserPathEntry -Value ($kept -join ';') -Kind $current.Kind
    Write-Ok 'user PATH cleaned'
}

# ----------------------------------------------------------------------- doctor

function Invoke-Doctor {
    if ($SkipDoctor) { Write-Info 'doctor skipped (-SkipDoctor)'; return }
    if ($script:DryRun) { Write-Info "would run: `"$InstalledExe`" doctor"; return }
    if (-not (Test-Path -LiteralPath $InstalledExe)) { Write-Warn2 'no installed exe to run doctor with'; return }

    Write-Head 'Verifying with `accessmcp doctor`'
    # Called by absolute path, never through PATH: the diagnostic must describe
    # the exe this script just installed, not whatever else may be on PATH.
    $code = Invoke-Native -FilePath $InstalledExe -Arguments @('doctor')
    Write-Host ''
    if ($code -eq 0) {
        Write-Ok 'doctor: every check passed (exit 0)'
    } elseif ($code -eq 1) {
        Write-Warn2 'doctor: at least one check FAILed (exit 1). Each FAIL above carries a Fix: line -- follow it, then run the doctor again.'
        Write-Info  "Command: `"$InstalledExe`" doctor"
    } else {
        Write-Warn2 "doctor exited $code (it could not run). Is this the win-x64 build on 64-bit Windows?"
    }
}

# --------------------------------------------------------------- exe deployment

function Resolve-SourceExe {
    if ($FromRelease) {
        if ($ExePath) { throw '-ExePath and -FromRelease are mutually exclusive.' }
        if (-not $ReleaseUrl -or $ReleaseUrl.Trim() -eq '') {
            throw @'
-FromRelease needs -ReleaseUrl.

No download URL is hardcoded in this installer, on purpose: a stale URL baked
into a script is worse than no URL, and this script must never fetch something
you did not name. Take the accessmcp.exe asset URL from
https://github.com/A-Point-Systems-ltd/access-mcp/releases (or from your own
internal mirror) and pass it:

  .\install-accessmcp.ps1 -FromRelease -ReleaseUrl <https url to accessmcp.exe>
'@
        }
        if ($ReleaseUrl -notmatch '^https://') { throw "-ReleaseUrl must be https (got: $ReleaseUrl)" }

        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "accessmcp-download-$BackupStamp.exe"
        Write-Action "download $ReleaseUrl -> $tmp"
        if ($script:DryRun) { return $tmp }
        # PowerShell 5.1 still defaults to TLS 1.0 in some configurations.
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
        Invoke-WebRequest -Uri $ReleaseUrl -OutFile $tmp -UseBasicParsing
        return $tmp
    }

    if (-not $ExePath -or $ExePath.Trim() -eq '') {
        throw 'Nothing to install. Pass -ExePath <path to accessmcp.exe>, or -FromRelease -ReleaseUrl <url>.'
    }
    if (-not (Test-Path -LiteralPath $ExePath)) { throw "not found: $ExePath" }
    $resolved = (Resolve-Path -LiteralPath $ExePath).Path
    if ([System.IO.Path]::GetExtension($resolved) -ne '.exe') { throw "not an .exe: $resolved" }
    return $resolved
}

function Install-Exe {
    param([string]$Source)

    if (-not (Test-Path -LiteralPath $InstallDir)) {
        Write-Action "create $InstallDir"
        if (-not $script:DryRun) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
    }

    if ((Test-Path -LiteralPath $InstalledExe) -and -not $script:DryRun) {
        try {
            $a = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
            $b = (Get-FileHash -LiteralPath $InstalledExe -Algorithm SHA256).Hash
            if ($a -eq $b) { Write-Ok "$InstalledExe is already this exact build"; return }
        } catch { }
        Write-Action "OVERWRITE the existing $InstalledExe"
    } else {
        Write-Action "copy accessmcp.exe -> $InstalledExe"
    }

    if ($script:DryRun) { return }
    try {
        Copy-Item -LiteralPath $Source -Destination $InstalledExe -Force
    } catch {
        throw "could not write $InstalledExe : $($_.Exception.Message). If a client is running the server, close it (Cursor, Claude Desktop, Claude Code, Codex) and run this again."
    }
    Write-Ok "installed $InstalledExe"

    # Mark-of-the-web is left alone on purpose: stripping a security marker is
    # the user's call, not an installer's.
    try {
        if (Get-Item -LiteralPath $InstalledExe -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue) {
            Write-Info 'The exe carries a mark-of-the-web (downloaded file). If Windows blocks it, run:'
            Write-Info "  Unblock-File -LiteralPath `"$InstalledExe`""
        }
    } catch { }

    $code = Invoke-Native -FilePath $InstalledExe -Arguments @('--version')
    if ($code -ne 0) { Write-Warn2 "`"$InstalledExe`" --version exited $code -- the exe may not run on this machine." }
}

function Uninstall-Exe {
    if (Test-Path -LiteralPath $InstalledExe) {
        Write-Action "delete $InstalledExe"
        if (-not $script:DryRun) {
            try { Remove-Item -LiteralPath $InstalledExe -Force } catch { Add-Problem "could not delete $InstalledExe : $($_.Exception.Message) (is a client still running it?)"; return }
        }
        Write-Ok "removed $InstalledExe"
    } else {
        Write-Info "no exe at $InstalledExe"
    }

    if (Test-Path -LiteralPath $InstallDir) {
        $left = @(Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) {
            Write-Action "delete the now-empty $InstallDir"
            if (-not $script:DryRun) { Remove-Item -LiteralPath $InstallDir -Force }
            Write-Ok "removed $InstallDir"
        } else {
            Write-Warn2 "$InstallDir still contains $($left.Count) item(s); left in place. Delete it yourself if you want it gone."
        }
    }
}

# -------------------------------------------------------------------- targets

function Resolve-Targets {
    param([string[]]$Requested, [string]$DefaultWhenEmpty)
    if ($null -eq $Requested -or $Requested.Count -eq 0) { $Requested = @($DefaultWhenEmpty) }
    # The leading comma keeps these arrays arrays: a bare `return @()` from a
    # PowerShell function arrives at the caller as $null.
    if ($Requested -contains 'none') {
        if ($Requested.Count -gt 1) { Write-Warn2 "-Configure includes 'none'; no client configs will be touched." }
        return ,@()
    }
    if ($Requested -contains 'all') { return ,@('claude-code', 'claude-desktop', 'cursor', 'codex') }
    return ,@($Requested | Select-Object -Unique)
}

$CursorConfigPath = Join-Path $env:USERPROFILE '.cursor\mcp.json'

# =============================================================================
#  main
# =============================================================================

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Cyan
Write-Host '  AccessMCP - per-user installer (no admin rights)   ' -ForegroundColor Cyan
Write-Host '=====================================================' -ForegroundColor Cyan
if ($script:DryRun) { Write-Host '  -DryRun: nothing will be created, written or deleted.' -ForegroundColor DarkGray }

try {
    if ($Uninstall) {
        Write-Head 'Uninstalling'
        Write-Info "install directory : $InstallDir"
        Write-Info "server name       : $ServerName"
        Write-Info 'Backups are never deleted, and your sign-in is left alone.'

        $targets = Resolve-Targets -Requested $Configure -DefaultWhenEmpty 'all'

        if ($targets.Count -gt 0) { Write-Head 'Client configs' }
        foreach ($t in $targets) {
            switch ($t) {
                'claude-code'    { Remove-ClaudeCodeServer }
                'claude-desktop' { foreach ($p in (Get-ClaudeDesktopConfigPaths)) { Remove-JsonMcpServer -Path $p -Label 'Claude Desktop' } }
                'cursor'         { Remove-JsonMcpServer -Path $CursorConfigPath -Label 'Cursor' }
                'codex'          { Remove-CodexServer }
            }
        }

        Write-Head 'User PATH'
        Remove-InstallDirFromUserPath

        Write-Head 'Executable'
        Uninstall-Exe

        Write-Head 'Deliberately NOT removed'
        Write-Info "your sign-in (%APPDATA%\AccessMCP\credentials.bin) - uninstalling is not signing out"
        Write-Info 'every *.accessmcp.bak backup this script ever wrote'
        Write-Info 'any accessmcp.exe you installed by hand somewhere else, and any config pointing at it'
    }
    else {
        Write-Head 'Plan'
        Write-Info "install directory : $InstallDir"
        Write-Info "executable        : $InstalledExe"
        Write-Info "server name       : $ServerName"
        $argPreview = @(Get-ServerArguments)
        Write-Info ("arguments         : " + $(if ($argPreview.Count -eq 0) { '(none)' } else { ($argPreview -join ' ') }))

        # v2.4.0: the server runs only against the database pinned as its first
        # argument. Refuse to register a client with no pin -- that would write
        # a config the server rejects -- and refuse BEFORE touching anything.
        $plannedTargets = Resolve-Targets -Requested $Configure -DefaultWhenEmpty 'none'
        if ($plannedTargets.Count -gt 0 -and -not ($DatabasePath -and $DatabasePath.Trim() -ne '')) {
            throw ("-Configure writes client configs, and the server requires the database pinned as its first argument (v2.4.0). " +
                   "Re-run with -DatabasePath 'C:\Data\YourDatabase.accdb' -- the Access file this server is allowed to work on.")
        }
        if ($plannedTargets.Count -gt 0 -and -not (Test-Path -LiteralPath $DatabasePath)) {
            Write-Warn2 "database file not found at $DatabasePath -- writing the config anyway; make sure the path is right before a client starts the server."
        }
        if ($env:LOCALAPPDATA -and -not $InstallDir.StartsWith($env:LOCALAPPDATA, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Warn2 "$InstallDir is outside %LOCALAPPDATA%; if it is a protected location this will need administrator rights, which the default location exists to avoid."
        }

        Write-Head 'Executable'
        $source = Resolve-SourceExe
        Install-Exe -Source $source

        Write-Head 'User PATH'
        Add-InstallDirToUserPath

        $targets = $plannedTargets
        if ($targets.Count -eq 0) {
            Write-Head 'Client configs'
            Write-Info 'None requested. Add one with -Configure claude-code,claude-desktop,cursor,codex or -Configure all,'
            Write-Info 'or paste the template from the matching packaging/<client>/ directory by hand.'
        } else {
            Write-Head 'Client configs (merged, never overwritten; each backed up first)'
            foreach ($t in $targets) {
                switch ($t) {
                    'claude-code'    { Set-ClaudeCodeServer }
                    'claude-desktop' {
                        foreach ($p in (Get-ClaudeDesktopConfigPaths)) {
                            # Create the documented %APPDATA% file if it is missing;
                            # only merge into an MSIX copy that already exists.
                            $isDocumented = $p -ieq (Join-Path $env:APPDATA 'Claude\claude_desktop_config.json')
                            Set-JsonMcpServer -Path $p -Label 'Claude Desktop' -CreateIfMissing:$isDocumented | Out-Null
                        }
                    }
                    'cursor'         {
                        Set-JsonMcpServer -Path $CursorConfigPath -Label 'Cursor' -IncludeType -CreateIfMissing | Out-Null
                        try {
                            $cfgObj = [ordered]@{ type = 'stdio'; command = $InstalledExe; args = @(Get-ServerArguments) }
                            # base64 of the INNER server object, without the name
                            # wrapping it -- that is the shape Cursor's install-link
                            # docs encode.
                            $cfg = ConvertTo-Json -InputObject $cfgObj -Compress
                            $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cfg))
                            Write-Info 'Cursor one-click link for this machine (optional, the config above is already written):'
                            Write-Host  "        cursor://anysphere.cursor-deeplink/mcp/install?name=$ServerName&config=$b64"
                        } catch { }
                    }
                    'codex'          { Set-CodexServer }
                }
            }
            Write-Info ''
            Write-Info 'Restart any client you just configured - they read their config at startup.'
        }

        Invoke-Doctor
    }

    Write-Head 'Summary'
    if ($script:Problems.Count -eq 0) {
        Write-Ok 'done, with no errors'
        if (-not $Uninstall) {
            Write-Info 'The exe is the product; everything else here is a shortcut. You can always'
            Write-Info 'point any client at it by hand:'
            Write-Info "  `"$InstalledExe`""
        }
        exit 0
    } else {
        Write-Host ''
        Write-Fail "$($script:Problems.Count) problem(s):"
        $script:Problems | ForEach-Object { Write-Host "        - $_" -ForegroundColor Red }
        exit 1
    }
}
catch {
    Write-Host ''
    Write-Fail $_.Exception.Message
    Write-Host ''
    exit 1
}

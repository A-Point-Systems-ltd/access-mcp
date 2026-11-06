# check-ps1-encoding.ps1 - every PowerShell script in this repo must parse in
# Windows PowerShell 5.1 on any Windows locale.
#
# Why: the plugins launch powershell.exe (5.1), which reads a .ps1 WITHOUT a
# BOM in the system ANSI code page. One UTF-8 em dash (E2 80 94) decodes under
# Hebrew code page 1255 to a sequence ending in U+201D, a quote PowerShell
# treats as a string terminator, and the whole bootstrap fails to parse - the
# MCP server never starts ("Connection closed"). CI's pwsh reads UTF-8, so it
# stayed green while 2.4.0 and 2.5.0 were dead on such machines.
#
# Fails when any tracked .ps1/.psm1/.psd1:
#   1. contains a non-ASCII character (ASCII reads the same in every code page), or
#   2. does not parse when read the way PS 5.1 reads it on a Hebrew machine:
#      a UTF-8 BOM wins; without one the bytes are decoded as Windows-1255.
# Parse only - nothing is run.
#
# Usage: pwsh -File scripts/check-ps1-encoding.ps1 [repo-root]

param([string] $Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# pwsh (.NET Core) ships only Unicode encodings until the code-page provider is
# registered; Windows PowerShell 5.1 has them built in.
try { [Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance) } catch { }
$cp1255 = [Text.Encoding]::GetEncoding(1255)

Push-Location $Root
try { $files = @(git ls-files -- '*.ps1' '*.psm1' '*.psd1') }
finally { Pop-Location }

$failed = 0
foreach ($rel in $files) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $Root $rel))
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $body = if ($bom) { [byte[]]($bytes | Select-Object -Skip 3) } else { $bytes }

    $lineNo = 1
    foreach ($b in $body) {
        if ($b -eq 10) { $lineNo++ }
        elseif ($b -gt 127) {
            [Console]::Error.WriteLine("${rel}:${lineNo}: non-ASCII byte 0x{0:X2} - use ASCII only" -f $b)
            $failed++
            break
        }
    }

    $text = if ($bom) { [Text.Encoding]::UTF8.GetString($body) } else { $cp1255.GetString($body) }
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $first = $errors[0]
        [Console]::Error.WriteLine("${rel}: $($errors.Count) parse error(s) under Windows-1255, first at line $($first.Extent.StartLineNumber): $($first.Message)")
        $failed++
    }
}

if ($failed) {
    [Console]::Error.WriteLine("check-ps1-encoding: $failed problem(s) in $($files.Count) PowerShell file(s)")
    exit 1
}
Write-Output "check-ps1-encoding: $($files.Count) PowerShell file(s) are ASCII and parse under Windows-1255"

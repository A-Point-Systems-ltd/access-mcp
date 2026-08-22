# Pester tests for the bootstrap's pure logic. Run anywhere (Linux CI
# included): the ACCESSMCP_BOOTSTRAP_TEST hook loads the functions without
# touching Windows paths or the network.
#
#   Invoke-Pester -Path tests/bootstrap.tests.ps1

BeforeAll {
    $env:ACCESSMCP_BOOTSTRAP_TEST = '1'
    . (Join-Path $PSScriptRoot '../agent-plugin/bootstrap/bootstrap.ps1')

    function New-Manifest([hashtable] $Overrides = @{}) {
        $m = [pscustomobject]@{
            version    = '2.3.1'
            exe_url    = 'https://github.com/A-Point-Systems-ltd/access-mcp/releases/download/v2.3.1/accessmcp.exe'
            exe_sha256 = 'a'.PadRight(64, 'a')
        }
        foreach ($k in $Overrides.Keys) {
            if ($m.PSObject.Properties[$k]) { $m.$k = $Overrides[$k] }
            else { $m | Add-Member -NotePropertyName $k -NotePropertyValue $Overrides[$k] }
        }
        $m
    }
}

Describe 'Assert-ManifestShape' {
    It 'accepts a well-formed manifest' {
        { Assert-ManifestShape (New-Manifest) 'test' } | Should -Not -Throw
    }

    It 'rejects a missing field' -ForEach @('version', 'exe_url', 'exe_sha256') {
        $m = New-Manifest @{ $_ = '' }
        { Assert-ManifestShape $m 'test' } | Should -Throw "*missing '$_'*"
    }

    It 'rejects an exe_url outside the pinned release pattern' {
        $m = New-Manifest @{ exe_url = 'https://github.com/A-Point-Systems-ltd/access-mcp/releases/latest/download/accessmcp.exe' }
        { Assert-ManifestShape $m 'test' } | Should -Throw '*pinned release pattern*'
    }

    It 'rejects a foreign host' {
        $m = New-Manifest @{ exe_url = 'https://evil.example.com/releases/download/v2.3.1/accessmcp.exe' }
        { Assert-ManifestShape $m 'test' } | Should -Throw '*pinned release pattern*'
    }

    It 'rejects a URL tag that disagrees with the version (TOCTOU / stale-URL guard)' {
        $m = New-Manifest @{ version = '2.5.0' }   # url still says v2.3.1
        { Assert-ManifestShape $m 'test' } | Should -Throw '*exe_url tag v2.3.1 != version 2.5.0*'
    }

    It 'rejects a malformed or placeholder sha256' -ForEach @('', '1234', ('0' * 63 + 'g')) {
        $m = New-Manifest @{ exe_sha256 = $_ }
        { Assert-ManifestShape $m 'test' } | Should -Throw
    }

    It 'accepts the all-zero placeholder shape (the release pipeline, not the shape check, blocks it)' {
        # The bootstrap will download and then fail the hash comparison —
        # the shape check only guards structure.
        $m = New-Manifest @{ exe_sha256 = ('0' * 64) }
        { Assert-ManifestShape $m 'test' } | Should -Not -Throw
    }
}

Describe 'Compare-Version' {
    It 'orders plain versions' {
        Compare-Version '2.4.0' '2.3.1' | Should -BeGreaterThan 0
        Compare-Version '2.3.1' '2.4.0' | Should -BeLessThan 0
        Compare-Version '2.3.1' '2.3.1' | Should -Be 0
    }
    It 'orders double-digit components numerically, not lexically' {
        Compare-Version '2.10.0' '2.9.9' | Should -BeGreaterThan 0
    }
}

Describe 'Get-Prop (StrictMode-safe access)' {
    It 'returns the value when present' {
        Get-Prop ([pscustomobject]@{ a = 1 }) 'a' | Should -Be 1
    }
    It 'returns null for a missing property instead of throwing under StrictMode' {
        Get-Prop ([pscustomobject]@{ a = 1 }) 'b' | Should -BeNullOrEmpty
    }
    It 'returns null for a null object' {
        Get-Prop $null 'a' | Should -BeNullOrEmpty
    }
}

Describe 'Read-Json / Write-JsonAtomic' {
    It 'round-trips through an atomic write' {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("accessmcp-test-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        try {
            $p = Join-Path $dir 'x.json'
            Write-JsonAtomic ([pscustomobject]@{ version = '2.3.1'; n = 7 }) $p
            $back = Read-Json $p
            $back.version | Should -Be '2.3.1'
            $back.n | Should -Be 7
            Get-ChildItem $dir -Filter '*.tmp.*' | Should -BeNullOrEmpty
        }
        finally { Remove-Item $dir -Recurse -Force }
    }
    It 'returns null for a missing or corrupt file' {
        Read-Json (Join-Path ([IO.Path]::GetTempPath()) 'no-such-file.json') | Should -BeNullOrEmpty
    }
}

Describe 'Assert-ExeTrusted / Test-CachedVersion (version + BYTES pin)' {
    BeforeEach {
        $script:VersionsDir = Join-Path ([IO.Path]::GetTempPath()) ("accessmcp-httest-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:VersionsDir | Out-Null
    }
    AfterEach {
        Remove-Item $script:VersionsDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'accepts an exe whose bytes match the pinned hash' {
        $exe = Get-ExePathFor '2.3.1'
        New-Item -ItemType Directory -Force -Path (Split-Path $exe) | Out-Null
        [IO.File]::WriteAllText($exe, 'the right bytes')
        $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
        $m = New-Manifest @{ exe_sha256 = $hash }
        { Assert-ExeTrusted $exe $m } | Should -Not -Throw
        Test-CachedVersion $m | Should -BeTrue
    }

    It 'rejects a cached entry with the right version name but WRONG bytes' {
        # The round-4 finding: versions\2.3.1\ exists but holds different
        # bytes than the manifest pins — must NOT count as installed.
        $exe = Get-ExePathFor '2.3.1'
        New-Item -ItemType Directory -Force -Path (Split-Path $exe) | Out-Null
        [IO.File]::WriteAllText($exe, 'tampered / stale bytes')
        $m = New-Manifest   # pins the aaaa... hash, not these bytes
        { Assert-ExeTrusted $exe $m } | Should -Throw '*SHA256 mismatch*'
        Test-CachedVersion $m | Should -BeFalse
        Test-InstalledVersion '2.3.1' | Should -BeTrue   # exists — but existence is no longer enough
    }

    It 'returns false when the pinned version is simply not cached' {
        Test-CachedVersion (New-Manifest) | Should -BeFalse
    }

    It 'does not require Authenticode while the manifest says unsigned' {
        $exe = Get-ExePathFor '2.3.1'
        New-Item -ItemType Directory -Force -Path (Split-Path $exe) | Out-Null
        [IO.File]::WriteAllText($exe, 'unsigned era bytes')
        $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
        $m = New-Manifest @{ exe_sha256 = $hash; signing = [pscustomobject]@{ status = 'unsigned'; subject = ''; thumbprint = '' } }
        { Assert-ExeTrusted $exe $m } | Should -Not -Throw
    }

    It 'demands a signature the moment the manifest says ev (plain file must fail)' {
        $exe = Get-ExePathFor '2.3.1'
        New-Item -ItemType Directory -Force -Path (Split-Path $exe) | Out-Null
        [IO.File]::WriteAllText($exe, 'bytes that are not signed')
        $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
        $m = New-Manifest @{ exe_sha256 = $hash; signing = [pscustomobject]@{ status = 'ev'; subject = 'A-Point Systems Ltd'; thumbprint = 'AB12' } }
        { Assert-ExeTrusted $exe $m } | Should -Throw '*Authenticode*'
    }
}

Describe 'Invoke-QuarantineVersion' {
    It 'moves a corrupt cache entry aside instead of deleting it' {
        $script:Root = Join-Path ([IO.Path]::GetTempPath()) ("accessmcp-qtest-" + [guid]::NewGuid().ToString('N'))
        $script:VersionsDir = Join-Path $script:Root 'versions'
        try {
            $exe = Get-ExePathFor '2.3.1'
            New-Item -ItemType Directory -Force -Path (Split-Path $exe) | Out-Null
            [IO.File]::WriteAllText($exe, 'bad bytes')
            Invoke-QuarantineVersion '2.3.1'
            Test-Path (Split-Path $exe) | Should -BeFalse
            @(Get-ChildItem $script:Root -Directory -Filter 'quarantine-2.3.1-*').Count | Should -Be 1
        }
        finally { Remove-Item $script:Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'version-cache path helpers' {
    It 'resolves and detects an installed pinned version' {
        $script:VersionsDir = Join-Path ([IO.Path]::GetTempPath()) ("accessmcp-vtest-" + [guid]::NewGuid().ToString('N'))
        try {
            Test-InstalledVersion '2.3.1' | Should -BeFalse
            $exe = Get-ExePathFor '2.3.1'
            New-Item -ItemType Directory -Force -Path (Split-Path $exe) | Out-Null
            Set-Content -Path $exe -Value 'stub'
            Test-InstalledVersion '2.3.1' | Should -BeTrue
            Test-InstalledVersion '2.4.0' | Should -BeFalse
            Test-InstalledVersion ''      | Should -BeFalse
        }
        finally { Remove-Item $script:VersionsDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

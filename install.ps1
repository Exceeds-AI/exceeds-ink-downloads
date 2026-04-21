param(
    [string]$Version = $(if ($env:EXCEEDS_INK_VERSION) { $env:EXCEEDS_INK_VERSION } else { "latest" }),
    [string]$Repo = $(if ($env:EXCEEDS_INK_REPO) { $env:EXCEEDS_INK_REPO } else { "Exceeds-AI/exceeds-ink-downloads" }),
    [string]$DownloadBase = $env:EXCEEDS_INK_DOWNLOAD_BASE_URL,
    [string]$InstallDir = $(if ($env:EXCEEDS_INK_INSTALL_DIR) { $env:EXCEEDS_INK_INSTALL_DIR } else { (Join-Path $HOME ".exceeds-ink\bin") }),
    [switch]$BinaryOnly,
    [string]$CompatEndpoint = $env:EXCEEDS_INK_COMPAT_ENDPOINT,
    [string]$OtlpHttpEndpoint = $env:EXCEEDS_INK_OTLP_HTTP_ENDPOINT,
    [string]$OtlpGrpcEndpoint = $env:EXCEEDS_INK_OTLP_GRPC_ENDPOINT,
    [string]$ApiKey = $env:EXCEEDS_INK_API_KEY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DefaultOtlpHttp = "https://exceeds-ink.vercel.app/api/v1/otlp"
$DefaultCompat = "https://exceeds-ink.vercel.app/api/v1/ingest"

if (-not $IsWindows) {
    throw "install.ps1 is intended for Windows. Use install.sh on macOS or Linux."
}

function Resolve-Version {
    param([string]$RequestedVersion, [string]$Repository, [string]$AssetBase)

    if ($RequestedVersion -and $RequestedVersion -ne "latest") {
        return $RequestedVersion.TrimStart("v")
    }

    if ($AssetBase) {
        $latestUrl = "$($AssetBase.TrimEnd('/'))/LATEST"
        try {
            $response = Invoke-WebRequest -Uri $latestUrl -UseBasicParsing
            $latest = ($response.Content -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
            if ($latest) {
                return $latest.Trim().TrimStart("v")
            }
        } catch {
            # Fall back to GitHub release discovery.
        }
    }

    $release = Invoke-RestMethod -Headers @{ Accept = "application/vnd.github+json" } -Uri "https://api.github.com/repos/$Repository/releases/latest"
    if (-not $release.tag_name) {
        if ($AssetBase) {
            throw "Failed to resolve the latest release for $Repository. Set EXCEEDS_INK_VERSION or publish $($AssetBase.TrimEnd('/'))/LATEST."
        }
        throw "Failed to resolve the latest release for $Repository"
    }
    return $release.tag_name.TrimStart("v")
}

function Get-Target {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    switch ($arch) {
        "X64" { return "x86_64-pc-windows-msvc" }
        "Arm64" { return "x86_64-pc-windows-msvc" }
        default { throw "Unsupported Windows architecture: $arch" }
    }
}

function Test-EnvFlag {
    param([string]$Value)

    if (-not $Value) {
        return $false
    }

    switch ($Value.ToLowerInvariant()) {
        "1" { return $true }
        "true" { return $true }
        "yes" { return $true }
        "on" { return $true }
        default { return $false }
    }
}

function Resolve-EffectiveEndpoints {
    param(
        [string]$Otlp,
        [string]$Compat,
        [string]$DefaultOtlp,
        [string]$DefaultCompat
    )

    $hasOtlp = -not [string]::IsNullOrWhiteSpace($Otlp)
    $hasCompat = -not [string]::IsNullOrWhiteSpace($Compat)
    if ($hasOtlp -and $hasCompat) {
        return @{ Otlp = $Otlp.Trim(); Compat = $Compat.Trim() }
    }
    if (-not $hasOtlp -and -not $hasCompat) {
        return @{ Otlp = $DefaultOtlp; Compat = $DefaultCompat }
    }
    throw "Set both EXCEEDS_INK_OTLP_HTTP_ENDPOINT and EXCEEDS_INK_COMPAT_ENDPOINT to override the collector, or set neither to use the default Exceeds Vercel URLs."
}

$binaryOnlyRequested = $BinaryOnly.IsPresent -or (Test-EnvFlag -Value $env:EXCEEDS_INK_BINARY_ONLY)

$resolvedVersion = Resolve-Version -RequestedVersion $Version -Repository $Repo -AssetBase $DownloadBase
$target = Get-Target
$asset = "exceeds-ink_${resolvedVersion}_${target}.zip"
if ($DownloadBase) {
    $baseUrl = "$($DownloadBase.TrimEnd('/'))/v$resolvedVersion"
} else {
    $baseUrl = "https://github.com/$Repo/releases/download/v$resolvedVersion"
}
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("exceeds-ink-install-" + [System.Guid]::NewGuid().ToString("n"))

try {
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

    $archivePath = Join-Path $tmpDir $asset
    $checksumPath = "$archivePath.sha256"

    if ($DownloadBase) {
        Write-Host "Downloading $asset from $baseUrl..."
    } else {
        Write-Host "Downloading $asset from $Repo..."
    }
    Invoke-WebRequest -Uri "$baseUrl/$asset" -OutFile $archivePath
    Invoke-WebRequest -Uri "$baseUrl/$asset.sha256" -OutFile $checksumPath

    $expected = ((Get-Content -Path $checksumPath -Raw).Trim() -split "\s+")[0].ToLowerInvariant()
    $actual = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -ne $actual) {
        throw "Checksum verification failed for $asset"
    }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Expand-Archive -Path $archivePath -DestinationPath $tmpDir -Force

    $binaryPath = Join-Path $InstallDir "exceeds-ink.exe"
    Copy-Item -Force (Join-Path $tmpDir "exceeds-ink.exe") $binaryPath
    Write-Host "Installed exceeds-ink to $binaryPath"

    if (-not $binaryOnlyRequested) {
        $eff = Resolve-EffectiveEndpoints -Otlp $OtlpHttpEndpoint -Compat $CompatEndpoint -DefaultOtlp $DefaultOtlpHttp -DefaultCompat $DefaultCompat
        Write-Host "Running exceeds-ink setup (collector: Exceeds Vercel or your overrides)..."
        $setupArgs = @(
            "setup",
            "--otlp-http-endpoint", $eff.Otlp,
            "--compat-endpoint", $eff.Compat
        )
        if ($OtlpGrpcEndpoint) {
            $setupArgs += @("--otlp-grpc-endpoint", $OtlpGrpcEndpoint)
        }
        if ($ApiKey) {
            $setupArgs += @("--api-key", $ApiKey)
        }
        & $binaryPath @setupArgs

        Write-Host "Running exceeds-ink install --all..."
        $installArgs = @(
            "install", "--all",
            "--otlp-http-endpoint", $eff.Otlp,
            "--compat-endpoint", $eff.Compat
        )
        if ($OtlpGrpcEndpoint) {
            $installArgs += @("--otlp-grpc-endpoint", $OtlpGrpcEndpoint)
        }
        if ($ApiKey) {
            $installArgs += @("--api-key", $ApiKey)
        }
        & $binaryPath @installArgs
    }

    $pathEntries = @($env:Path -split ";" | Where-Object { $_ })
    if (-not ($pathEntries -contains $InstallDir)) {
        Write-Host ""
        Write-Host "Add exceeds-ink to your user PATH for future shells:"
        Write-Host ('  [Environment]::SetEnvironmentVariable("Path", "{0};" + [Environment]::GetEnvironmentVariable("Path", "User"), "User")' -f $InstallDir)
    }

    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Run 'exceeds-ink --version' in a new shell to confirm the install."
    if ($binaryOnlyRequested) {
        Write-Host "  2. Run 'exceeds-ink setup' / 'exceeds-ink install' as needed, or re-run this installer without -BinaryOnly."
        Write-Host "  3. Run 'exceeds-ink init' inside each repo you want to track."
    } else {
        Write-Host "  2. Run 'exceeds-ink init' inside each repo you want to track."
    }
    Write-Host "  On Windows, repo hooks require Git Bash (`bash`) on PATH."
    if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") {
        Write-Host "  Windows ARM currently installs the x64 binary."
    }
}
finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $tmpDir
}

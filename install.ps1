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
$ReleaseManifestName = "release-manifest.json"
$ReleaseManifestSignatureName = "release-manifest.rsa.sig"
$ProductionReleasePublicKeyPem = @'
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlnPeY/YmSu1zHZTUTKyD
v7xVo+7OfHHjHtmphaRtrzbX+lESyXhgEKGaqbPXiSlwq52OqAME7HN5aouMJ5yB
PYXU4lHZw9ufprvo8zsOZXFW/ajFI1kP8sbsU5ZjByM2iNikO7urYzETaKWaFAMh
thsK7ie1+mkCe+9s8ZNiFi2B/x0oRYIUylOY18/WAp8gv5ilJPCUlL2amjkuso5t
B0JVlFOIe6aka4agJVyss5MW0UqKRdv2q53vbw/537xYcJmB1fVAj6NhN8ALY9Dj
oinfdbjpS3lDeIRxXTjGcB96HacTUmZvPfcXyoSiqjVatz9pCTRG7zwsmLapl4lC
FQIDAQAB
-----END PUBLIC KEY-----
'@

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

function Get-ReleasePublicKeyPem {
    if (-not [string]::IsNullOrWhiteSpace($env:EXCEEDS_INK_RELEASE_PUBLIC_KEY_PEM)) {
        return $env:EXCEEDS_INK_RELEASE_PUBLIC_KEY_PEM
    }
    return $ProductionReleasePublicKeyPem
}

function Get-SignedManifestAssetHash {
    param(
        [string]$ManifestPath,
        [string]$SignaturePath,
        [string]$AssetName,
        [string]$ExpectedVersion
    )

    if (-not (Test-Path -LiteralPath $ManifestPath) -or -not (Test-Path -LiteralPath $SignaturePath)) {
        throw "release is not trusted: signed release manifest or signature is missing. For local release testing, publish release-manifest.json and release-manifest.rsa.sig and set EXCEEDS_INK_RELEASE_PUBLIC_KEY_PEM to the PEM public key that signed it."
    }

    $manifestBytes = [System.IO.File]::ReadAllBytes($ManifestPath)
    $signatureText = ([System.IO.File]::ReadAllText($SignaturePath) -replace "\s", "")
    try {
        $signatureBytes = [Convert]::FromBase64String($signatureText)
    } catch {
        throw "release is not trusted: release manifest signature is not valid base64. For local release testing, set EXCEEDS_INK_RELEASE_PUBLIC_KEY_PEM to the PEM public key that signed the manifest."
    }

    $rsa = [System.Security.Cryptography.RSA]::Create()
    try {
        $pem = Get-ReleasePublicKeyPem
        $rsa.ImportFromPem($pem.AsSpan())
        $verified = $rsa.VerifyData(
            $manifestBytes,
            $signatureBytes,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    } finally {
        $rsa.Dispose()
    }
    if (-not $verified) {
        throw "release is not trusted: RSA-SHA256 release manifest signature verification failed. For local release testing, set EXCEEDS_INK_RELEASE_PUBLIC_KEY_PEM to the PEM public key that signed the manifest."
    }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ($manifest.version -ne $ExpectedVersion) {
        throw "release is not trusted: manifest version mismatch. Expected $ExpectedVersion but found $($manifest.version)."
    }
    $asset = @($manifest.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1)
    if (-not $asset) {
        throw "release is not trusted: manifest missing asset $AssetName."
    }
    $hash = [string]$asset.sha256
    if ($hash -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "release is not trusted: manifest asset sha256 is invalid."
    }
    return $hash.ToLowerInvariant()
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
    $manifestPath = Join-Path $tmpDir $ReleaseManifestName
    $signaturePath = Join-Path $tmpDir $ReleaseManifestSignatureName

    if ($DownloadBase) {
        Write-Host "Downloading $asset from $baseUrl..."
    } else {
        Write-Host "Downloading $asset from $Repo..."
    }
    Invoke-WebRequest -Uri "$baseUrl/$asset" -OutFile $archivePath
    Invoke-WebRequest -Uri "$baseUrl/$ReleaseManifestName" -OutFile $manifestPath
    Invoke-WebRequest -Uri "$baseUrl/$ReleaseManifestSignatureName" -OutFile $signaturePath

    $expected = Get-SignedManifestAssetHash -ManifestPath $manifestPath -SignaturePath $signaturePath -AssetName $asset -ExpectedVersion $resolvedVersion
    $actual = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -ne $actual) {
        throw "SHA256 verification failed for $asset"
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

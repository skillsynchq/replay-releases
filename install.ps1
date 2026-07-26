# Installs skl — the Skillsync CLI — on Windows.
#   irm https://install.skillsync.com/install.ps1 | iex
# Options (set as env vars before running):
#   $env:VERSION         pin a version, e.g. "0.18.1"
#   $env:SKL_INSTALL_DIR custom install directory

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Windows PowerShell 5.1 defaults to TLS 1.0; GitHub requires 1.2+.
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

$Repo = "skillsynchq/skl-releases"
# ARM64 Windows runs this via x64 emulation; only x86_64 is built.
$Target = "x86_64-pc-windows-msvc"
$InstallDir = if ($env:SKL_INSTALL_DIR) { $env:SKL_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "skl\bin" }

# An existing install means this is an upgrade, not a fresh setup,
# so skip the interactive init at the end.
$alreadyInstalled = [bool](Get-Command skl -ErrorAction SilentlyContinue)

if ($env:VERSION) {
    $tag = "v$env:VERSION"
} else {
    $tag = (Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest").tag_name
}

$archiveDir = "skl-cli-$tag-$Target"
$archive = "$archiveDir.zip"
$base = "https://github.com/$Repo/releases/download/$tag"

$tmp = Join-Path ([IO.Path]::GetTempPath()) "skl-install-$([IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    Invoke-WebRequest "$base/$archive" -OutFile (Join-Path $tmp $archive)
    Invoke-WebRequest "$base/$archive.sha256" -OutFile (Join-Path $tmp "$archive.sha256")

    # Checksum files vary: some hold a bare hash, some "hash  filename".
    # The first field is always the hash.
    $expected = ((Get-Content (Join-Path $tmp "$archive.sha256") -Raw).Trim() -split "\s+")[0].ToLower()
    $actual = (Get-FileHash (Join-Path $tmp $archive) -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) {
        throw "Checksum mismatch for ${archive}: expected $expected, got $actual"
    }

    Write-Host "Installing skl ($tag) for $Target"
    Write-Host "Script source: https://github.com/$Repo/blob/main/install.ps1"
    Write-Host ""

    Expand-Archive (Join-Path $tmp $archive) -DestinationPath $tmp -Force

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Move-Item (Join-Path $tmp "$archiveDir\skl.exe") (Join-Path $InstallDir "skl.exe") -Force

    Write-Host "Installed skl to $(Join-Path $InstallDir "skl.exe")"

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (($userPath -split ";") -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$InstallDir", "User")
        Write-Host "Added $InstallDir to your PATH (open a new terminal to pick it up)"
    }
    if (($env:Path -split ";") -notcontains $InstallDir) {
        $env:Path = "$env:Path;$InstallDir"
    }

    if (-not $alreadyInstalled) {
        Write-Host ""
        Write-Host "Running 'skl init'..."
        & (Join-Path $InstallDir "skl.exe") init
    }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

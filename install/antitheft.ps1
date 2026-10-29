# antitheft installer for Windows:   iwr https://antitheft.pro/antitheft.ps1 -useb | iex
#
# What it does, in order:
#   1. reads the current release: the newest one on GitHub (github.com/kinnector/antitheft/releases, its
#      manifest.json), or https://dl.antitheft.pro/antitheft/latest.json when GitHub cannot be reached:
#        {"version": "1.2.3", "files": {"windows-x86_64-msi": {"url": "...", "sha256": "..."}, ...}}
#      file keys are <os>-<arch>-<package>: os windows, arch x86_64 | aarch64, package msi (or exe)
#   2. downloads this computer's installer from that GitHub release, else from https://dl.antitheft.pro/antitheft/<version>/
#   3. checks its SHA-256 against the release description (a copy that does not match is never installed)
#   4. runs it (Windows asks for permission, as for any installer)
# Nothing is installed when any step fails. No release published yet: it says STAGING MODE and stops.
#
# Environment: ANTITHEFT_DL (another download root holding latest.json and <version>/, used INSTEAD of GitHub
# and the mirror, for testing a release before it is public),
# ANTITHEFT_DRY_RUN=1 (download and verify, print the install command, install nothing).
#
# Everything is one script block, run on its last line: a download cut short runs nothing. It never calls `exit`,
# which would close the PowerShell window it was pasted into.

& {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is many times slower while it draws progress
  # Windows PowerShell 5.1 may not offer TLS 1.2 by default
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

  function Fail([string]$text) { Write-Host "antitheft: $text" -ForegroundColor Red }

  # Where releases are: GitHub first, our own mirror when GitHub is blocked or down. ANTITHEFT_DL replaces both.
  $gh = 'https://github.com/kinnector/antitheft/releases'
  $mirror = 'https://dl.antitheft.pro/antitheft'
  if ($env:ANTITHEFT_DL) { $gh = $null; $mirror = $env:ANTITHEFT_DL.TrimEnd('/') }
  $dry = $env:ANTITHEFT_DRY_RUN -eq '1'

  $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'x86_64' }
    'ARM64' { 'aarch64' }
    default { $null }
  }
  if ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') { $arch = 'x86_64' }   # 32-bit PowerShell on 64-bit Windows
  if (-not $arch) { Fail "antitheft has no package for $($env:PROCESSOR_ARCHITECTURE) processors yet."; return }

  # 1. the release: GitHub's newest, else the mirror's latest.json. No release is: nothing on GitHub and no
  #    latest.json (404, or 403 from the bucket), or no download host at all yet.
  $resp = $null
  if ($gh) { try { $resp = Invoke-WebRequest -Uri "$gh/latest/download/manifest.json" -UseBasicParsing } catch { $resp = $null } }
  if (-not $resp) { try {
    $resp = Invoke-WebRequest -Uri "$mirror/latest.json" -UseBasicParsing
  } catch {
    $status = $null
    if ($_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch {} }
    $noHost = $_.Exception.Message -match 'could not be resolved|No such host|name or service not known'
    if ($status -eq 404 -or $status -eq 403 -or $noHost) {
      Write-Host 'STAGING MODE'
      Write-Host 'antitheft is not released yet: there is nothing to install. Check https://antitheft.pro for the launch.'
    } else {
      Fail "could not reach the antitheft download server. Check your connection and try again. ($($_.Exception.Message))"
    }
    return
  } }
  try { $latest = $resp.Content | ConvertFrom-Json } catch { Fail 'the release description is unreadable.'; return }
  $version = [string]$latest.version
  if ($version -notmatch '^[A-Za-z0-9._+-]+$') { Fail 'the release description is unreadable (no valid version).'; return }

  # 2. this computer's installer
  if (-not $latest.files) { Fail 'the release description lists no files.'; return }
  $key = $null; $entry = $null
  foreach ($kind in 'zip', 'msi', 'exe') {
    $k = "windows-$arch-$kind"
    if ($latest.files.PSObject.Properties.Name -contains $k) { $key = $k; $entry = $latest.files.$k; break }
  }
  if (-not $entry) { Fail "antitheft $version has no installer for Windows on $arch yet."; return }
  $sha = ([string]$entry.sha256).ToLowerInvariant()
  if ($sha -notmatch '^[0-9a-f]{64}$') { Fail "the release description has no valid SHA-256 for $key."; return }
  # Only the file NAME is taken from the description; where it is fetched from is ours (GitHub's release, the mirror).
  $file = ([string]$entry.url).Split('/')[-1]
  if ($file -notmatch '^[A-Za-z0-9._+-]+$') { Fail "the release names an unexpected file: $file"; return }

  # 3. download and verify
  $dir = Join-Path ([IO.Path]::GetTempPath()) ('antitheft-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $dir | Out-Null
  try {
    $path = Join-Path $dir $file
    Write-Host "Downloading antitheft $version ($file)..."
    # GitHub first, then the mirror; only a copy that matches the SHA-256 counts
    $places = @()
    if ($gh) { $places += "$gh/download/v$version" }
    $places += "$mirror/$version"
    $ok = $false
    foreach ($from in $places) {
      Remove-Item -Force -Path $path -ErrorAction SilentlyContinue
      try { Invoke-WebRequest -Uri "$from/$file" -OutFile $path -UseBasicParsing } catch { Write-Host "Could not download it from $from, trying the next place..."; continue }
      $got = (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLowerInvariant()
      if ($got -eq $sha) { $ok = $true; break }
      Write-Host "The copy at $from does not match its SHA-256 (expected $sha, got $got), trying the next place..."
    }
    if (-not $ok) { Fail 'the download failed or did not match its SHA-256. Nothing was installed. Try again in a minute.'; return }
    Write-Host "SHA-256 verified: $sha"
    # said before anything is installed: the service comes before the app's own gate
    Write-Host 'By installing antitheft you agree to its Terms: https://antitheft.pro/terms/'
    Write-Host 'It runs with full system rights and can stop programs. To remove it: https://antitheft.pro/uninstall/'

    # 4. install. A zip (the service-wrapper build, no MSI) unpacks and runs its own install.ps1
    #    elevated; an msi goes through msiexec; anything else is run as-is.
    if ($file.EndsWith('.zip')) {
      $unpack = Join-Path $dir 'unpacked'
      try { Expand-Archive -Path $path -DestinationPath $unpack -Force } catch { Fail 'the download could not be unpacked.'; return }
      $installer = Get-ChildItem -Path $unpack -Filter 'install.ps1' -Recurse | Select-Object -First 1
      if (-not $installer) { Fail 'the download has no install.ps1.'; return }
      $exe = 'powershell.exe'; $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($installer.FullName)`"")
    }
    elseif ($file.EndsWith('.msi')) { $exe = 'msiexec.exe'; $argv = @('/i', "`"$path`"", '/passive', '/norestart') }
    else { $exe = $path; $argv = @() }
    if ($dry) { Write-Host "dry run, would run: $exe $($argv -join ' ')"; return }
    Write-Host 'Installing (Windows asks for permission)...'
    try {
      if ($argv.Count) { $p = Start-Process -FilePath $exe -ArgumentList $argv -Verb RunAs -Wait -PassThru }
      else { $p = Start-Process -FilePath $exe -Verb RunAs -Wait -PassThru }
    } catch { Fail 'Windows did not get permission to install. Nothing was installed.'; return }
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { Fail "the installer stopped with code $($p.ExitCode). Nothing more was done."; return }
    Write-Host ''
    Write-Host "antitheft $version is installed. Open the antitheft app to finish setting it up."
  } finally {
    Remove-Item -Recurse -Force -Path $dir -ErrorAction SilentlyContinue
  }
}

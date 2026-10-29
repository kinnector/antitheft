# Check an antitheft release by hand on Windows: your downloads against the release's signed manifest.
#
#   powershell -ExecutionPolicy Bypass -File scripts\verify-release.ps1 manifest.token antitheft-0.1.1-windows-x86_64-setup.exe
#
# manifest.token is attached to every release: its files' SHA-256 and size, signed with the antitheft release key.
# Windows has no built-in Ed25519, so the signature is checked with OpenSSL 3 when one is on PATH (Git for Windows
# ships one); without it only the files are compared, and the script says so.
param(
  [Parameter(Mandatory = $true, Position = 0)] [string] $Token,
  [Parameter(ValueFromRemainingArguments = $true)] [string[]] $Files = @()
)
$ErrorActionPreference = 'Stop'

# The antitheft release public key (Ed25519). base64url: u8amLvQRI4xRHnpuEwDpgUsdl2vS-URYNt6SoR_765c
$ReleaseKeyPem = @"
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAu8amLvQRI4xRHnpuEwDpgUsdl2vS+URYNt6SoR/765c=
-----END PUBLIC KEY-----
"@

function FromBase64Url([string] $s) {
  $s = $s.Replace('-', '+').Replace('_', '/')
  while ($s.Length % 4) { $s += '=' }
  [Convert]::FromBase64String($s)
}

$text = (Get-Content -Raw -Path $Token).Trim()
$dot = $text.IndexOf('.')
if ($dot -lt 1) { Write-Host 'not a signed manifest' -ForegroundColor Red; exit 1 }
$payload = FromBase64Url $text.Substring(0, $dot)
$signature = FromBase64Url $text.Substring($dot + 1)
$manifest = [Text.Encoding]::UTF8.GetString($payload) | ConvertFrom-Json
$status = 0

$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl -and (Test-Path "$env:ProgramFiles\Git\usr\bin\openssl.exe")) { $openssl = Get-Item "$env:ProgramFiles\Git\usr\bin\openssl.exe" }
if ($openssl) {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ('antitheft-verify-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $dir | Out-Null
  try {
    $domain = [Text.Encoding]::ASCII.GetBytes("antitheft-release-v1`0")
    [IO.File]::WriteAllBytes((Join-Path $dir 'signed.bin'), [byte[]]($domain + $payload))
    [IO.File]::WriteAllBytes((Join-Path $dir 'sig.bin'), $signature)
    [IO.File]::WriteAllText((Join-Path $dir 'key.pem'), $ReleaseKeyPem)
    & $openssl.Source pkeyutl -verify -pubin -inkey (Join-Path $dir 'key.pem') -rawin -in (Join-Path $dir 'signed.bin') -sigfile (Join-Path $dir 'sig.bin') *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host 'BAD SIGNATURE: this manifest was not signed with the antitheft release key' -ForegroundColor Red; exit 1 }
    Write-Host "signature OK: antitheft $($manifest.version), signed with the antitheft release key"
  } finally {
    Remove-Item -Recurse -Force -Path $dir -ErrorAction SilentlyContinue
  }
} else {
  Write-Host 'signature NOT checked: no OpenSSL 3 found (install Git for Windows, or use verify-release.sh in WSL)' -ForegroundColor Yellow
  Write-Host "manifest says: antitheft $($manifest.version)"
}

foreach ($f in $Files) {
  $name = Split-Path -Leaf $f
  $entry = $manifest.files.PSObject.Properties.Value | Where-Object { ([string]$_.url).Split('/')[-1] -eq $name } | Select-Object -First 1
  if (-not $entry) { Write-Host "NOT IN RELEASE: $name" -ForegroundColor Red; $status = 1; continue }
  $got = (Get-FileHash -Algorithm SHA256 -Path $f).Hash.ToLowerInvariant()
  if ($got -eq ([string]$entry.sha256).ToLowerInvariant()) { Write-Host "OK: $name ($got)" }
  else { Write-Host "MISMATCH: $name is $got, the release says $($entry.sha256)" -ForegroundColor Red; $status = 1 }
}
exit $status

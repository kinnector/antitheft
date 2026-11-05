# Check an installed copy of antitheft on Windows, file by file, against the release's signed file list.
#
#   powershell -ExecutionPolicy Bypass -File scripts\verify-install.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\verify-install.ps1 -Token antitheft-0.1.8-windows-x86_64-files.token
#
# Every release carries a list of every file in it with its SHA-256 and size, signed with the antitheft release
# key: inside the install folder as files.token, and attached to the release as
# antitheft-<version>-windows-x86_64-files.token. Use the one from the release page if you do not want to trust
# the copy on this computer. This script does not run any antitheft program.
#
# Windows has no built-in Ed25519, so the signature is checked with OpenSSL 3 (Git for Windows ships one).
# Without OpenSSL the files are still compared, and the script says the list itself was not checked.
param(
  [string] $Folder = (Join-Path $env:ProgramFiles 'Antitheft'),
  [string] $Token = ''
)
$ErrorActionPreference = 'Stop'

# The antitheft release public key (Ed25519). base64url: u8amLvQRI4xRHnpuEwDpgUsdl2vS-URYNt6SoR_765c
$ReleaseKeyPem = @"
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAu8amLvQRI4xRHnpuEwDpgUsdl2vS+URYNt6SoR/765c=
-----END PUBLIC KEY-----
"@
# The setup writes the install folder's own antitheft-cli.exe path into these two files of the Claude Code plugin;
# the release ships them with this placeholder, so it is put back before they are hashed.
$PluginToken = '${CLAUDE_PLUGIN_ROOT}/../../../../antitheft-cli'
$StampedFiles = @('integrations/claude-code/plugins/antitheft/.mcp.json', 'integrations/claude-code/plugins/antitheft/hooks/hooks.json')
# Expected in an install folder and in no list: the setup's uninstaller, and the list itself.
$Expected = @('files.json', 'files.token', 'uninstall-antitheft.exe', 'uninstall.ps1')

function FromBase64Url([string] $s) {
  $s = $s.Replace('-', '+').Replace('_', '/')
  while ($s.Length % 4) { $s += '=' }
  [Convert]::FromBase64String($s)
}
function Sha256Hex([byte[]] $bytes) {
  $h = [Security.Cryptography.SHA256]::Create()
  try { ([BitConverter]::ToString($h.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() } finally { $h.Dispose() }
}

if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { Write-Host "no install folder at $Folder" -ForegroundColor Red; exit 1 }
$Folder = (Resolve-Path -LiteralPath $Folder).Path
if (-not $Token) { $Token = Join-Path $Folder 'files.token' }
if (-not (Test-Path -LiteralPath $Token)) { Write-Host "no signed file list at $Token (antitheft before 0.1.8 did not install one)" -ForegroundColor Red; exit 1 }

$text = (Get-Content -Raw -LiteralPath $Token).Trim()
$dot = $text.IndexOf('.')
if ($dot -lt 1) { Write-Host 'not a signed file list' -ForegroundColor Red; exit 1 }
$payload = FromBase64Url $text.Substring(0, $dot)
$signature = FromBase64Url $text.Substring($dot + 1)
$list = [Text.Encoding]::UTF8.GetString($payload) | ConvertFrom-Json
$status = 0

$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl -and (Test-Path "$env:ProgramFiles\Git\usr\bin\openssl.exe")) { $openssl = Get-Item "$env:ProgramFiles\Git\usr\bin\openssl.exe" }
if ($openssl) {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ('antitheft-verify-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $dir | Out-Null
  try {
    $domain = [Text.Encoding]::ASCII.GetBytes("antitheft-files-v1`0")
    [IO.File]::WriteAllBytes((Join-Path $dir 'signed.bin'), [byte[]]($domain + $payload))
    [IO.File]::WriteAllBytes((Join-Path $dir 'sig.bin'), $signature)
    [IO.File]::WriteAllText((Join-Path $dir 'key.pem'), $ReleaseKeyPem)
    $src = if ($openssl.Source) { $openssl.Source } else { $openssl.FullName }
    & $src pkeyutl -verify -pubin -inkey (Join-Path $dir 'key.pem') -rawin -in (Join-Path $dir 'signed.bin') -sigfile (Join-Path $dir 'sig.bin') *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host 'BAD SIGNATURE: this file list was not signed with the antitheft release key' -ForegroundColor Red; exit 1 }
    Write-Host "signature OK: antitheft $($list.version) ($($list.platform)), signed with the antitheft release key"
  } finally {
    Remove-Item -Recurse -Force -Path $dir -ErrorAction SilentlyContinue
  }
} else {
  Write-Host 'signature NOT checked: no OpenSSL 3 found (install Git for Windows)' -ForegroundColor Yellow
  Write-Host "the list says: antitheft $($list.version) ($($list.platform))"
}

$cli = [IO.Path]::Combine($Folder, 'antitheft-cli.exe')
$cliJson = ($cli | ConvertTo-Json).Trim('"')
$listed = @{}
$checked = 0
foreach ($p in $list.files.PSObject.Properties) {
  $rel = $p.Name
  $want = $p.Value
  $listed[$rel.ToLowerInvariant()] = $true
  $path = Join-Path $Folder ($rel.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    if ($want.optional) { continue }
    Write-Host "MISSING: $rel" -ForegroundColor Red; $status = 1; continue
  }
  $bytes = [IO.File]::ReadAllBytes($path)
  if ($StampedFiles -contains $rel) {
    $bytes = (New-Object Text.UTF8Encoding $false).GetBytes([Text.Encoding]::UTF8.GetString($bytes).Replace($cliJson, $PluginToken))
  }
  $checked++
  if ((Sha256Hex $bytes) -ne ([string]$want.sha256).ToLowerInvariant() -or $bytes.Length -ne [int64]$want.size) {
    Write-Host "CHANGED: $rel" -ForegroundColor Red; $status = 1
  }
}
foreach ($f in Get-ChildItem -LiteralPath $Folder -Recurse -File -Force) {
  $rel = $f.FullName.Substring($Folder.Length).TrimStart('\').Replace('\', '/')
  $top = -not $rel.Contains('/')
  if ($listed.ContainsKey($rel.ToLowerInvariant())) { continue }
  if ($top -and (($Expected -contains $rel.ToLowerInvariant()) -or $rel.Contains('.old-'))) { continue }
  Write-Host "ADDED: $rel" -ForegroundColor Red; $status = 1
}
if ($status -eq 0) { Write-Host "OK: all $checked installed files are exactly as released" }
else { Write-Host 'NOT AS RELEASED: see the lines above' -ForegroundColor Red }
exit $status

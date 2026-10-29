#!/usr/bin/env bash
# Check an antitheft release by hand: its signature, and that your downloads are the files it names.
#
#   scripts/verify-release.sh manifest.token [downloaded file ...]
#
# manifest.token is attached to every release. It is the release's manifest (version, and the SHA-256 and size
# of each file) signed with the antitheft release key, the same key every installed copy checks before it
# installs an update. Needs bash, openssl 3 and base64.
set -euo pipefail

# The antitheft release public key (Ed25519). The same key, base64url: u8amLvQRI4xRHnpuEwDpgUsdl2vS-URYNt6SoR_765c
RELEASE_KEY_PEM='-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAu8amLvQRI4xRHnpuEwDpgUsdl2vS+URYNt6SoR/765c=
-----END PUBLIC KEY-----'
DOMAIN='antitheft-release-v1'

[[ $# -ge 1 && -f $1 ]] || { echo "usage: $0 manifest.token [downloaded file ...]" >&2; exit 2; }
token=$(tr -d ' \r\n' <"$1"); shift
[[ $token == *.* ]] || { echo "not a signed manifest" >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
unb64url() { local s; s=$(printf '%s' "$1" | tr '_-' '/+'); while (( ${#s} % 4 )); do s+='='; done; printf '%s' "$s" | base64 -d; }
printf '%s' "$RELEASE_KEY_PEM" >"$work/key.pem"
unb64url "${token%%.*}" >"$work/payload.json"
unb64url "${token#*.}" >"$work/sig.bin"
{ printf '%s\0' "$DOMAIN"; cat "$work/payload.json"; } >"$work/signed.bin"

if ! openssl pkeyutl -verify -pubin -inkey "$work/key.pem" -rawin -in "$work/signed.bin" -sigfile "$work/sig.bin" >/dev/null 2>&1; then
    echo "BAD SIGNATURE: this manifest was not signed with the antitheft release key" >&2
    exit 1
fi
version=$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' "$work/payload.json")
echo "signature OK: antitheft $version, signed with the antitheft release key"

status=0
for f in "$@"; do
    name=${f##*/}
    # the manifest's entry for this file: {"mirrors":[...],"sha256":"...","size":N,"url":".../<name>"}
    want=$(grep -o "{[^{}]*/${name//./\\.}\"[^{}]*}" "$work/payload.json" | sed -n 's/.*"sha256":"\([0-9a-fA-F]\{64\}\)".*/\1/p' | head -1)
    if [[ -z $want ]]; then echo "NOT IN RELEASE: $name"; status=1; continue; fi
    got=$( (command -v sha256sum >/dev/null && sha256sum "$f" || shasum -a 256 "$f") | cut -d' ' -f1)
    if [[ ${got,,} == "${want,,}" ]]; then echo "OK: $name ($got)"; else echo "MISMATCH: $name is $got, the release says $want"; status=1; fi
done
exit $status

#!/bin/bash
# Repo-specific secret guard.
#
# This exists because of what nearly happened: SolisSettings.register(defaults:)
# once shipped a live SolisCloud session — cookie, authorization header,
# device-id, station ID — and SolisAPI carried the vendor's HMAC signing secret.
# A clone was a working login to one account.
#
# Off-the-shelf scanners would not have caught either. A 32-char hex string and a
# session cookie match no known provider pattern, so the patterns below are
# specific to this project rather than generic.
#
# Exits non-zero on the first hit. Run against tracked files only, so local
# scratch files and the 500 MB .build directory are ignored.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
report() { printf '  %-38s %s\n' "$1" "$2"; }

check() {
    local label="$1" pattern="$2"
    local hits
    hits=$(git ls-files -z | xargs -0 grep -nIE "$pattern" 2>/dev/null \
           | grep -v '^scripts/check-secrets.sh:' || true)
    if [ -n "$hits" ]; then
        report "$label" "FOUND"
        echo "$hits" | sed 's/^/      /' | head -5
        fail=1
    else
        report "$label" "clean"
    fi
}

echo "Scanning tracked files for credentials and account data:"

# The vendor's request-signing secret: 32 hex chars assigned to something
# secret-shaped. Deliberately not the literal value — that would put it back.
check "signing secret (32-char hex)"     '(secret|Secret)[[:space:]]*=[[:space:]]*"[0-9a-f]{32}"'
check "SolisCloud session cookie"        'token=token_[0-9a-f-]{8}|acw_tc=[0-9a-f]{16}|_ga=GA1\.'
check "captured authorization header"    'WEB [0-9]{4}:[A-Za-z0-9+/]{20,}='
check "station / device identifiers"     '[^0-9.][0-9]{19}[^0-9]'
check "hardcoded coordinates"            '[0-9]{2}\.[0-9]{4},?[[:space:]]*/?[[:space:]]*6[0-9]\.[0-9]{4}'
# Anything-but-a-quote between the name and the literal: the first version
# required `name = "…"` and missed `name: String = "…"`, which the negative
# test caught. A check that can never fire is worse than no check.
check "content-md5 style digest literal" '(contentMD5|content-md5)[^"]{0,24}"[A-Za-z0-9+/]{20,}=='
check "personal address fragments"       'House No|Nazimabad'

echo
if [ "$fail" -ne 0 ]; then
    echo "FAILED — a credential or account identifier is present in tracked files."
    echo "Nothing account-specific belongs in this repository; see CLAUDE.md."
    exit 1
fi
echo "PASSED — nothing account-specific in tracked files."

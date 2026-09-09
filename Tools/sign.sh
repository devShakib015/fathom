#!/bin/bash
#
# Ad-hoc signs a built Fathom.app for distribution.
#
# Exists because the obvious command is wrong in a way nothing reports:
#
#     codesign --force --deep --sign - Fathom.app     # ← strips every entitlement
#
# `--force --sign` replaces the signature, and a replaced signature carries no
# entitlements unless you hand them back. `--deep` then does the same thing to
# the embedded widget extension. The result installs, launches, and looks
# completely normal — but the extension is no longer sandboxed, and macOS
# silently refuses to register an unsandboxed widget extension. Green build,
# working app, no widgets, no error anywhere.
#
# So: sign inside out, name the entitlements explicitly, and verify afterwards
# rather than trusting the exit code.
set -euo pipefail

APP="${1:?usage: sign.sh /path/to/Fathom.app}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="$APP/Contents/PlugIns/FathomWidget.appex"

[ -d "$APP" ] || { echo "No app at $APP" >&2; exit 1; }
[ -d "$EXT" ] || { echo "No extension inside $APP — the widget will never appear." >&2; exit 1; }

# Inside out. Signing the host first would invalidate its own seal the moment
# the nested binary changed.
codesign --force --sign - --timestamp=none \
  --entitlements "$ROOT/Widget/FathomWidget.entitlements" "$EXT"

codesign --force --sign - --timestamp=none \
  --entitlements "$ROOT/App/Fathom.entitlements" "$APP"

# Verification is the point of the script. A signature that dropped the sandbox
# is indistinguishable from a good one until a widget quietly fails to appear.
fail=0
check() {
  local target="$1" label="$2" key="$3"
  if codesign -d --entitlements - "$target" 2>&1 | tr -d '\0' | grep -q "$key"; then
    echo "  ok   $label — $key"
  else
    echo "  FAIL $label — $key is missing" >&2
    fail=1
  fi
}

echo "Signed. Checking what actually survived:"
check "$EXT" "extension" "com.apple.security.app-sandbox"
check "$EXT" "extension" "/Users/Shared/Fathom/"
check "$APP" "app"       "com.apple.security.app-sandbox"
check "$APP" "app"       "/Users/Shared/Fathom/"
check "$APP" "app"       "com.apple.security.personal-information.location"

codesign --verify --deep --strict "$APP" && echo "  ok   seal verifies"

exit $fail

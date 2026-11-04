#!/bin/bash
# Adapted from macos-spm-app-packaging/assets/templates/sign-and-notarize.sh.
# Signs the already-built native CEF bundle; never fetches/replaces Chromium.
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-help}"
APP="${2:-}"
IDENTITY="${BROWSER_SIGN_IDENTITY:-}"
TEAM="${BROWSER_SIGN_TEAM:-LWSP9A5UDA}"
ENTITLEMENTS="$NATIVE_ROOT/Signing"

case "$MODE" in
  sign)
    SOURCE="${2:-$NATIVE_ROOT/build/Arc Reborn.app}"
    APP="${3:-$NATIVE_ROOT/build/distribution/Arc Reborn.app}"
    [[ -d "$SOURCE/Contents/Frameworks" ]] || { echo 'Bundle source introuvable.' >&2; exit 1; }
    [[ ! -e "$APP" ]] || { echo 'La destination existe déjà ; choisir un nouveau dossier.' >&2; exit 1; }
    if [[ -z "$IDENTITY" ]]; then
      IDENTITY="$(security find-identity -v -p codesigning | /usr/bin/python3 -c 'import re,sys; team=sys.argv[1]; ids=re.findall(r"^\s*\d+\) ([A-F0-9]{40}) \"Developer ID Application: [^\n]+\("+re.escape(team)+r"\)\"",sys.stdin.read(),re.M); print(ids[0] if len(ids)==1 else "")' "$TEAM")"
    fi
    [[ -n "$IDENTITY" ]] || { echo 'Définir BROWSER_SIGN_IDENTITY avec un certificat Developer ID Application.' >&2; exit 1; }
    # Validate the signer before copying hundreds of MB or changing any signature.
    security find-identity -v -p codesigning | /usr/bin/python3 -c 'import re,sys; value=sys.stdin.read(); identity,team=sys.argv[1:]; rows=re.findall(r"^\s*\d+\) ([A-F0-9]{40}) \"([^\n]+)\"",value,re.M); assert any(identity in (sha,name) and name.startswith("Developer ID Application:") and name.endswith("("+team+")") for sha,name in rows), "Identité Developer ID invalide"' "$IDENTITY" "$TEAM"
    mkdir -p "$(dirname "$APP")"
    /bin/cp -cR "$SOURCE" "$APP"
    # Debug symbols belong beside the deliverable, not under Contents/MacOS.
    SYMBOLS="$(mktemp -d "$(dirname "$APP")/symbols.XXXXXX")"
    while IFS= read -r -d '' symbol; do mv "$symbol" "$SYMBOLS/"; done < <(find "$APP/Contents/MacOS" -maxdepth 1 -name '*.dSYM' -type d -print0)
    FRAMEWORK="$APP/Contents/Frameworks/Chromium Embedded Framework.framework"
    for suffix in '' ' (GPU)' ' (Renderer)' ' (Plugin)' ' (Alerts)'; do
      [[ -x "$APP/Contents/Frameworks/Arc Reborn Helper$suffix.app/Contents/MacOS/Arc Reborn Helper$suffix" ]] || { echo "Helper manquant : $suffix" >&2; exit 1; }
    done
    # Sign each physical nested image once, from the inside out. Never --deep-sign.
    while IFS= read -r -d '' library; do
      codesign --force --timestamp --sign "$IDENTITY" "$library"
    done < <(find "$FRAMEWORK" -type f -name '*.dylib' -print0)
    codesign --force --timestamp --sign "$IDENTITY" "$FRAMEWORK"
    for suffix in '' ' (GPU)' ' (Renderer)' ' (Plugin)' ' (Alerts)'; do
      POLICY="$ENTITLEMENTS/helper.entitlements"
      case "$suffix" in ' (GPU)'|' (Renderer)') POLICY="$ENTITLEMENTS/jit.entitlements";; esac
      codesign --force --timestamp --options runtime --sign "$IDENTITY" --entitlements "$POLICY" "$APP/Contents/Frameworks/Arc Reborn Helper$suffix.app"
    done
    "$NATIVE_ROOT/scripts/sign-sparkle.sh" "$APP/Contents/Frameworks/Sparkle.framework" "$IDENTITY"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" --entitlements "$ENTITLEMENTS/app.entitlements" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    codesign --display --verbose=4 "$APP"
    echo "Signé : $APP"
    ;;
  submit)
    [[ -d "$APP" ]] || { echo 'Indiquer le bundle signé.' >&2; exit 1; }
    codesign --verify --deep --strict "$APP"
    SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
    [[ "$SIGNATURE" == *'Authority=Developer ID Application:'* && "$SIGNATURE" == *'(runtime)'* ]] || { echo 'Developer ID et Hardened Runtime requis.' >&2; exit 1; }
    AUTH=()
    if [[ -n "${BROWSER_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
      AUTH=(--keychain-profile "$BROWSER_NOTARY_KEYCHAIN_PROFILE")
    else
      : "${BROWSER_NOTARY_KEY:?Chemin privé de la clé .p8 requis}"
      : "${BROWSER_NOTARY_KEY_ID:?Identifiant de clé requis}"
      AUTH=(--key "$BROWSER_NOTARY_KEY" --key-id "$BROWSER_NOTARY_KEY_ID")
      if [[ -n "${BROWSER_NOTARY_ISSUER:-}" ]]; then AUTH+=(--issuer "$BROWSER_NOTARY_ISSUER"); fi
    fi
    PACKAGE="${APP%.app}-notarization.zip"
    [[ ! -e "$PACKAGE" ]] || { echo 'Archive de soumission déjà présente.' >&2; exit 1; }
    ditto -c -k --keepParent "$APP" "$PACKAGE"
    # No blocking --wait: keep the submission ID and poll with notarytool info.
    xcrun notarytool submit "$PACKAGE" "${AUTH[@]}" --output-format json > "${APP%.app}-submission.json"
    cat "${APP%.app}-submission.json"
    ;;
  staple)
    [[ -d "$APP" ]] || { echo 'Indiquer le bundle accepté par Apple.' >&2; exit 1; }
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
    PACKAGE="${APP%.app}.zip"
    [[ ! -e "$PACKAGE" ]] || { echo 'Archive finale déjà présente.' >&2; exit 1; }
    ditto -c -k --keepParent "$APP" "$PACKAGE"
    shasum -a 256 "$PACKAGE" > "$PACKAGE.sha256"
    echo "Distribution notarifiée : $PACKAGE"
    ;;
  *)
    echo "Usage: $0 sign [source.app] [destination.app]"
    echo "       $0 submit destination.app"
    echo "       $0 staple destination.app"
    [[ "$MODE" == help ]]
    ;;
esac

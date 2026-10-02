#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"; SCRIPTS=$(pwd)

BACKEND_URL="$(printf '%s' "${BACKEND_URL:-}" | tr -d ' "'$'\r\n\t' | sed 's#/*$##')"
if [ -z "$BACKEND_URL" ]; then
  BACKEND_URL="https://web2apkandaab.lovable.app"
fi
BUILDER_SECRET="$(printf '%s' "${BUILDER_SECRET:-}" | tr -d ' "'$'\r\n\t')"

api() { 
  curl -fsS -X POST "$BACKEND_URL/api/public/builder/$1" \
    -H "content-type: application/json" \
    -H "x-builder-secret: $BUILDER_SECRET" \
    -d "$2"
}

report() { 
  bash "$SCRIPTS/report.sh" "$@"
}

CFG=$(api config "{\"build_id\":\"$BUILD_ID\"}")
NAME=$(jq -r .apps.name <<<"$CFG"); URL=$(jq -r .apps.website_url <<<"$CFG")
PKG=$(jq -r .apps.package_name <<<"$CFG"); VNAME=$(jq -r .apps.version_name <<<"$CFG")
VCODE=$(jq -r .apps.version_code <<<"$CFG"); TYPE=$(jq -r .build_type <<<"$CFG")
report BUILDING "" 10

WORK=$(mktemp -d); cd "$WORK"
mkdir -p www && echo "<!doctype html><meta http-equiv=refresh content=\"0;url=$URL\">" > www/index.html
npm init -y >/dev/null
npm i @capacitor/core@6 @capacitor/cli@6 @capacitor/android@6 >/dev/null
HOST=$(node -e "console.log(new URL(process.argv[1]).host)" "$URL")
jq -n --arg id "$PKG" --arg n "$NAME" --arg u "$URL" --arg h "$HOST" \
  '{appId:$id,appName:$n,webDir:"www",server:{url:$u,allowNavigation:[$h]}}' > capacitor.config.json
npx cap add android >/dev/null
report BUILDING "" 40

cd android
sed -i "s/versionCode .*/versionCode $VCODE/; s/versionName .*/versionName \"$VNAME\"/" app/build.gradle
chmod +x gradlew
TASKS=""
[[ "$TYPE" == "apk" || "$TYPE" == "both" ]] && TASKS="$TASKS assembleDebug"
[[ "$TYPE" == "aab" || "$TYPE" == "both" ]] && TASKS="$TASKS bundleDebug"
./gradlew $TASKS --no-daemon -q
report BUILDING "" 85

upload() { # kind file
  local r url path size
  r=$(api upload-url "{\"build_id\":\"$BUILD_ID\",\"kind\":\"$1\"}")
  url=$(jq -r .url <<<"$r"); path=$(jq -r .path <<<"$r"); size=$(stat -c %s "$2")
  curl -fsS -X PUT "$url" -H "content-type: application/octet-stream" --data-binary @"$2" >/dev/null
  api artifact "{\"build_id\":\"$BUILD_ID\",\"kind\":\"$1\",\"path\":\"$path\",\"size_bytes\":$size}" >/dev/null
}
[[ -f app/build/outputs/apk/debug/app-debug.apk ]] && upload apk app/build/outputs/apk/debug/app-debug.apk
[[ -f app/build/outputs/bundle/debug/app-debug.aab ]] && upload aab app/build/outputs/bundle/debug/app-debug.aab
report SUCCESS

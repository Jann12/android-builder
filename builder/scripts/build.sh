#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"; SCRIPTS=$(pwd)
api() { curl -fsS -X POST "$BACKEND_URL/api/public/builder/$1" -H "content-type: application/json" -H "x-builder-secret: $BUILDER_SECRET" -d "$2"; }
report() { bash "$SCRIPTS/report.sh" "$@"; }

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
ICON_URL=$(jq -r '.icon_url // empty' <<<"$CFG")
if [[ -z "$ICON_URL" ]]; then
  echo "No custom icon uploaded - using default icon"
elif curl -fsSL "$ICON_URL" -o /tmp/icon_src; then
  command -v convert >/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq imagemagick >/dev/null; }
  RES=app/src/main/res
  rm -rf "$RES"/mipmap-anydpi-v26 "$RES"/mipmap-*/ic_launcher*.webp "$RES"/mipmap-*/ic_launcher*.png
  for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    dir="$RES/mipmap-${d%%:*}"; sz=${d##*:}; mkdir -p "$dir"
    convert /tmp/icon_src -background none -resize ${sz}x${sz} -gravity center -extent ${sz}x${sz} "PNG32:$dir/ic_launcher.png"
    cp "$dir/ic_launcher.png" "$dir/ic_launcher_round.png"
    cp "$dir/ic_launcher.png" "$dir/ic_launcher_foreground.png"
  done
  echo "Custom icon installed"
else
  echo "WARNING: could not download custom icon - using default icon"
fi
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

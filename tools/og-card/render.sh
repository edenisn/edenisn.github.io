#!/usr/bin/env bash
#
# Regenerates source/images/og-<locale>.png, the 1200x630 previews that
# messengers show for a link. Run it after the name, the role or the portrait
# changes; the result is committed, so a normal build needs no browser.
#
#   tools/og-card/render.sh
#
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp "$root/source/images/portrait.jpg" "$work/"

render() {
  local lang="$1" name="$2" role="$3"

  sed -e "s|__LANG__|$lang|" -e "s|__NAME__|$name|" -e "s|__ROLE__|$role|" \
    "$root/tools/og-card/card.html.template" > "$work/card-$lang.html"

  # Rendered at 2x and scaled down, otherwise the text edges look ragged.
  "$chrome" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=2 --window-size=1200,630 \
    --screenshot="$work/og-$lang.png" "file://$work/card-$lang.html" >/dev/null 2>&1

  sips -z 630 1200 "$work/og-$lang.png" --out "$root/source/images/og-$lang.png" >/dev/null
  echo "source/images/og-$lang.png"
}

render ru "Денис Ерофеев" "Senior Ruby on Rails разработчик"
render en "Denis Erofeev" "Senior Ruby on Rails developer"

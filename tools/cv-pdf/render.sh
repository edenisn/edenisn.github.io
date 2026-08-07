#!/usr/bin/env bash
#
# Renders source/cv-<locale>.pdf from the already built site, using the print
# rules in site.css.scss. The result is committed so that serving the site
# stays a matter of copying static files.
#
#   bundle exec middleman build && tools/cv-pdf/render.sh
#
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"

# A different port every run. Chrome's HTTP cache is keyed by the full URL, so
# reusing one port makes it print the previous stylesheet after a CSS change.
port=$((4300 + RANDOM % 300))

if [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
  chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
else
  chrome="$(command -v google-chrome || command -v chromium)"
fi

if [ ! -d "$root/build" ]; then
  echo "build/ is missing: run 'bundle exec middleman build' first" >&2
  exit 1
fi

# Pages reference stylesheets with root-absolute paths, so the build has to be
# served over HTTP; under file:// Chrome would look for /stylesheets at the
# root of the filesystem and print an unstyled page.
ruby -run -e httpd "$root/build" -p "$port" >/dev/null 2>&1 &
server=$!
# By pid, not by job spec: job control is off in a non-interactive shell, so
# `kill %1` fails and the script hangs waiting for webrick.
trap 'kill "$server" 2>/dev/null || true' EXIT

for _ in $(seq 40); do
  curl -sf -o /dev/null "http://127.0.0.1:$port/" && break
  sleep 0.25
done

render() {
  local lang="$1" path="$2"
  local out="$root/source/cv-$lang.pdf"
  local profile waited=0 pid size='' previous='x'
  profile="$(mktemp -d)"

  rm -f "$out"

  "$chrome" --headless=new --disable-gpu --no-pdf-header-footer \
    --user-data-dir="$profile" \
    --no-first-run --no-default-browser-check \
    --disable-background-networking --disable-component-update \
    --disable-extensions --disable-sync \
    --print-to-pdf="$out" \
    "http://127.0.0.1:$port$path" >/dev/null 2>&1 &
  pid=$!

  # Headless Chrome writes the PDF and then, on macOS, often refuses to exit.
  # So wait for the file to stop growing rather than for the process, and stop
  # it ourselves; the cap keeps a real failure from stalling the whole job.
  while [ "$waited" -lt 90 ]; do
    size=''
    [ -f "$out" ] && size="$(wc -c <"$out")"
    [ -n "$size" ] && [ "$size" = "$previous" ] && break
    previous="$size"
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
    waited=$((waited + 1))
  done

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -rf "$profile"

  if [ ! -s "$out" ]; then
    echo "cv-$lang.pdf was not written after ${waited}s" >&2
    return 1
  fi

  echo "source/cv-$lang.pdf ($(wc -c <"$out" | tr -d ' ') bytes)"
}

render ru /cv/
render en /en/cv/

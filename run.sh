#!/usr/bin/env bash
# Usage: ./run.sh sf7|sf8   (PHP=php8.4 by default; needs node and composer)
set -u
variant=${1:?usage: run.sh sf7|sf8}
cd "$(dirname "$0")"
php=${PHP:-php8.4}
export VARIANT_DIR="$PWD/$variant"
composer_bin=$(command -v composer)
composer() { "$php" "$composer_bin" "$@"; }
[ -d "$variant/vendor" ] || composer update -d "$variant" -n -q || { echo "composer failed for $variant" >&2; exit 1; }
clients="curl-20 curl-prior sf-curl sf-amp amp-only2"
base=$((20000 + RANDOM % 20000))
out=results/$variant.txt
{
  echo "# variant: $variant"
  echo "# php: $($php -r 'echo PHP_VERSION;')  libcurl: $($php -r 'echo curl_version()["version"];')"
  composer show -d "$variant" 2>/dev/null | grep -E '^(symfony/http-client|amphp/http-client|amphp/socket) ' | awk '{print "# " $1 " " $2}'
  echo
  echo "## Part A: first bytes on the wire, cleartext http:// (raw TCP listener)"
  i=0
  for c in $clients; do
    i=$((i+1)); port=$((base+i))
    node capture.js $port > "results/.wire-$c" & pid=$!
    sleep 0.7
    timeout 10 $php probe.php $c "http://127.0.0.1:$port/" > /dev/null 2>&1
    sleep 0.8; kill $pid 2>/dev/null; wait $pid 2>/dev/null
    printf '%-11s %s\n' "$c" "$(sed '2,$s/^/            (further connection) /' results/.wire-$c)"
    rm -f "results/.wire-$c"
  done
  echo
  h2=$((base+50)); h1=$((base+51))
  node servers.js $h2 $h1 & spid=$!
  sleep 1
  for srv in "h2c-only:$h2" "http1-only:$h1"; do
    echo "## Part B: server $(echo $srv | cut -d: -f1)"
    for c in $clients; do
      printf '%-11s ' "$c"; timeout 10 $php probe.php $c "http://127.0.0.1:$(echo $srv | cut -d: -f2)/"
    done
    echo
  done
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
} > "$out" 2>&1
cat "$out"

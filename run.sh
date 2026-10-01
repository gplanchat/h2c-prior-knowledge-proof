#!/usr/bin/env bash
# Usage: ./run.sh sf7|sf8|sf7-patched|sf8-patched   (PHP=php8.4 by default; needs node, npm, go and composer)
set -u
variant=${1:?usage: run.sh sf7|sf8|sf7-patched|sf8-patched}
cd "$(dirname "$0")"
php=${PHP:-php8.4}
export VARIANT_DIR="$PWD/$variant"
composer_bin=$(command -v composer)
composer() { "$php" "$composer_bin" "$@"; }
basevariant=${variant%-patched}
if [ "$variant" != "$basevariant" ]; then
  # "-patched": a copy of the base variant with patches/*.patch applied to symfony/http-client
  [ -d "$basevariant/vendor" ] || composer update -d "$basevariant" -n -q || { echo "composer failed for $basevariant" >&2; exit 1; }
  if [ ! -d "$variant/vendor" ]; then
    mkdir -p "$variant"; cp "$basevariant/composer.json" "$basevariant/composer.lock" "$variant/"; cp -r "$basevariant/vendor" "$variant/vendor"
    for p in patches/*.patch; do patch -s -p1 -d "$variant/vendor/symfony/http-client" < "$p" || { echo "patch $p failed" >&2; exit 1; }; done
  fi
fi
[ -d "$variant/vendor" ] || composer update -d "$variant" -n -q || { echo "composer failed for $variant" >&2; exit 1; }
[ -x grpc/bin-grpc-go ] || (cd grpc/go && go build -o ../bin-grpc-go .) || { echo "go build failed" >&2; exit 1; }
[ -d grpc/node/node_modules ] || (cd grpc/node && npm ci --no-audit --no-fund -s) || { echo "npm ci failed" >&2; exit 1; }
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
  gports=($((base+60)) $((base+61)))
  grpc/bin-grpc-go -addr 127.0.0.1:${gports[0]} 2>/dev/null & gopid=$!
  node grpc/node/server.js 127.0.0.1:${gports[1]} & jspid=$!
  sleep 1.5
  i=0
  for name in "grpc-go" "grpc-js"; do
    echo "## Part C: gRPC server $name (unary grpc.health.v1.Health/Check, cleartext)"
    for c in $clients; do
      printf '%-11s ' "$c"; timeout 10 $php probe-grpc.php $c "127.0.0.1:${gports[$i]}"
    done
    echo; i=$((i+1))
  done
  kill $gopid $jspid 2>/dev/null; wait $gopid $jspid 2>/dev/null
} > "$out" 2>&1
cat "$out"

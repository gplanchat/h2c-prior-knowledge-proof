# h2c with prior knowledge in Symfony HttpClient

Measurements that back [symfony/symfony#66530](https://github.com/symfony/symfony/issues/66530):
what `CurlHttpClient` and `AmpHttpClient` send on a cleartext `http://` URL when the request sets
`http_version: 2.0`, and what changes if an explicit `2.0` on `http://` means HTTP/2 with prior
knowledge.

## Result

On `http://`, an explicit `http_version: 2.0` never produces cleartext HTTP/2 with prior knowledge.

| Client | First bytes on the wire |
|---|---|
| `AmpHttpClient`, `http_version: 2.0` | `POST / HTTP/1.1`, no `Upgrade` header (same as the default) |
| `CurlHttpClient`, `http_version: 2.0` | `POST / HTTP/1.1` with `Upgrade: h2c` |
| libcurl, `CURL_HTTP_VERSION_2_0` | `POST / HTTP/1.1` with `Upgrade: h2c` |
| libcurl, `CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE` | `PRI * HTTP/2.0` (the HTTP/2 connection preface) |
| amphp/http-client, `setProtocolVersions(['2'])` | `PRI * HTTP/2.0` |

Against plain test servers (Node `http2` for the h2c-only server, Node `http` for the HTTP/1.1-only one):

| Client | h2c-only server | HTTP/1.1-only server |
|---|---|---|
| libcurl `CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE` | 200, trailer `grpc-status: 0` read | fails: "Remote peer returned unexpected data while we expected SETTINGS frame" |
| libcurl `CURL_HTTP_VERSION_2_0` | fails: "Received HTTP/0.9 when not allowed" | 200 over HTTP/1.1 (the upgrade falls back) |
| `CurlHttpClient`, `2.0` | fails with the same message | 200 |
| `AmpHttpClient`, `2.0` | fails: the socket is closed | 200 |
| amphp/http-client `['2']` | 200, trailers `{"grpc-status":["0"]}` | fails: "Connection closed before HTTP/2 settings could be received" |

Against real gRPC servers, a unary `grpc.health.v1.Health/Check` call on a cleartext port, with `content-type: application/grpc` and `te: trailers`:

| Client | grpc-go 1.84.0 | grpc-js 1.14.5 |
|---|---|---|
| libcurl `CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE` | 200, body `00000000020801` (SERVING), trailer `grpc-status: 0` | same |
| libcurl `CURL_HTTP_VERSION_2_0` | fails: "Received HTTP/0.9 when not allowed" | same |
| `CurlHttpClient`, `2.0` | fails with the same message | same |
| `AmpHttpClient`, `2.0` | fails: the socket is closed | same |
| amphp/http-client `['2']` | 200, same body, trailers `grpc-status: 0` | same |

Symfony 7.4.20 and Symfony 8.1.8 give the same results (`results/sf7.txt`, `results/sf8.txt`). Neither
release exposes the `trailers` info yet, so the Symfony rows do not read trailers; the libcurl and
amphp rows read them directly.

What follows from it:

- Mapping an explicit `2.0` on `http://` to prior knowledge (`CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE` for
  Curl, `['2']` for Amp) makes cleartext gRPC servers reachable.
- The same mapping makes an HTTP/1.1-only server unreachable with `2.0` on `http://`, where the
  upgrade fallback works today.
- `AmpHttpClient` maps `2.0` to `['2', '1.1', '1.0']`. `amphp/http-client` treats only `['2']` alone
  as prior knowledge, so the change must apply on `http:` only. On `https:` the fallback list keeps
  ALPN negotiation working.

## Run it

Requirements: PHP 8.4 (`AmpHttpClient` with amphp/http-client 5 refuses to load below 8.4) with the
curl extension, Node.js with npm, Go, Composer.

```sh
./run.sh sf7   # Symfony 7.4
./run.sh sf8   # Symfony 8.1
```

`PHP=/path/to/php ./run.sh sf8` selects another PHP binary. Each run installs its variant in `sf7/`
or `sf8/`, then writes `results/<variant>.txt`.

- Part A starts `capture.js`, a raw TCP listener that prints the first bytes each client sends.
- Part B starts `servers.js`, an h2c-only server that answers 200 with a `grpc-status: 0` trailer
  and an HTTP/1.1-only server, then runs `probe.php` against both.
- Part C starts two gRPC servers, `grpc/go` (grpc-go with the standard health service, built on first
  run) and `grpc/node` (`@grpc/grpc-js`, installed on first run), and runs `probe-grpc.php` against
  both.

## Limits

- Parts A and B use Node servers that are not gRPC servers; Part C uses grpc-go and grpc-js. A
  Temporal server, or another server with its own HTTP/2 settings, is not measured.
- Only Symfony 7.4.20 and 8.1.8 are measured, not the 8.2 development branch.
- amphp/http-client 4 (the PHP 8.2 path of Symfony 7) is not measured.
- HTTP/2 through a proxy and `CONNECT` are not covered.

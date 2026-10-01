<?php
require getenv('VARIANT_DIR').'/vendor/autoload.php';
[$which, $url] = [$argv[1], $argv[2]];
$out = function (string $s) { echo $s, "\n"; };
try {
  switch ($which) {
    case 'curl-prior': case 'curl-20':
      $trailers = []; $ch = curl_init($url);
      curl_setopt_array($ch, [CURLOPT_HTTP_VERSION => $which === 'curl-prior' ? CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE : CURL_HTTP_VERSION_2_0, CURLOPT_POST => 1, CURLOPT_POSTFIELDS => 'x', CURLOPT_TIMEOUT => 3, CURLOPT_RETURNTRANSFER => 1,
        CURLOPT_HEADERFUNCTION => function ($ch, $l) use (&$trailers) { if (stripos($l, 'grpc-status') === 0) $trailers[] = trim($l); return strlen($l); }]);
      $body = curl_exec($ch);
      $out($body === false ? 'FAIL: '.curl_error($ch) : 'OK status='.curl_getinfo($ch, CURLINFO_RESPONSE_CODE).' http_version='.curl_getinfo($ch, CURLINFO_HTTP_VERSION).' trailers='.json_encode($trailers));
      break;
    case 'sf-curl':
      $r = (new Symfony\Component\HttpClient\CurlHttpClient())->request('POST', $url, ['http_version' => '2.0', 'body' => 'x', 'timeout' => 3]);
      $out('OK status='.$r->getStatusCode().' http_version='.$r->getInfo('http_version')); break;
    case 'sf-amp':
      $r = (new Symfony\Component\HttpClient\AmpHttpClient())->request('POST', $url, ['http_version' => '2.0', 'body' => 'x', 'timeout' => 3]);
      $out('OK status='.$r->getStatusCode().' http_version='.$r->getInfo('http_version')); break;
    case 'amp-only2':
      $c = Amp\Http\Client\HttpClientBuilder::buildDefault();
      $req = new Amp\Http\Client\Request($url, 'POST', 'x'); $req->setProtocolVersions(['2']); $req->setTransferTimeout(3);
      $resp = $c->request($req, new Amp\NullCancellation()); $resp->getBody()->buffer();
      $tr = $resp->getTrailers()->await();
      $out('OK status='.$resp->getStatus().' protocol='.$resp->getProtocolVersion().' trailers='.json_encode($tr->getHeaders())); break;
  }
} catch (Throwable $e) { $out('FAIL: '.get_class($e).': '.substr($e->getMessage(), 0, 110)); }

<?php
// Evangelio del día para el Dashboard de la Bitácora.
// Lo lee de Vatican News (medio oficial de la Santa Sede, enlazado desde vatican.va) desde el servidor,
// porque su sitio no deja que el navegador lo lea directo. Guarda una copia por día.
// Uso: evangelio.php?fecha=YYYY-MM-DD  →  {fecha, titulo, cita, parrafos[], url}
header('Content-Type: application/json; charset=utf-8');
header('X-Robots-Tag: noindex, nofollow');

function responder($codigo, $datos) {
  http_response_code($codigo);
  if ($codigo === 200) header('Cache-Control: public, max-age=21600');
  else header('Cache-Control: no-store');
  echo json_encode($datos, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
  exit;
}

$fecha = isset($_GET['fecha']) ? (string)$_GET['fecha'] : '';
if (!preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $fecha, $m) || !checkdate((int)$m[2], (int)$m[3], (int)$m[1])) {
  $hoy = new DateTime('now', new DateTimeZone('America/Mexico_City'));
  $fecha = $hoy->format('Y-m-d');
  preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $fecha, $m);
}
$url = "https://www.vaticannews.va/es/evangelio-de-hoy/{$m[1]}/{$m[2]}/{$m[3]}.html";
$cache = rtrim(sys_get_temp_dir(), '/') . "/tdd-evangelio-$fecha.json";

if (is_file($cache) && filesize($cache) > 50) {
  header('Cache-Control: public, max-age=21600');
  readfile($cache);
  exit;
}

// Descargar la página del día
$html = false;
if (function_exists('curl_init')) {
  $c = curl_init($url);
  curl_setopt_array($c, [CURLOPT_RETURNTRANSFER => true, CURLOPT_FOLLOWLOCATION => true, CURLOPT_TIMEOUT => 8,
    CURLOPT_USERAGENT => 'Mozilla/5.0 (Bitacora Tiempo de Dios)']);
  $html = curl_exec($c);
  if (curl_getinfo($c, CURLINFO_HTTP_CODE) !== 200) $html = false;
  curl_close($c);
}
if (!$html) {
  $ctx = stream_context_create(['http' => ['timeout' => 8, 'header' => "User-Agent: Mozilla/5.0 (Bitacora Tiempo de Dios)\r\n"]]);
  $html = @file_get_contents($url, false, $ctx);
}
if (!$html) responder(502, ['error' => 'No se pudo leer Vatican News.', 'url' => $url]);

// Sección "Evangelio del Día"
if (!preg_match('~<h2>\s*Evangelio del D[ií]a\s*</h2>.*?<div class="section__content">(.*?)</div>~siu', $html, $sec)) {
  responder(502, ['error' => 'Vatican News cambió el formato de la página.', 'url' => $url]);
}
preg_match_all('~<p[^>]*>(.*?)</p>~si', $sec[1], $ps);
$parrafos = [];
foreach ($ps[1] as $p) {
  $t = html_entity_decode(strip_tags(preg_replace('~<br\s*/?>~i', ' ', $p)), ENT_QUOTES | ENT_HTML5, 'UTF-8');
  $t = trim(preg_replace('/\s+/u', ' ', str_replace("\xC2\xA0", ' ', $t)));
  if ($t !== '') $parrafos[] = $t;
}
$titulo = ''; $cita = '';
foreach ($parrafos as $i => $t) {
  if ($titulo === '' && preg_match('/^Lectura del santo evangelio/iu', $t)) { $titulo = $t; unset($parrafos[$i]); continue; }
  if ($cita === '' && mb_strlen($t) < 60 && preg_match('/^[1-3]?\s?\p{L}+\.?\s+\d+/u', $t)) { $cita = $t; unset($parrafos[$i]); }
  if ($titulo !== '' && $cita !== '') break;
}
$parrafos = array_values($parrafos);
if (!$parrafos) responder(502, ['error' => 'No se encontró el texto del evangelio.', 'url' => $url]);

$json = json_encode(['fecha' => $fecha, 'titulo' => $titulo, 'cita' => $cita, 'parrafos' => $parrafos, 'url' => $url,
  'fuente' => 'Vatican News'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
@file_put_contents($cache, $json);
header('Cache-Control: public, max-age=21600');
echo $json;

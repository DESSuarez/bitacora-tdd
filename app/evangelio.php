<?php
// Lecturas del día para el Dashboard de la Bitácora.
// Evangelio, primera y segunda lectura: Vatican News (medio oficial de la Santa Sede, enlazado desde vatican.va).
// Salmo responsorial: Evangelio del Día (evangeliodeldia.org), porque Vatican News no lo publica.
// Se leen desde el servidor (esos sitios no dejan que el navegador los lea directo) y se guarda una copia por día.
// Uso: evangelio.php?fecha=YYYY-MM-DD
//   → {fecha, url, lecturas:[{tipo, nombre, titulo, cita, parrafos[]}], y por compatibilidad titulo, cita, parrafos del evangelio}
//   tipo: evangelio | primera | salmo | segunda (en ese orden)
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
$cache = rtrim(sys_get_temp_dir(), '/') . "/tdd-lecturas-v2-$fecha.json";

if (is_file($cache) && filesize($cache) > 50) {
  header('Cache-Control: public, max-age=21600');
  readfile($cache);
  exit;
}

function descargar($url) {
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
  return $html ?: '';
}
function limpiar($t) {
  $t = html_entity_decode(strip_tags(preg_replace('~<br\s*/?>~i', "\n", $t)), ENT_QUOTES | ENT_HTML5, 'UTF-8');
  $t = str_replace("\xC2\xA0", ' ', $t);
  $t = preg_replace('/[ \t]+/u', ' ', $t);
  return trim(preg_replace('/\s*\n\s*/u', "\n", $t));
}
// Párrafos de una sección de Vatican News ("Lectura del Día", "Evangelio del Día")
function seccion($html, $nombre) {
  if (!preg_match('~<h2>\s*' . $nombre . '\s*</h2>.*?<div class="section__content">(.*?)</div>~siu', $html, $sec)) return [];
  preg_match_all('~<p[^>]*>(.*?)</p>~si', $sec[1], $ps);
  $out = [];
  foreach ($ps[1] as $p) { $t = trim(preg_replace('/\s+/u', ' ', limpiar($p))); if ($t !== '') $out[] = $t; }
  return $out;
}
// Separa título («Lectura del…»), cita («Lucas 17, 26-37») y texto
function lectura($tipo, $nombre, $pars) {
  $titulo = ''; $cita = '';
  foreach ($pars as $i => $t) {
    if ($titulo === '' && preg_match('/^Lectura (del|de la|de los|de las)\b/iu', $t)) { $titulo = $t; unset($pars[$i]); continue; }
    if ($cita === '' && mb_strlen($t) < 70 && preg_match('/^[1-3]?\s?\p{L}+\.?\s+\d+/u', $t)) { $cita = $t; unset($pars[$i]); }
    if ($titulo !== '' && $cita !== '') break;
  }
  $pars = array_values($pars);
  return $pars ? ['tipo' => $tipo, 'nombre' => $nombre, 'titulo' => $titulo, 'cita' => $cita, 'parrafos' => $pars] : null;
}

$html = descargar($url);
if (!$html) responder(502, ['error' => 'No se pudo leer Vatican News.', 'url' => $url]);

$lecturas = [];
$ev = lectura('evangelio', 'Evangelio', seccion($html, 'Evangelio del D[ií]a'));
if (!$ev) responder(502, ['error' => 'Vatican News cambió el formato de la página.', 'url' => $url]);
$lecturas[] = $ev;

// "Lectura del Día": entre semana trae solo la primera; los domingos, «Primera lectura» y «Segunda lectura»
$lec = seccion($html, 'Lectura del D[ií]a');
$primera = []; $segunda = []; $actual = &$primera;
foreach ($lec as $t) {
  if (preg_match('/^Primera lectura$/iu', $t)) { $actual = &$primera; continue; }
  if (preg_match('/^Segunda lectura$/iu', $t)) { $actual = &$segunda; continue; }
  $actual[] = $t;
}
unset($actual);
if ($l = lectura('primera', 'Primera lectura', $primera)) $lecturas[] = $l;

// Salmo responsorial (Evangelio del Día)
$fe = str_replace('-', '', $fecha);
$base = "https://feed.evangelizo.org/v2/reader.php?date=$fe&lang=SP&content=PS";
$salmo = descargar("$base&type=reading");
if ($salmo && !preg_match('/^\s*</', $salmo)) {
  $estrofas = array_values(array_filter(array_map('trim', preg_split('~(<br\s*/?>\s*){2,}~i', $salmo)), fn($x) => $x !== ''));
  $estrofas = array_values(array_filter(array_map('limpiar', $estrofas), fn($x) => $x !== ''));
  $cita = limpiar(descargar("$base&type=reading_lt"));
  if ($estrofas) $lecturas[] = ['tipo' => 'salmo', 'nombre' => 'Salmo', 'titulo' => 'Salmo responsorial', 'cita' => rtrim($cita, '.'), 'parrafos' => $estrofas,
    'fuente' => 'evangeliodeldia.org'];
}

if ($l = lectura('segunda', 'Segunda lectura', $segunda)) $lecturas[] = $l;

$json = json_encode(['fecha' => $fecha, 'url' => $url, 'fuente' => 'Vatican News', 'lecturas' => $lecturas,
  'titulo' => $ev['titulo'], 'cita' => $ev['cita'], 'parrafos' => $ev['parrafos']], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
@file_put_contents($cache, $json);
header('Cache-Control: public, max-age=21600');
echo $json;

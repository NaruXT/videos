#!/usr/bin/env bats

setup() {
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/descargar.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR" || exit 1
}

teardown() {
  cd /
  rm -rf "$WORKDIR"
}

assert_carpeta_con_transcripcion() {
  local id="$1"
  local carpeta srt txt
  carpeta="$(find "$WORKDIR" -maxdepth 1 -type d -iname "*${id}*")"
  srt="$(find "$carpeta" -maxdepth 1 -iname '*.srt')"
  txt="$(find "$carpeta" -maxdepth 1 -iname '*.txt')"
  [ -n "$srt" ] && [ -s "$srt" ]
  [ -n "$txt" ] && [ -s "$txt" ]
}

@test "sin URL: imprime uso y termina con error" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"uso"* || "$output" == *"Uso"* || "$output" == *"USO"* ]]
}

@test "video individual: descarga el mp4 en una carpeta propia" {
  run "$SCRIPT" "https://www.youtube.com/watch?v=jNQXAC9IVRw" --resolucion 144
  [ "$status" -eq 0 ]

  carpeta="$(find "$WORKDIR" -maxdepth 1 -type d -iname '*jNQXAC9IVRw*')"
  [ -n "$carpeta" ]

  mp4="$(find "$carpeta" -maxdepth 1 -iname '*.mp4')"
  [ -n "$mp4" ]
  [ -s "$mp4" ]
}

@test "idempotencia: si el video y la transcripcion ya existen, la segunda corrida los salta" {
  "$SCRIPT" "https://www.youtube.com/watch?v=jNQXAC9IVRw" --resolucion 144

  run "$SCRIPT" "https://www.youtube.com/watch?v=jNQXAC9IVRw" --resolucion 144
  [ "$status" -eq 0 ]
  [[ "$output" == *"ya existe, se salta"* ]]
  [[ "$output" == *"transcripción ya existe, se salta"* ]]
}

@test "--forzar: rehace tanto la descarga como la transcripcion" {
  "$SCRIPT" "https://www.youtube.com/watch?v=jNQXAC9IVRw" --resolucion 144

  run "$SCRIPT" "https://www.youtube.com/watch?v=jNQXAC9IVRw" --resolucion 144 --forzar
  [ "$status" -eq 0 ]
  [[ "$output" == *"descargando video"* ]]
  [[ "$output" != *"transcripción ya existe, se salta"* ]]
}

@test "video con subtitulo oficial: usa el subtitulo y no invoca Whisper" {
  run "$SCRIPT" "https://www.youtube.com/watch?v=n99bA45CGSs" --resolucion 144
  [ "$status" -eq 0 ]
  [[ "$output" == *"subtítulo oficial encontrado"* ]]
  assert_carpeta_con_transcripcion "n99bA45CGSs"
}

@test "URL invalida: termina con error y no deja carpetas a medio crear" {
  run "$SCRIPT" "https://www.youtube.com/watch?v=esto-no-existe-000" --resolucion 144
  [ "$status" -ne 0 ]

  cantidad_carpetas="$(find "$WORKDIR" -maxdepth 1 -type d ! -path "$WORKDIR" | wc -l | tr -d ' ')"
  [ "$cantidad_carpetas" -eq 0 ]
}

@test "resolucion invalida: termina con error" {
  run "$SCRIPT" "https://www.youtube.com/watch?v=jNQXAC9IVRw" --resolucion no-es-un-numero
  [ "$status" -ne 0 ]
}

@test "video sin subtitulo oficial: cae a transcripcion con Whisper" {
  run "$SCRIPT" "https://www.youtube.com/watch?v=qLGNj-xrgvY" --resolucion 144
  [ "$status" -eq 0 ]
  [[ "$output" == *"sin subtítulo oficial"* ]]
  assert_carpeta_con_transcripcion "qLGNj-xrgvY"
}

@test "resumen final: lista los archivos generados al terminar" {
  run "$SCRIPT" "https://www.youtube.com/watch?v=jNQXAC9IVRw" --resolucion 144
  [ "$status" -eq 0 ]
  [[ "$output" == *"Listo. Archivos generados:"* ]]
  [[ "$output" == *".mp4"* ]]
  [[ "$output" == *".srt"* ]]
  [[ "$output" == *".txt"* ]]
}

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
modelo="${script_dir}/models/ggml-large-v3-turbo.bin"

uso() {
  cat <<'EOF'
Uso: descargar.sh <url> [--resolucion N] [--forzar]

  <url>              URL de un video o playlist/canal de YouTube
  --resolucion N      Resolución máxima de video (default: 1080)
  --forzar             Rehace descarga y transcripción aunque ya existan
EOF
}

url=""
resolucion=1080
forzar=false

while [ $# -gt 0 ]; do
  case "$1" in
    --resolucion)
      resolucion="$2"
      shift 2
      ;;
    --forzar)
      forzar=true
      shift
      ;;
    -h|--help)
      uso
      exit 0
      ;;
    *)
      if [ -n "$url" ]; then
        echo "Error: se recibió más de una URL (\"$url\" y \"$1\")" >&2
        exit 1
      fi
      url="$1"
      shift
      ;;
  esac
done

if [ -z "$url" ]; then
  uso >&2
  exit 1
fi

buscar_uno() {
  find "$1" -maxdepth 1 -iname "$2" 2>/dev/null | head -n1 || true
}

derivar_txt() {
  local srt="$1" txt="$2"
  awk '/-->/{next} /^[0-9]+$/{next} NF{print}' "$srt" > "$txt"
}

idioma_audio() {
  local mp4="$1"
  local tag
  tag="$(ffprobe -v quiet -select_streams a:0 -show_entries stream_tags=language \
    -of default=noprint_wrappers=1:nokey=1 "$mp4" 2>/dev/null || true)"
  case "$tag" in
    eng) echo "en" ;;
    spa) echo "es" ;;
    *) echo "" ;;
  esac
}

procesar_video() {
  local id="$1"
  local url_video="https://www.youtube.com/watch?v=${id}"
  local nombre_carpeta
  nombre_carpeta="$(yt-dlp --print filename -o "%(title)s [${id}]" "$url_video")"
  local carpeta="$nombre_carpeta"
  local base="${carpeta}/${nombre_carpeta}"
  local plantilla="${base}.%(ext)s"

  local mp4_final="${base}.mp4"
  local mp4_existente
  mp4_existente="$(buscar_uno "$carpeta" '*.mp4')"

  if [ -n "$mp4_existente" ] && [ "$forzar" = false ]; then
    echo "[$id] video ya existe, se salta la descarga"
  else
    echo "[$id] descargando video (resolución <= ${resolucion}p)..."
    yt-dlp -f "bv*[height<=${resolucion}]+ba/b[height<=${resolucion}]" \
      --remux-video mp4 \
      -o "$plantilla" \
      "$url_video"
  fi

  local srt_final="${base}.srt"
  local txt_final="${base}.txt"

  if [ -s "$srt_final" ] && [ -s "$txt_final" ] && [ "$forzar" = false ]; then
    echo "[$id] transcripción ya existe, se salta"
    salidas+=("$base")
    return
  fi

  local sub_langs
  sub_langs="$(idioma_audio "$mp4_final")"
  if [ -z "$sub_langs" ]; then
    sub_langs="en,es"
    echo "[$id] idioma de audio no identificado, se prueban subtítulos en: ${sub_langs}"
  else
    echo "[$id] idioma de audio detectado: ${sub_langs}"
  fi

  yt-dlp --write-subs --sub-langs "$sub_langs" --skip-download --convert-subs srt \
    -o "${base}.subtitulo.%(ext)s" \
    "$url_video" >/dev/null 2>&1 || true

  local sub_encontrado
  sub_encontrado="$(buscar_uno "$carpeta" '*.subtitulo.*.srt')"

  if [ -n "$sub_encontrado" ]; then
    echo "[$id] subtítulo oficial encontrado, se omite Whisper"
    mv "$sub_encontrado" "$srt_final"
    find "$carpeta" -maxdepth 1 -iname '*.subtitulo.*' -delete
  else
    echo "[$id] sin subtítulo oficial, transcribiendo con Whisper..."
    local wav="${carpeta}/audio.wav"
    ffmpeg -y -i "$mp4_final" -vn -ar 16000 -ac 1 -c:a pcm_s16le "$wav" -loglevel error
    whisper-cli -m "$modelo" -f "$wav" -l auto -osrt -of "$base"
    rm -f "$wav"
  fi

  derivar_txt "$srt_final" "$txt_final"
  salidas+=("$base")
}

entradas="$(yt-dlp --flat-playlist --print id "$url")"
salidas=()
while IFS= read -r id; do
  [ -n "$id" ] || continue
  procesar_video "$id"
done <<< "$entradas"

echo ""
echo "Listo. Archivos generados:"
for base in "${salidas[@]}"; do
  echo "  ${base}.mp4"
  echo "  ${base}.srt"
  echo "  ${base}.txt"
done

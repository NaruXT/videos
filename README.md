# videos

Mecanismo ligero para descargar videos de YouTube junto con su transcripción de calidad.

- Descarga video vía `yt-dlp` (calidad configurable, default 1080p, MP4).
- Transcripción híbrida: usa subtítulos oficiales manuales si existen; si no, transcribe localmente con `whisper-cpp` (modelo `large-v3-turbo`).
- Genera transcripción en `.txt` y `.srt`, en el idioma original del video.
- Soporta URLs de video individual y de playlist/canal.
- Cada video queda organizado en su propia carpeta.

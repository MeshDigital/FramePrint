# FramePrint

An app that turns YouTube videos into printable "knowledge cards" — a
one-page PDF with a title, key steps/insights/warnings pulled from the
video via a local LLM, a few key frames, and a QR code back to the source.

Flutter app (Windows first, Android later). Everything runs locally: no
cloud APIs, video download/processing/summarization all happen on-device.

## Pipeline

1. Paste a YouTube URL → `yt-dlp` downloads the video.
2. Pick a segment (start/end) from the video.
3. `ffmpeg` cuts a preview GIF and extracts frames for that segment.
4. `ffmpeg` extracts audio → a local speech-to-text model transcribes it.
5. A local 7B model (via `llama.cpp`) summarizes the transcript into
   steps / insights / warnings.
6. A one-page PDF card is generated (title, steps, insights, warnings,
   frames, QR code back to the video) and stored in a local SQLite catalog.

See project memory / prior planning notes for the full phased breakdown
(Phase 1: Windows pipeline, Phase 2: Android port, Phase 3: UX polish).

## Status

Phase 1, steps 1-5 (URL input → download → segment selection → GIF/frame
extraction → transcription) are implemented and working, verified
end-to-end against a real video:
- SQLite-backed `VideoCard` catalog, with a `duration_seconds` migration already in place ([lib/db/app_database.dart](lib/db/app_database.dart), [lib/models/video_card.dart](lib/models/video_card.dart))
- `yt-dlp` wrapper for metadata + download ([lib/services/ytdlp_service.dart](lib/services/ytdlp_service.dart))
- `ffmpeg` wrapper for audio/GIF/frame extraction (audio as 16kHz mono WAV, ready for whisper.cpp) ([lib/services/ffmpeg_service.dart](lib/services/ffmpeg_service.dart))
- `whisper-cli` (whisper.cpp) wrapper for local, offline transcription ([lib/services/whisper_service.dart](lib/services/whisper_service.dart))
- Home screen (card list) + "new card" screen (URL → download with live log) + "card detail" screen (range slider → extract frames → pick up to 6 key frames → optional preview GIF → transcribe audio) ([lib/screens/](lib/screens/))

Not yet built: local LLM summarization, QR/PDF card generation.

Note: yt-dlp currently warns about a missing JS runtime ("No supported
JavaScript runtime could be found... YouTube extraction without a JS
runtime has been deprecated"). Downloads still work today, but
installing `deno` would silence this and future-proof extraction.

## Prerequisites (Windows dev machine)

- [Flutter SDK](https://flutter.dev) (stable channel), on PATH
- [Visual Studio Build Tools](https://visualstudio.microsoft.com/) with
  "Desktop development with C++" (for the Windows build)
- **Windows Developer Mode** enabled — required for Flutter's Windows
  build (symlink support): Settings → Privacy & security → For
  developers → Developer Mode → On
- [`ffmpeg`](https://ffmpeg.org/) on PATH
- [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) on PATH (`pip install yt-dlp`)
- [`whisper.cpp`](https://github.com/ggml-org/whisper.cpp) CLI build on PATH
  (`whisper-cli.exe`, e.g. from the `whisper-bin-x64.zip` Windows release
  asset), plus a ggml model — this repo currently hardcodes
  `C:\tools\whisper-cpp\models\ggml-base.bin`
  ([lib/services/whisper_service.dart](lib/services/whisper_service.dart)),
  downloadable from
  [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp)

## Running

```
flutter pub get
flutter run -d windows
```

## Not yet set up

- Local 7B LLM runtime (llama.cpp + a GGUF model)
- Android toolchain (cmdline-tools + licenses) for the Phase 2 port

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

Phase 1, step 1-2 (URL input → download) is implemented and working:
- SQLite-backed `VideoCard` catalog ([lib/db/app_database.dart](lib/db/app_database.dart), [lib/models/video_card.dart](lib/models/video_card.dart))
- `yt-dlp` wrapper for metadata + download ([lib/services/ytdlp_service.dart](lib/services/ytdlp_service.dart))
- `ffmpeg` wrapper for audio/GIF/frame extraction, not yet wired into the UI ([lib/services/ffmpeg_service.dart](lib/services/ffmpeg_service.dart))
- Home screen (card list) + "new card" screen (URL → download with live log) ([lib/screens/](lib/screens/))

Not yet built: segment-selection UI, transcript (STT), local LLM
summarization, QR/PDF card generation.

## Prerequisites (Windows dev machine)

- [Flutter SDK](https://flutter.dev) (stable channel), on PATH
- [Visual Studio Build Tools](https://visualstudio.microsoft.com/) with
  "Desktop development with C++" (for the Windows build)
- **Windows Developer Mode** enabled — required for Flutter's Windows
  build (symlink support): Settings → Privacy & security → For
  developers → Developer Mode → On
- [`ffmpeg`](https://ffmpeg.org/) on PATH
- [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) on PATH (`pip install yt-dlp`)

## Running

```
flutter pub get
flutter run -d windows
```

## Not yet set up

- Speech-to-text (Whisper or similar)
- Local 7B LLM runtime (llama.cpp + a GGUF model)
- Android toolchain (cmdline-tools + licenses) for the Phase 2 port

# FramePrint

An app that turns YouTube videos into printable "knowledge cards" — a
one-page PDF with a title, key steps/insights/warnings pulled from the
video via a local LLM, a few key frames, and a QR code back to the source.

Flutter app (Windows first, Android later). Everything runs locally: no
cloud APIs, video download/processing/summarization all happen on-device.

## Pipeline

1. Paste a YouTube URL → `yt-dlp` downloads the video.
2. Pick a segment (start/end) from the video → `ffmpeg` cuts a preview GIF
   and a frame gallery to hand-pick a cover image from.
3. `ffmpeg` extracts audio → whisper.cpp transcribes it **with per-segment
   timestamps**.
4. A local 7B model (via `llama.cpp`) summarizes the timestamped transcript
   into steps / insights / warnings — each step is tagged with the moment
   in the video it corresponds to.
5. `ffmpeg` grabs a frame at each step's exact timestamp, so the printed
   card shows the right picture next to the right instruction instead of
   an arbitrary gallery of frames.
6. A PDF card is generated (title, QR code back to the video, each step
   paired with its own frame, insights, warnings) — paginated across
   multiple pages if it doesn't fit on one — and stored in a local SQLite
   catalog.

See project memory / prior planning notes for the full phased breakdown
(Phase 1: Windows pipeline, Phase 2: Android port, Phase 3: UX polish).

## Status

The full Phase 1 pipeline (URL → download → segment selection →
GIF/frame extraction → transcription → local LLM summarization →
printable PDF card) is implemented and working, verified end-to-end
against real videos:
- SQLite-backed `VideoCard` catalog, with a `duration_seconds` migration already in place ([lib/db/app_database.dart](lib/db/app_database.dart), [lib/models/video_card.dart](lib/models/video_card.dart))
- `yt-dlp` wrapper for metadata + download ([lib/services/ytdlp_service.dart](lib/services/ytdlp_service.dart))
- `ffmpeg` wrapper for audio/GIF/frame extraction (audio as 16kHz mono WAV, ready for whisper.cpp) ([lib/services/ffmpeg_service.dart](lib/services/ffmpeg_service.dart))
- `whisper-cli` (whisper.cpp) wrapper for local, offline transcription **with per-segment timestamps** ([lib/services/whisper_service.dart](lib/services/whisper_service.dart))
- `llama-server` (llama.cpp, GPU-accelerated) wrapper managing a local OpenAI-compatible server, kept resident for the app session ([lib/services/llm_service.dart](lib/services/llm_service.dart))
- Chunk → per-chunk-summarize → merge summarization pipeline producing a title plus timestamped steps/insights/warnings — each step carries the `[MM:SS]` moment it came from ([lib/services/summarizer_service.dart](lib/services/summarizer_service.dart))
- Per-step frame extraction: `ffmpeg` grabs a frame at each step's timestamp ([lib/services/ffmpeg_service.dart](lib/services/ffmpeg_service.dart)'s `extractFrameAt`)
- Paginating (`pw.MultiPage`) PDF card generator: title, QR code back to the source video, each step shown next to its own frame, insights, warnings ([lib/services/pdf_service.dart](lib/services/pdf_service.dart))
- Home screen (card list) → "new card" screen (URL → download with live log) → "card detail" screen (range slider → extract frames → pick up to 6 key frames → optional preview GIF → transcribe audio → summarize with local LLM, showing each step next to its aligned frame) → PDF preview screen (print/save via the `printing` package's built-in controls) ([lib/screens/](lib/screens/))

Not yet built: the Phase 2 Android port, and any UX polish (tagging,
batch/playlist mode, re-editing a saved card).

Known limitation: if the app is killed abruptly rather than closed
normally, the `llama-server` child process can be left running in the
background holding GPU memory — no cleanup UI for this yet.

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
- [`llama.cpp`](https://github.com/ggml-org/llama.cpp) `llama-server.exe` on
  PATH (a CUDA build if you have an NVIDIA GPU, matched to your driver's
  CUDA version, plus its `cudart`/`cublas` DLLs alongside it — otherwise
  the CPU build), plus a GGUF instruct model — this repo currently
  hardcodes `C:\tools\llama-cpp\models\Qwen2.5-7B-Instruct-Q4_K_M.gguf`
  ([lib/services/llm_service.dart](lib/services/llm_service.dart)). The app
  starts/manages the server itself (127.0.0.1:8811) the first time
  summarization is used.

## Running

```
flutter pub get
flutter run -d windows
```

## Not yet set up

- Android toolchain (cmdline-tools + licenses) for the Phase 2 port

# Voice messages in chat (1.2.1)

Design and UX: hatiwal-mobile `docs/design/VOICE_MESSAGES.md`. Evidence: hatiwal-mobile
`docs/qa-1.2.1/voice/`. This file covers the API.

## Sending

`POST /api/v1/conversations/:id/messages`, multipart: `kind=voice_message`, `attachment=<file>`,
optional `client_uuid` (+ `Idempotency-Key`), exactly like a chat photo.

- Accepted containers, recognized by their leading bytes: MP4/M4A (`ftyp`), WebM/Matroska
  (EBML), Ogg (`OggS`). The phones send AAC `.m4a`; browsers send `.m4a` or WebM/Opus.
- `VoiceMessages::Transcoder` re-encodes every clip with ffmpeg to AAC-LC `.m4a`, mono, 24 kHz,
  40 kbps, faststart, no metadata — the one file every client plays (the iOS app cannot play
  WebM). From the decoded sound it measures the duration and a 64-bar waveform (0–100).
- The message stores the m4a (`audio/mp4`), `voice_duration_ms`, `voice_waveform`, and
  `body = "🎤 m:ss"` (set by the server). Apps ≤ 1.2.0 render an unknown kind as a text bubble
  with its body, so they show "🎤 0:12".
- Allowed in buyer↔seller chats and shop chats; not in Support threads (no player in the admin
  Support screen).

| Refusal | HTTP | `code` |
|---|---|---|
| no file | 422 | `voice_missing` |
| > 2 MB | 422 | `voice_too_large` (checked before ffmpeg) |
| < 1 s | 422 | `voice_too_short` |
| > 122 s (2 min + slack) | 422 | `voice_too_long` |
| not MP4/WebM/Ogg, no audio stream, undecodable, > 10 s of work | 422 | `voice_invalid` |
| ffmpeg missing or `VOICE_MESSAGES_ENABLED=0` | 503 | `voice_messages_unavailable` |
| another clip held the transcoder for 5 s | 503 + `Retry-After: 5` | `voice_busy` (retryable: the outbox sends it again) |
| > 60 voice messages / hour / user (inside the chat's 120 / hour) | 429 | `rate_limited` |

## ffmpeg hardening

The upload is untrusted input to ffmpeg:

- the container is recognized by its bytes **before** ffmpeg runs; anything else (an HLS
  playlist, an ffconcat list, random bytes) is refused unread;
- ffmpeg is given the demuxer (`-f mov|matroska|ogg`), so it never probes; `-protocol_whitelist
  file` (no network, no pipes); the mov demuxer's external references stay off (its default);
- `-nostdin`, `timeout -s KILL 10`, at most 125 s decoded, `-threads 1`, a private temp dir
  removed in `ensure`;
- **one transcode at a time per process** (`Transcoder::SLOTS = 1`): production Puma has 3
  threads with Solid Queue inside it, so three 2-minute clips at once would otherwise hold every
  thread for seconds. A second clip waits up to 5 s for the slot, then gets 503 `voice_busy`.

Specs: `spec/services/voice_messages/transcoder_spec.rb`, `spec/requests/api/v1/voice_messages_spec.rb`.

## Reading

`messages[].voice = { url, duration_ms, waveform }` on voice messages, `null` otherwise and once
deleted. The waveform is in the JSON so a bubble draws without downloading the audio; the apps
download the file only on first play.

## Delete, report, push

- Deleting a voice message (soft delete) **purges its audio**. Account or conversation
  destruction destroys the messages and purges their files.
- A voice message is reportable on its own: `POST /api/v1/reports` with `reportable_type:
  "Message"`. Only a participant on the other side of the chat (`ReportPolicy`), only a voice
  message that is not deleted (`Report`). The admin report page plays it and can warn the sender.
- Push: `push.message.voice` ("🎤 Voice message" in en/ps/fa/ur), never the audio.

## Operations

- `GET /app_config` → `features.voice_messages`: true when ffmpeg is installed and
  `VOICE_MESSAGES_ENABLED` is not `0` (kill switch, like `IMAGE_SEARCH_ENABLED`).
- The Dockerfile installs Debian's `ffmpeg` in the runtime stage. Measured on the dev image
  (same Debian 13 base, same `--no-install-recommends`): **+389 MB**.
- Cost per clip, measured on the dev box (i7-1260P, one thread): **≈ 2.0–2.2 s for a 2-minute
  clip**, ≈ 0.2–0.6 s for a typical 10–30 s one. Estimate on the 4-vCPU VPS: ≈ 3–4.5 s for 2
  minutes. It runs in the request (a Puma thread is busy that long); the 60/hour/user limit and
  the 2-minute cap bound it.
- New migration `20261030100000_add_voice_to_messages`: two nullable columns, additive.

### 1.2.1 deploy notes

- **Raise `RAILS_MAX_THREADS` to 5** (supervisor's call at deploy time; RAM is fine): with one
  thread possibly busy transcoding for ~4 s, 5 threads keep the rest of the API responsive.
- The image is +389 MB (ffmpeg); the VPS has room (55 GB free, 2026-10-30).
- Later optimisation (not 1.2.1): a static ffmpeg built with only the mov/matroska/ogg demuxers
  and the aac/opus/vorbis codecs would be a fraction of that size, at the cost of a custom build
  to maintain and patch.

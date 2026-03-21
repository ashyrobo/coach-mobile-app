# Progress

## Current Status
Core MVP loop is validated on physical iPhone: record → transcribe → rewrite/coaching works end-to-end.

Latest implementation milestone completed: separate **Realtime** tab and backend realtime relay are now integrated for speech-in/live-text-out flow.

Latest direction update: user validated physical-device run and requested a personal-use path to run without local backend-proxy dependency.

Latest stabilization update: realtime on-device transcript display has been reworked to reduce pause-related clearing, long-silence resets, and duplication artifacts; further tuning remains for rare duplicate sentence cases.

## What Works (Documented)
- Clear project vision and user flow.
- Defined rewrite modes and coaching output expectations.
- Layered architecture pattern (MVVM + Use Cases + services).
- Hybrid STT strategy (on-device first, OpenAI fallback).
- Secure API approach (backend proxy; no client-side API key exposure).
- MVP-to-production roadmap captured in memory context.
- iOS source foundation created under `ios/CoachMobileApp` with domain/data/presentation separation.
- UI flow foundation in place:
  - mode picker (`summarize`, `fullSentence`, `rewordBetter`)
  - start/stop recording
  - process session and render transcript/final text/tips
- Recording + permission services implemented using AVFoundation and Speech.
- Backend proxy foundation created under `backend-proxy` with:
  - `GET /health`
  - `POST /v1/process-audio` multipart parsing + normalized JSON response.
- Backend proxy now performs real AI processing:
  - OpenAI transcription request for uploaded audio
  - OpenAI rewrite/coaching request with mode-specific prompting
  - strict JSON normalization to `transcript`, `final_text`, `tips`, `grammar_fixes`
  - deterministic fallback response when upstream AI fails
  - `/health` reports `openai_configured`
- Added `backend-proxy/.env.example` for backend env configuration.
- Added iOS API base URL overrides (env + UserDefaults) via `AppConfig` to support physical-device LAN testing.
- Added `ios/CoachMobileApp/Info.plist.example` with microphone and speech privacy usage keys.
- End-to-end flow on real iPhone is confirmed working by user.
- Recording UX has been upgraded with explicit controls:
  - Record, Pause/Resume, Stop actions
  - live recording timer display during capture
  - paused-state handling and processing disable while capture is active
- Realtime STT plumbing has been upgraded:
  - live transcription callback now carries `isFinal` metadata (`LiveTranscriptionUpdate`)
  - ViewModel now uses finalized + partial buffers for live transcript assembly
  - pause/stop boundaries finalize current partial segment to preserve visible text
  - overlap/containment merge heuristics added to reduce repeated sentence appends
- Settings tab is now functional (no longer placeholder):
  - OpenAI credit refresh/display (best-effort)
  - OpenAI month-to-date usage refresh/display (best-effort)
  - direct OpenAI billing dashboard link
- Backend proxy now includes settings observability endpoints:
  - `GET /v1/openai-credit`
  - `GET /v1/openai-usage-month`
  - graceful fallback messaging when account/role/key scope cannot access billing/cost data
- Realtime chat lifecycle hardening is now implemented in iOS RealtimeChatViewModel:
  - session bootstrap is refreshed automatically if ephemeral client secret is expired or near expiry before connect/reconnect
  - dropped realtime WebRTC sessions trigger automatic reconnect with exponential backoff and capped retry attempts
- Realtime baseline path is now implemented end-to-end (proxy-backed):
  - iOS `Realtime` tab with Start/Stop and live text area
  - iOS realtime service streams mic audio chunks and appends text deltas in UI
  - backend `POST /v1/openai-realtime/session` created
  - backend `WS /v1/openai-realtime/ws` relay created (OpenAI Realtime forwarding)
  - realtime default model config set to `gpt-realtime`
- Realtime conversation UX/control improvements now implemented:
  - distinct realtime event types for user transcript vs assistant reply
  - delta parsing routes supported OpenAI event variants to correct stream (no mixed single buffer)
  - ViewModel now keeps separate text streams:
    - `You said`
    - `Assistant replied`
  - Realtime UI now renders two dedicated panes for those streams
  - assistant behavior instructions are now configurable via `AppConfig.realtimeAssistantInstructions`
  - `Reset Conversation` button now clears both panes and refreshes realtime session context when active
  - lifecycle stability validated with successful `xcodebuild` compile after changes
- Remote deployment posture validated at architecture level:
  - app can run on phone without localhost backend when deployed backend URL is configured (e.g., Render)
- Repo hygiene updates completed:
  - `.gitignore` now ignores `backend-proxy/node_modules/`
  - `.gitignore` now ignores `*.xcuserstate`
  - backend lockfile generation captured (`backend-proxy/package-lock.json`)
- Vocabulary learning flow has been expanded:
  - manual **spoken add** from Vocabulary tab is now implemented (mic start/stop -> OpenAI STT extraction)
  - extracted spoken input now produces structured vocabulary item data (`phrase`, `meaning`, `corrected_sentence`)
  - vocabulary detail now auto-generates comprehensive usage examples (multiple sentence contexts)
  - generated examples are cached and persisted with each vocabulary item
  - vocabulary tab header now uses compact inline title (large title removed)
- Backend proxy supports vocabulary AI endpoints:
  - `POST /v1/vocabulary/extract-from-audio`
  - `POST /v1/vocabulary/examples`
- Build validation completed after vocabulary feature implementation:
  - `node --check backend-proxy/src/server.js` passed
  - `xcodebuild` for `CoachMobileApp` simulator build passed

## What’s Left to Build
1. Confirm/document canonical iOS source path and clean duplicate folder ambiguity.
2. Ensure actual target `Info.plist` values match privacy template in committed project configuration.
3. Add transcription strategy layer (on-device first, cloud fallback) as runtime behavior.
4. Persist sessions (SwiftData) and build history browsing UI.
5. Add tests (ViewModel/use-case unit tests + backend contract tests) and basic analytics/error tracking.
6. Add optional direct-to-OpenAI iOS mode for personal prototype operation (while keeping proxy mode for security/release).
7. Continue refining realtime merge heuristics to eliminate occasional repeated sentence artifacts after long pauses/re-segmentation.
8. Run device-level validation pass for new realtime relay flow and confirm incoming OpenAI event variants are fully covered by delta parsing logic.

## Known Risks / Considerations
- Latency and quality trade-offs between local and cloud transcription.
- Prompt drift if response formatting is not strictly constrained.
- Cost control required for transcription + generation at scale.
- App Store/privacy disclosures needed for cloud audio processing.
- OpenAI billing/cost API access is inconsistent across account types and permission scopes; "credit remaining" may be unavailable even with a valid API key.
- Apple Speech partial/final segmentation can vary by pause cadence and locale, creating edge cases where live text may still duplicate unless merge logic is carefully tuned.

## Next Milestone
Move from validated MVP to durable v1 baseline: canonicalized project structure, persisted history, initial automated tests, and production-hardening of newly added realtime relay path.

## Deferred Roadmap: OpenAI Realtime Full Wiring (Future)

### Now (keep current stable behavior)
- Keep primary runtime flow for rewriting/coaching as batch processing: record -> `POST /v1/process-audio`.
- Realtime tab now provides a simple parallel mode for live transcript streaming.

### Next (when realtime implementation starts)
- Backend (partially done):
  - websocket relay path implemented: `/v1/openai-realtime/ws`
  - realtime session bootstrap implemented: `POST /v1/openai-realtime/session`
  - next: add richer relay diagnostics and capability introspection endpoint if needed
- iOS (partially done):
  - dedicated realtime streaming service implemented (connect/send audio/receive transcript deltas)
  - dedicated `Realtime` tab implemented
  - next: improve lifecycle hardening/reconnect and event compatibility coverage

### Later (hardening and polish)
- Add rewrite-only endpoint (planned: `POST /v1/rewrite-text`) so realtime transcript is not retranscribed.
- Expand websocket diagnostics and telemetry for realtime failures (reconnect baseline now implemented).
- Add regression tests ensuring Apple on-device path remains unaffected.
- Replace preview copy with live connection/capability state UX once realtime is fully wired.

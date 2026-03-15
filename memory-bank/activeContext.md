# Active Context

## Current Focus
Move from initial integration to **post-MVP stabilization** now that end-to-end iPhone flow is validated.

Latest UI/UX pass focused on:
- richer in-session recording controls (record/pause/resume/stop + live timer)
- settings observability for OpenAI account usage/cost visibility

Latest reliability pass focused on:
- stabilizing **on-device realtime transcription UX** during long pauses and pause/resume cycles

## User Preference Update (Latest)
- User successfully ran/tested app on physical iPhone.
- User wants an **independent app mode** that does not rely on `backend-proxy` for day-to-day personal use.
- User asked about embedding OpenAI key client-side for single-user usage.

## Repository Structure Note
- Multiple iOS trees currently exist in repo (`ios/CoachMobileApp`, `CoachMobileApp/CoachMobileApp 2`, and Xcode project paths).
- Next cleanup pass should confirm and document the canonical source path used for active development.

## Recent Changes
- Reworked live transcription contract in active iOS tree (`CoachMobileApp/CoachMobileApp 2`):
  - `AudioRecorderServicing.setLiveTranscriptionHandler` now sends `LiveTranscriptionUpdate { text, isFinal }`
  - `AudioRecorderService` now forwards `SFSpeechRecognizer` finalization state instead of text-only callbacks
- Reworked ViewModel live transcript assembly (`VoiceSessionViewModel`):
  - dual-buffer model: `finalizedLiveTranscript` + `currentPartialLiveTranscript`
  - composed display text avoids full-screen wipe during recognizer segment refreshes
  - pause action now promotes current partial into finalized text to keep transcript visible while paused
  - stop action finalizes remaining partial before setting transcript snapshot
  - overlap/canonicalization heuristics added to reduce duplicated sentence merges
- Added long-pause protection:
  - when recognizer emits a newly segmented partial after silence, prior partial is promoted before replacement
  - empty partial callbacks are ignored to prevent visual clearing

- Updated active iOS UX in `CoachMobileApp/CoachMobileApp 2/Presentation/Home`:
  - replaced single toggle record button with explicit **Record / Pause-Resume / Stop** controls
  - added live recording timer (`mm:ss`) and paused-state indicator
  - disabled processing while recording is active or paused
- Extended audio recording abstraction:
  - `AudioRecorderServicing` now includes `pauseRecording`, `resumeRecording`, and `currentRecordingTime`
  - `AudioRecorderService` now tracks/stores latest recording duration for stable UI display after stop
- Expanded `VoiceSessionViewModel` recording state handling:
  - explicit `idle/recording/paused` state model
  - timer updates via Combine publisher
- Replaced Settings placeholder with actionable billing/usage screen:
  - OpenAI credit display + refresh
  - OpenAI month-to-date usage display + refresh
  - direct link to OpenAI billing dashboard in Safari
- Added backend proxy support for settings observability:
  - `GET /v1/openai-credit`
  - `GET /v1/openai-usage-month`
  - graceful fallback payloads when OpenAI account/key lacks billing or org-cost API access
- Implemented iOS app scaffold under `ios/CoachMobileApp` with layered folders:
  - `Presentation/Home` (`HomeView`, `VoiceSessionViewModel`)
  - `Domain/Models` (`RewriteMode`, `RewriteResult`, `VoiceSession`)
  - `Domain/Protocols` (`AudioRecorderServicing`, `PermissionServicing`, `VoiceProcessingServicing`)
  - `Domain/UseCases` (`ProcessVoiceSessionUseCase`)
  - `Domain/Errors` (`AppError`)
  - `Data/Services` (`PermissionService`, `AudioRecorderService`, `VoiceProcessingAPIService`)
  - `Data/Config` (`AppConfig`)
- Added app entrypoint in `CoachMobileAppApp.swift` wired to `HomeView` + shared `VoiceSessionViewModel`.
- Built recording + permission flow foundation:
  - microphone permission via `AVAudioSession`
  - speech permission via `SFSpeechRecognizer`
  - audio capture to temporary `.m4a` via `AVAudioRecorder`
- Built backend proxy foundation under `backend-proxy`:
  - `POST /v1/process-audio` multipart contract endpoint
  - `GET /health` health endpoint
  - deterministic JSON response contract (`transcript`, `final_text`, `tips`, `grammar_fixes`)
- Verified backend proxy syntax with `node --check`.
- Upgraded backend proxy (`backend-proxy/src/server.js`) to real OpenAI flow:
  - transcription via `POST /v1/audio/transcriptions`
  - rewrite/coaching via `POST /v1/chat/completions`
  - mode-aware prompting for `summarize`, `fullSentence`, `rewordBetter`
  - strict JSON parsing/sanitization (`final_text`, `tips`, `grammar_fixes`)
  - fallback response path when upstream AI call fails
  - health payload now includes `openai_configured`
- Added backend env template: `backend-proxy/.env.example` with `OPENAI_API_KEY` and optional model overrides.
- Improved iOS runtime endpoint configuration in `AppConfig`:
  - default localhost for simulator
  - optional override via Xcode scheme env var `VOICE_API_BASE_URL`
  - optional override via `UserDefaults` key `voiceProcessingBaseURL`
- Added `ios/CoachMobileApp/Info.plist.example` with required privacy keys:
  - `NSMicrophoneUsageDescription`
  - `NSSpeechRecognitionUsageDescription`

## Active Decisions
- Build iOS app natively with SwiftUI for best audio/platform quality.
- Use hybrid STT strategy:
  - On-device recognition first when suitable.
  - OpenAI transcription fallback for quality/reliability.
- Standardize rewrite/coaching output as strict JSON contract.
- Keep strict normalized backend response contract even with real OpenAI integration.
- Fail safely: if upstream AI fails, return deterministic fallback payload to keep UI pipeline stable during MVP iteration.

## Immediate Next Steps
1. Document canonical iOS source-of-truth path and remove ambiguity between duplicate folders.
2. Add local history persistence (SwiftData) and history UI.
3. Add unit tests for ViewModel/use case and contract tests for backend response schema.
4. Implement/validate optional direct OpenAI mode for personal use while preserving proxy mode for secure/release path.
5. Improve settings diagnostics to distinguish: missing backend key vs restricted OpenAI role/scope vs unsupported endpoint.
6. Continue tuning realtime STT merge behavior to eliminate occasional duplicate phrase/sentence artifacts after speech segmentation changes.

## Revised Near-Term Plan
1. Add/plan a **Direct OpenAI mode** in iOS (no backend proxy) for personal prototype usage.
2. Keep backend-proxy path available as recommended secure architecture for future sharing/release.
3. Define safe-enough personal key handling pattern (non-committed config, limited-scope key, rotation).

## Prompt/Mode Guidelines (initial)
- **summarize**: concise, high-signal short output.
- **fullSentence**: convert fragmented speech into complete grammatical sentences.
- **rewordBetter**: preserve intent, improve fluency/professional tone.
- Tips should be short, actionable, and max 3–5 items.

# Active Context

## Current Focus
Execute **Phase 2 MVP runtime integration**: replace backend placeholders with real OpenAI processing and prepare device runtime configuration.

## User Preference Update (Latest)
- User successfully ran/tested app on physical iPhone.
- User wants an **independent app mode** that does not rely on `backend-proxy` for day-to-day personal use.
- User asked about embedding OpenAI key client-side for single-user usage.

## Recent Changes
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
1. Wire `Info.plist.example` values into actual Xcode target `Info.plist` and verify permission prompts on-device.
2. Start backend proxy with real `OPENAI_API_KEY` and validate `/health` + `/v1/process-audio` end-to-end.
3. Configure iPhone runtime API URL using `VOICE_API_BASE_URL` (Mac LAN IP + port).
4. Add local history persistence (SwiftData) and history UI.
5. Add unit tests for ViewModel/use case and contract tests for backend response schema.

## Revised Near-Term Plan
1. Add/plan a **Direct OpenAI mode** in iOS (no backend proxy) for personal prototype usage.
2. Keep backend-proxy path available as recommended secure architecture for future sharing/release.
3. Define safe-enough personal key handling pattern (non-committed config, limited-scope key, rotation).

## Prompt/Mode Guidelines (initial)
- **summarize**: concise, high-signal short output.
- **fullSentence**: convert fragmented speech into complete grammatical sentences.
- **rewordBetter**: preserve intent, improve fluency/professional tone.
- Tips should be short, actionable, and max 3–5 items.

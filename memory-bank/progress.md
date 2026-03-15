# Progress

## Current Status
Phase 2 started: backend now integrates real OpenAI transcription/rewrite pipeline; iOS runtime config + privacy template prepared for device testing.

Latest direction update: user validated physical-device run and requested a personal-use path to run without local backend-proxy dependency.

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

## What’s Left to Build
1. Create/commit Xcode project configuration and wire all files into target.
2. Wire iOS privacy usage descriptions into actual target `Info.plist`.
3. Validate full end-to-end flow on real iPhone with live backend key and LAN URL.
4. Add transcription strategy layer (on-device first, cloud fallback) as runtime behavior.
5. Persist sessions (SwiftData) and build history browsing UI.
6. Add tests (ViewModel/use-case unit tests + backend contract tests) and basic analytics/error tracking.
7. Add optional direct-to-OpenAI iOS mode for personal prototype operation (while keeping proxy mode for security/release).

## Known Risks / Considerations
- Latency and quality trade-offs between local and cloud transcription.
- Prompt drift if response formatting is not strictly constrained.
- Cost control required for transcription + generation at scale.
- App Store/privacy disclosures needed for cloud audio processing.

## Next Milestone
Deliver first runnable iPhone MVP by finishing Xcode target wiring/privacy keys and validating record → process → rewrite pipeline against live backend.

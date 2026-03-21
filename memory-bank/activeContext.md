# Active Context

## Current Focus
Move from initial integration to **post-MVP stabilization** now that end-to-end iPhone flow is validated.

Latest implementation pass completed:
- added a separate in-app **Realtime** tab for speech-in/live-text-out
- wired backend proxy realtime session bootstrap + websocket relay for OpenAI Realtime API (`gpt-realtime`, text-only output path)

Latest UI/UX pass focused on:
- richer in-session recording controls (record/pause/resume/stop + live timer)
- settings observability for OpenAI account usage/cost visibility

Latest reliability pass focused on:
- stabilizing **on-device realtime transcription UX** during long pauses and pause/resume cycles

## User Preference Update (Latest)
- User successfully ran/tested app on physical iPhone.
- User wants an **independent app mode** that does not rely on `backend-proxy` for day-to-day personal use.
- User asked about embedding OpenAI key client-side for single-user usage.
- User confirmed they want realtime architecture as: `iPhone mic -> OpenAI Realtime -> streamed text to UI`.
- User also wants ability to run from phone against deployed web backend (Render), independent of localhost runtime.

## Repository Structure Note
- Multiple iOS trees currently exist in repo (`ios/CoachMobileApp`, `CoachMobileApp/CoachMobileApp 2`, and Xcode project paths).
- Next cleanup pass should confirm and document the canonical source path used for active development.

## Recent Changes
- Implemented **voice-driven manual Vocabulary add** flow (proxy-backed OpenAI STT + extraction):
  - iOS vocabulary tab now has mic/stop toolbar action to capture short spoken input
  - new ViewModel state/actions in `VoiceSessionViewModel`:
    - `isVocabularyVoiceRecording`
    - `vocabularyVoiceStatusMessage`
    - `startVocabularyVoiceCapture()`
    - `stopVocabularyVoiceCaptureAndSave()`
  - voice add now calls new service contract method `extractVocabularyFromAudio(at:)`
  - extracted item is stored with richer metadata (phrase, meaning, corrected sentence)
- Implemented **on-demand vocabulary use-case sentence generation**:
  - new service contract method `generateVocabularyExamples(for:)`
  - vocabulary detail view now auto-loads examples on open
  - examples are cached in-memory and persisted in `VocabularyItem.exampleSentences`
  - `VocabularyStore.updateExamples(for:examples:)` persists generated examples
- Implemented backend-proxy vocabulary endpoints in `backend-proxy/src/server.js`:
  - `POST /v1/vocabulary/extract-from-audio`
    - transcribes uploaded audio with OpenAI STT
    - extracts `{ phrase, meaning, corrected_sentence }` via chat completion JSON contract
  - `POST /v1/vocabulary/examples`
    - generates diverse sentence examples for a given phrase via strict JSON contract
- Updated vocabulary UI compactness:
  - vocabulary screen now uses inline nav title (`.navigationBarTitleDisplayMode(.inline)`) to remove large top title space

- Implemented realtime stream separation + reset UX in active iOS tree (`CoachMobileApp/CoachMobileApp 2`):
  - `OpenAIRealtimeStreamingService.RealtimeEvent` now emits distinct events:
    - `userTranscriptDelta`
    - `assistantReplyDelta`
  - realtime delta parsing now routes supported OpenAI event types into explicit user vs assistant streams (no mixed single text buffer)
  - `session.update` now includes configurable assistant behavior instructions from `AppConfig.realtimeAssistantInstructions`
  - added `resetConversation()` in realtime service to clear session-level context by restarting realtime session when active
- Updated realtime ViewModel state in `VoiceSessionViewModel`:
  - replaced single `realtimeLiveText` with:
    - `realtimeUserTranscriptText`
    - `realtimeAssistantReplyText`
  - added `resetRealtimeConversation()` to clear both UI streams and refresh session context when realtime is running
- Updated Realtime tab UI in `HomeView`:
  - separate panes for `You said` and `Assistant replied`
  - added `Reset Conversation` button
- Added assistant behavior control config in `AppConfig`:
  - new `realtimeAssistantInstructions` sourced from env/UserDefaults with stable default chat-style coaching instruction
- Ran compile validation with `xcodebuild` for `CoachMobileApp` scheme on iOS Simulator; build succeeded.

- Implemented separate **Realtime** tab in active iOS tree (`CoachMobileApp/CoachMobileApp 2/Presentation/Home/HomeView.swift`):
  - added `Realtime` tab item with dedicated `RealtimeView`
  - simple UX: Start / Stop + status + continuously appended live text area
- Implemented Realtime UI state/actions in `VoiceSessionViewModel`:
  - new published state: `realtimeStatusMessage`, `realtimeLiveText`, `isRealtimeRunning`
  - new controls: `startRealtimeStreaming()` / `stopRealtimeStreaming()`
  - shared permission flow reused before realtime start
- Implemented minimal realtime streaming service in `Data/Services/VoiceProcessingAPIService.swift` (`OpenAIRealtimeStreamingService`):
  - starts/stops `AVAudioEngine` mic capture
  - converts buffer to PCM16 mono payload
  - sends `input_audio_buffer.append` websocket events
  - sends `session.update` constrained to text modality path
  - receives realtime delta events and forwards text chunks to ViewModel
- Implemented realtime backend support in `backend-proxy/src/server.js`:
  - added `POST /v1/openai-realtime/session` for session bootstrap
  - added websocket relay endpoint `/v1/openai-realtime/ws`
  - relays client<->OpenAI realtime events and enforces text-only modality on `session.update`
  - supports model query override with default fallback to `gpt-realtime`
- Added backend dependency `ws` in `backend-proxy/package.json`.
- Added runtime realtime config in `AppConfig.swift`:
  - `openAIRealtimeModel`
  - `realtimeSessionURL`
  - `realtimeWebSocketURL` (auto `ws/wss` conversion from base URL)
- Updated `.gitignore`:
  - ignore `backend-proxy/node_modules/`
  - ignore `*.xcuserstate`

- Hardened realtime session lifecycle in `CoachMobileApp/CoachMobileApp 2/Presentation/Home/VoiceSessionViewModel.swift` (`RealtimeChatViewModel`):
  - pre-connect ephemeral secret freshness guard now refreshes session bootstrap when secret is expired or near expiry
  - automatic reconnect on dropped realtime WebRTC path with exponential backoff (1s -> 2s -> 4s -> 8s -> 16s, capped retries)
  - reconnect scheduling is canceled/reset on manual disconnect and on successful reconnect
  - debug event stream now captures secret refresh and reconnect lifecycle transitions
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
4. Validate realtime tab against deployed backend (Render) on physical iPhone and capture any event-shape mismatches in delta parsing.
5. Implement/validate optional direct OpenAI mode for personal use while preserving proxy mode for secure/release path.
6. Improve settings diagnostics to distinguish: missing backend key vs restricted OpenAI role/scope vs unsupported endpoint.
7. Continue tuning realtime STT merge behavior to eliminate occasional duplicate phrase/sentence artifacts after speech segmentation changes.

## Revised Near-Term Plan
1. Add/plan a **Direct OpenAI mode** in iOS (no backend proxy) for personal prototype usage.
2. Keep backend-proxy path available as recommended secure architecture for future sharing/release.
3. Define safe-enough personal key handling pattern (non-committed config, limited-scope key, rotation).

## Prompt/Mode Guidelines (initial)
- **summarize**: concise, high-signal short output.
- **fullSentence**: convert fragmented speech into complete grammatical sentences.
- **rewordBetter**: preserve intent, improve fluency/professional tone.
- Tips should be short, actionable, and max 3–5 items.

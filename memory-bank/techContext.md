# Technical Context

## Stack in Use (Current)
- **Client**: iOS native app (SwiftUI)
- **Language**: Swift 5.9+
- **Architecture**: MVVM + Use Cases + protocol-based services
- **Audio/Speech**:
  - AVFoundation (`AVAudioRecorder`, speech synthesis)
  - Apple Speech framework (permissions + local speech support where used)
- **Networking**: `URLSession` + `Codable`
- **Backend**: Node.js HTTP server (`backend-proxy/src/server.js`)
- **AI Provider**: OpenAI APIs (transcription + chat completions)

## Runtime Topology
- iOS app calls backend proxy endpoints for rewrite, vocabulary, practice, and observability.
- Backend proxy holds `OPENAI_API_KEY` and forwards requests to OpenAI.
- Default configured backend base URL currently points to deployed Render service via `AppConfig.defaultBaseURL`.

## iOS Configuration Notes
- `AppConfig.voiceProcessingBaseURL` resolution order:
  1. env `VOICE_API_BASE_URL`
  2. `UserDefaults` override (`voiceProcessingBaseURL`)
  3. built-in default URL
- Rewrite transcription method setting currently uses `TranscriptionMethod.appleOnDevice` naming, but active rewrite pipeline is backend-proxy driven.
- Active rewrite modes: `summarize`, `rewordBetter`.

## Backend API Surface (Implemented)

### Health / Settings
- `GET /health`
- `GET /v1/openai-credit`
- `GET /v1/openai-usage-month`

### Rewrite / Coaching
- `POST /v1/process-audio`

### Vocabulary
- `GET /v1/vocabulary/cloud`
- `PUT /v1/vocabulary/cloud`
- `POST /v1/vocabulary/extract-from-audio`
- `POST /v1/vocabulary/examples`
- `POST /v1/vocabulary/speaking-mission`

### Interview Practice
- `POST /v1/interview/behavioral/question`
- `POST /v1/interview/behavioral/evaluate`

## Persistence
- iOS local persistence currently uses JSON files (history + vocabulary) in documents directory.
- `UserDefaults` stores reminder settings, daily counters, and lightweight app preferences.
- Backend cloud vocabulary persistence currently uses file-backed JSON (`data/cloud-vocabulary.json`).

## Security / Operational Constraints
- API keys must stay server-side for shared/release usage.
- Strict JSON response shaping is required to keep decoding deterministic.
- Billing/cost endpoints may fail due to account/org/key limitations; app/backend should continue with fallback messaging.
- For deployed phone usage, HTTPS backend connectivity is required.

## Known Technical Debt
1. Clarify naming/semantics around transcription method selection versus actual runtime behavior.
2. Duplicate iOS source trees still exist in repo and should be further consolidated/documented.
3. Automated test coverage remains limited for ViewModel logic and backend contract checks.

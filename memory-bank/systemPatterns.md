# System Patterns

## Architecture Style
The app uses a layered structure with **MVVM + service protocols**:
- **Presentation**: SwiftUI views + `VoiceSessionViewModel`
- **Domain**: models/protocols/use cases (`ProcessVoiceSessionUseCase`)
- **Data**: concrete services (`AudioRecorderService`, `PermissionService`, `VoiceProcessingAPIService`)

This keeps UI state orchestration centralized while external integrations remain swappable/testable.

## Core Product Pipelines

### 1) Voice Rewrite/Coaching Pipeline
`Record Audio -> backend transcription -> rewrite/coaching JSON -> render + persist session`

- iOS uploads multipart audio + mode (+ optional tone)
- backend proxy calls OpenAI transcription + chat completion
- backend returns normalized contract
- ViewModel saves session via `SessionHistoryStore`

### 2) Vocabulary Learning Pipeline
`Voice/Manual capture -> vocabulary item -> examples/practice/sync`

- extraction from audio via backend endpoint
- item persisted in local `VocabularyStore`
- optional example generation per item
- flashcard scheduling fields tracked on each item
- cloud vocabulary sync via `GET/PUT /v1/vocabulary/cloud`

### 3) Speaking Practice Pipeline
Three modules share similar pattern: generate/select prompt -> capture speech -> transcribe/evaluate -> feedback.

- **Shadowing**: phrase replay + spoken attempt evaluation
- **Mission**: backend-generated mission from vocabulary phrases + local coverage feedback
- **Behavioral Interview**: backend question generation + backend STAR/rubric evaluation

## State & Persistence Patterns
- `VoiceSessionViewModel` is the central orchestrator for recording, processing, vocabulary, and practice states.
- `SessionHistoryStore` uses JSON file persistence + recording file management in app documents directory.
- `VocabularyStore` uses JSON file persistence and tracks spaced review metadata per card.
- `UserDefaults` stores lightweight counters/settings (daily review counters, reminder time/toggles, selection prefs).

## API Contract Patterns

### Rewrite
`POST /v1/process-audio` (multipart)
```json
{
  "title": "string",
  "transcript": "string",
  "final_text": "string",
  "tips": ["string"],
  "grammar_fixes": ["string"]
}
```

### Vocabulary
- `POST /v1/vocabulary/extract-from-audio`
- `POST /v1/vocabulary/examples`
- `GET /v1/vocabulary/cloud`
- `PUT /v1/vocabulary/cloud`
- `POST /v1/vocabulary/speaking-mission`

### Interview Coaching
- `POST /v1/interview/behavioral/question`
- `POST /v1/interview/behavioral/evaluate`

### Settings Observability
- `GET /v1/openai-credit`
- `GET /v1/openai-usage-month`

## Key Design Decisions (Current)
1. Backend proxy is the default architecture for API key safety and normalized contracts.
2. Realtime streaming paths are removed from active codebase.
3. Rewrite scope is currently `summarize` and `rewordBetter` (+ tone for rewording).
4. Product emphasis extends beyond rewrite into retention/practice loops (vocabulary + speaking/interview).

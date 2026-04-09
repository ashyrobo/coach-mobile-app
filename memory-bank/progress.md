# Progress

## Current Status
Project is in a stable post-MVP phase: the core voice rewrite flow is validated on physical iPhone, and the product has expanded into vocabulary retention and speaking/interview practice modules.

## What Works

### Core Voice Flow
- Record -> process -> rewrite/coaching flow works end-to-end.
- Rewrite modes currently implemented:
  - `summarize`
  - `rewordBetter` (with selectable tone)
- Session results include transcript, final text, tips, and grammar fixes.

### App Surface
- Active tabs in `HomeView`:
  - Record
  - Vocabulary
  - Practice
  - History
  - Settings

### Vocabulary
- Manual vocabulary capture from voice input via backend extraction endpoint.
- Vocabulary examples generation per phrase.
- Flashcard scheduling and review metadata on items.
- Practice queue with ratings-driven scheduling.
- Cloud vocabulary sync through backend (`GET/PUT /v1/vocabulary/cloud`).
- Reminder settings/cadence controls integrated in app state.

### Practice Features
- Shadowing module with speech capture and scoring feedback.
- Shadowing prompt generation now supports backend OpenAI TTS + local cached playback fallback path.
- Speaking mission generation + completion feedback.
- Behavioral interview module:
  - question generation by category
  - spoken answer capture
  - STAR coverage + rubric evaluation + improved answer + follow-up questions

### History / Persistence
- Session history persistence implemented with local JSON + audio file storage.
- Vocabulary persistence implemented with local JSON store.

### Backend Proxy
- Node backend proxy is active and provides rewrite, vocabulary, interview, and observability endpoints.
- OpenAI integration in place for transcription and completion-based coaching tasks.
- Added combined shadowing prompt + neural TTS endpoint: `POST /v1/practice/shadowing-prompt-with-audio`.

### Removed / Deprecated
- Realtime streaming architecture and related iOS/backend wiring have been removed from active code paths.

## In Progress / Remaining
1. Keep memory-bank docs synchronized with active implementation details.
2. Expand automated tests:
   - iOS ViewModel/use case coverage
   - backend contract/shape validation
3. Resolve remaining repo ambiguity around duplicate iOS trees.
4. Clarify/refactor transcription method configuration naming to match actual behavior.

## Risks / Considerations
- OpenAI billing/usage endpoint availability varies by account/org permissions.
- Cost/latency must be monitored for frequent transcription + generation usage.
- Privacy disclosures remain important for cloud audio/text processing.

## Next Milestone
Move from stable feature-rich prototype to durable v1 baseline through stronger test coverage, clearer project structure, and tightened configuration semantics.

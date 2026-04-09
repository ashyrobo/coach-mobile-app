# Active Context

## Current Focus
Consolidate the project into a stable post-MVP baseline with reliable daily-use flows:
- voice rewrite/coaching
- vocabulary capture + review
- speaking/interview practice
- history and cloud vocabulary sync

## Canonical Source Paths (Current)
- Active iOS target source is under: `CoachMobileApp/CoachMobileApp 2/...`
- Xcode project references this tree via `CoachMobileApp.xcodeproj` groups.
- Backend proxy is under: `backend-proxy/src/server.js`.

## User-Validated Direction
- Physical iPhone flow is validated.
- App should be usable from phone against deployed backend (not localhost-only).
- Backend-proxy architecture remains primary for key safety.

## Recent Significant Change (Practice TTS)
- Added combined shadowing generation + neural TTS flow for Practice tab.
- Backend now supports `POST /v1/practice/shadowing-prompt-with-audio`.
- iOS now requests paragraph + audio together, caches returned audio locally, and plays cached audio first.
- Fallback behavior remains intact:
  - If cloud TTS fails, paragraph-only flow still works.
  - Local `AVSpeechSynthesizer` playback still works as backup.

## Confirmed Current Feature Set
- Realtime feature set is removed from active iOS and backend paths.
- Main app tabs: `Record`, `Vocabulary`, `Practice`, `History`, `Settings`.
- Rewrite modes in active model:
  - `summarize`
  - `rewordBetter` (with tone controls: professional/casual/friendly/confident/polite)
- Vocabulary system includes:
  - manual voice add via backend extraction
  - generated examples per phrase
  - local flashcard states + spaced review scheduling
  - cloud sync (`GET/PUT /v1/vocabulary/cloud`)
  - daily reminder scheduling in app settings
- Practice system includes:
  - shadowing capture/evaluation
  - speaking mission generation/evaluation
  - behavioral interview question generation + STAR/rubric-based evaluation
- Settings includes OpenAI billing/usage observability endpoints via backend.

## Active Architecture Notes
- iOS remains MVVM + service-protocol driven.
- Persistence currently uses local JSON stores (`SessionHistoryStore`, `VocabularyStore`) + `UserDefaults` for counters/settings.
- Backend provides normalized AI contracts for rewrite, vocabulary, and interview workflows.

## Immediate Next Steps
1. Keep memory-bank docs synchronized with current implementation (no stale realtime/fullSentence references).
2. Add/expand automated tests for ViewModel logic and backend response contracts.
3. Clarify naming/config around transcription method (current enum naming vs proxy behavior).
4. Continue repo cleanup to reduce duplicate iOS tree ambiguity.

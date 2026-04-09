# Project Brief

## Product
**Coach Mobile App** — an iOS app that helps users turn spoken English into clearer written output, with short coaching feedback.

## Core Flow
1. Record speech in-app.
2. Transcribe spoken input.
3. Rewrite by mode (`summarize`, `rewordBetter`) with optional tone control.
4. Show final text + coaching tips.
5. Save useful outputs and vocabulary for later review/practice.

## Scope (Current)
- iOS-first, SwiftUI native app.
- Fast MVP UX, stable processing pipeline.
- OpenAI-backed rewriting/coaching.
- Vocabulary learning support is active (capture + examples + flashcards + practice modules).
- Behavioral interview and speaking-practice coaching are active product areas.

## Success Criteria
- Reliable and fast record → result flow.
- Clearly distinct rewrite mode behavior (`summarize`, `rewordBetter`).
- Practical, concise coaching tips.
- Safe secret handling (proxy for shared/release usage; careful local handling for personal mode).

## Current Validation
- End-to-end flow is validated on physical iPhone.
- Build/runtime includes active backend-proxy integration for transcription, rewrite/coaching, vocabulary, and interview practice APIs.

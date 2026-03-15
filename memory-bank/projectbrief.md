# Project Brief: Smart Voice Assistant iPhone App

## Project Name
Coach Mobile App (Smart Voice Assistant)

## Vision
Build an iPhone app that helps users improve spoken/written English by transforming recorded speech into clearer output with coaching guidance.

## Core User Flow
1. User records audio in-app.
2. App transcribes speech to text.
3. App rewrites text based on selected mode:
   - Summarize
   - Full sentence
   - Reword better
4. App displays final response with English coaching tips.
5. Session can be saved to history.

## Scope
- iOS-first (native SwiftUI).
- MVP optimized for speed and quality.
- Hybrid AI approach: on-device first where possible, cloud fallback (OpenAI) for quality and advanced rewriting/coaching.

## Success Criteria
- Recording/transcription/rewrite pipeline is reliable and fast.
- Rewrite modes produce clearly distinct outputs.
- Coaching tips are useful, concise, and actionable.
- Privacy and API key security follow production-safe patterns.

## Validation Snapshot
- MVP core loop has been validated on a physical iPhone (record → transcribe → rewrite/coaching).

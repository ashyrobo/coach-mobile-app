# System Patterns

## Architecture Style
Use **layered modular architecture** with **MVVM + Use Cases**:
- Presentation Layer (SwiftUI Views + ViewModels)
- Domain Layer (Use Cases / business rules)
- Data Layer (service implementations: audio, speech-to-text, AI rewrite, persistence)

This structure supports fast MVP delivery while keeping logic testable and scalable.

## Core Pipeline Pattern
`Record Audio -> Transcribe -> Rewrite by Mode -> Generate Coaching Tips -> Render + Save`

### Components
- `AudioRecorderService` (AVFoundation)
- `SpeechToTextService` (strategy-based)
  - `OnDeviceSTTProvider` (Apple Speech framework)
  - `CloudSTTProvider` (OpenAI transcription fallback)
- `RewriteAndCoachingService` (OpenAI chat/completions with JSON schema output)
- `SessionRepository` (SwiftData for local history)

## Key Design Decisions
1. **Hybrid STT strategy**: prefer on-device first, cloud fallback for quality/reliability.
2. **Structured AI response**: model must return strict JSON for deterministic UI parsing.
3. **Server-side key management**: iOS app talks to backend proxy, never embeds OpenAI key.
4. **Mode-driven prompting**: each rewrite mode has dedicated prompt instructions and examples.

## Suggested Domain Models
- `RewriteMode` enum: `.summarize`, `.fullSentence`, `.rewordBetter`
- `VoiceSession`
  - id, createdAt
  - audioPath
  - transcriptText
  - finalText
  - coachingTips: [String]
  - mode
- `RewriteResult`
  - finalText
  - tips
  - optional grammarFixes

## API Contract Pattern
Backend endpoint (example): `POST /v1/process-audio`
- Input: multipart audio + rewrite mode
- Output JSON:
```json
{
  "transcript": "...",
  "final_text": "...",
  "tips": ["...", "...", "..."],
  "grammar_fixes": ["..."]
}
```

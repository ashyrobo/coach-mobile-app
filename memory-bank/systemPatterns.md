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
  - supports start/pause/resume/stop and exposes current recording time for live UI timers
  - emits structured live transcription updates (`text`, `isFinal`) from Apple Speech callbacks
- `SpeechToTextService` (strategy-based)
  - `OnDeviceSTTProvider` (Apple Speech framework)
  - `CloudSTTProvider` (OpenAI transcription fallback)
- `RewriteAndCoachingService` (OpenAI chat/completions with JSON schema output)
- `SessionRepository` (SwiftData for local history)
- `Settings/Billing Observability` (proxy-backed OpenAI credit + usage checks with graceful fallback)

## Key Design Decisions
1. **Hybrid STT strategy**: prefer on-device first, cloud fallback for quality/reliability.
2. **Structured AI response**: model must return strict JSON for deterministic UI parsing.
3. **Server-side key management (default/release)**: iOS app should talk to backend proxy; avoid embedding OpenAI key in distributed builds.
   - **Dev-only exception**: temporary direct OpenAI mode may be used for personal local prototype usage with non-committed secrets and strict key limits/rotation.
4. **Mode-driven prompting**: each rewrite mode has dedicated prompt instructions and examples.
5. **Live transcript assembly pattern**:
   - maintain separate `finalized` and `partial` buffers in ViewModel
   - compose display as `finalized + partial`
   - promote partial to finalized on explicit pause/stop boundaries
   - apply overlap-aware merge heuristics to reduce duplication during recognizer re-segmentation

## Realtime STT Buffering Pattern (Current)
- Speech callbacks can re-segment text after silence and may not always include prior words.
- To avoid visual wipe-outs and duplication:
  1. keep `finalizedLiveTranscript` and `currentPartialLiveTranscript`
  2. on `isFinal`, merge incoming into finalized and clear partial
  3. on partial updates, preserve prior text when incoming callback is empty or newly segmented
  4. merge with containment/overlap checks before appending
- Final transcript used at stop should prefer finalized buffer snapshot before backend processing result replaces it.

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

Additional settings observability endpoints (best-effort):
- `GET /v1/openai-credit` → `{ remainingUSD: number|null, message: string|null }`
- `GET /v1/openai-usage-month` → `{ monthToDateUSD: number|null, message: string|null }`

These are intentionally resilient to account/role limitations and should return user-facing fallback messages when OpenAI billing/cost APIs are unavailable.

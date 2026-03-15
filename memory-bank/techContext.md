# Technical Context

## Recommended Stack
- **Client**: iOS native app with SwiftUI
- **Language**: Swift 5.9+
- **Architecture**: MVVM + Use Cases + service protocols
- **Audio**: AVFoundation (`AVAudioRecorder` / `AVAudioEngine`)
- **Speech Recognition (local)**: Apple Speech framework
- **AI Cloud**: OpenAI (transcription fallback + rewrite/coaching)
- **Local Persistence**: SwiftData (or Core Data if needed)
- **Networking**: URLSession + Codable

## Backend Proxy (for API key safety)
Preferred lightweight options:
- Supabase Edge Functions
- Cloudflare Workers
- Firebase Functions

Responsibilities:
- Store OpenAI API key server-side
- Validate requests from app
- Forward transcription/rewrite requests to OpenAI
- Return normalized JSON contract to iOS app

## Operational Constraints
- Never hardcode OpenAI key in iOS bundle.
- Keep model responses in strict JSON to prevent parsing failures.
- Optimize for latency with small prompts and limited tip count.
- Request microphone and speech permissions with clear rationale text.

## Personal Prototype Exception (Documented)
- User is currently single-user and requested an independent app path without backend-proxy.
- For this temporary mode, direct OpenAI calls from iOS are acceptable only with risk awareness:
  - key can be extracted from the app binary/runtime,
  - usage abuse is possible if app is shared/leaked,
  - key rotation and spending limits are strongly recommended.
- Preferred compromise: store key outside source control and inject via runtime config for local/dev builds.

## Privacy + Compliance Notes
- Minimize transmitted data (only required audio/text).
- Add user disclosure for cloud processing.
- Consider optional local-only mode in later phase.

## Testing Strategy (initial)
- Unit test use cases with mocked services.
- Contract test backend JSON schema.
- Manual device testing for record/transcribe/rewrite loop.



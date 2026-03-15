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
- Optionally provide best-effort billing/usage summaries for in-app settings visibility

## Operational Constraints
- Never hardcode OpenAI key in iOS bundle.
- Keep model responses in strict JSON to prevent parsing failures.
- Optimize for latency with small prompts and limited tip count.
- Request microphone and speech permissions with clear rationale text.
- OpenAI billing/usage endpoints are not uniformly available for every account type, org role, or key scope.
- In-app billing/usage UI must tolerate restricted endpoints and present fallback messaging.

## Personal Prototype Exception (Documented)
- User is currently single-user and requested an independent app path without backend-proxy.
- For this temporary mode, direct OpenAI calls from iOS are acceptable only with risk awareness:
  - key can be extracted from the app binary/runtime,
  - usage abuse is possible if app is shared/leaked,
  - key rotation and spending limits are strongly recommended.
- Preferred compromise: store key outside source control and inject via runtime config for local/dev builds.

### Personal Mode Secret Injection Pattern
- Do not commit keys in source, plist, or tracked xcconfig files.
- Keep a local-only config file (e.g., untracked `.xcconfig`) or Xcode scheme environment variable for API key/base URL injection during local runs.
- Add `.example` templates only, and ensure real secret files are ignored by `.gitignore`.
- Use restricted/rotated API keys with spending limits.

## Privacy + Compliance Notes
- Minimize transmitted data (only required audio/text).
- Add user disclosure for cloud processing.
- Consider optional local-only mode in later phase.

## Testing Strategy (initial)
- Unit test use cases with mocked services.
- Contract test backend JSON schema.
- Manual device testing for record/transcribe/rewrite loop.

## Implemented Settings Observability (Current)
- iOS Settings screen now includes:
  - OpenAI credit display + refresh
  - OpenAI month-to-date usage display + refresh
  - direct link to OpenAI billing dashboard
- Backend proxy endpoints:
  - `GET /v1/openai-credit`
  - `GET /v1/openai-usage-month`
- Both endpoints are best-effort and designed to return friendly fallback messages when upstream access is restricted.



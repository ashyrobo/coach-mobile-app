# Coach Mobile App — First MVP Run on iPhone

This checklist gets you from current code to first end-to-end iPhone run.

## 1) Backend setup (Mac)

From project root:

```bash
cd /Users/ashkan/Downloads/HW_projects/coach_mobile_app/backend-proxy
cp .env.example .env
```

Edit `.env` and set:
- `OPENAI_API_KEY=...`

Run backend:

```bash
npm run dev
```

Verify health:

```bash
curl http://127.0.0.1:8787/health
```

Expected: JSON with `status: "ok"` and `openai_configured: true`.

---

## 2) iOS target privacy config (Xcode)

Add to the app target `Info.plist` (use values from `ios/CoachMobileApp/Info.plist.example`):

- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`

Without these keys, recording/transcription permissions will fail.

---

## 3) iPhone networking config

Find your Mac LAN IP (example `192.168.1.23`).

In Xcode scheme for the iOS app, add environment variable:

- `VOICE_API_BASE_URL = http://<MAC_LAN_IP>:8787`

Example:
- `VOICE_API_BASE_URL = http://192.168.1.23:8787`

Notes:
- iPhone and Mac must be on same Wi-Fi.
- Backend must be running when app sends requests.

---

## 4) Run on physical iPhone

1. Connect iPhone to Mac and trust device.
2. Enable Developer Mode on iPhone if prompted.
3. In Xcode, select your Apple Team/signing for app target.
4. Choose iPhone as run destination.
5. Build and run.

Test flow:
- Select mode
- Start Recording → Stop Recording
- Tap Process Session
- Confirm transcript + final text + tips appear

---

## Current blocker to fully "one-click runnable MVP"

The repo still needs final Xcode project/target wiring confirmation (`.xcodeproj`/target membership + final `Info.plist` in target). Once that is done, this runbook should work end-to-end.

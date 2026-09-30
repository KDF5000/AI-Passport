<p align="right"><a href="README.zh_CN.md">简体中文</a> · <strong>English</strong></p>

# AI Guide Companion

AI Guide Companion is an offline-first travel assistant made of an iOS/Android
phone app and FoloToy AI Passport firmware. The phone plans and stores a trip,
uses AI only when explicitly requested, and handles network access. Passport is
the low-distraction route display, microphone, and speaker.

The current implementation supports:

- AI-generated itineraries for a destination, date, visit window, pace, and
  party profile;
- user-confirmed performances and reservations as immutable scheduling
  constraints;
- a review step before an AI draft becomes the saved trip;
- per-stop summaries, spoken guide scripts, field tips, assumptions, and
  information that must be verified before departure;
- locally persisted itinerary and completion progress;
- optional pre-generated audio cached on the phone for offline playback;
- contextual AI questions from either the phone or Passport;
- BLE route synchronization, voice input, streamed answer text, and audio
  playback on Passport.

This is not a live map or ticketing service. AI-generated schedules are
planning suggestions. Opening hours, admission rules, performance times, and
temporary notices must still be checked against the venue's official source.

## Repository layout

- `mobile/`: Flutter app, developed and device-tested on iPhone; the codebase
  also targets Android.
- `passport/`: ESP-IDF firmware for FoloToy AI Passport.
- `protocol/`: versioned BLE packet contract shared by both sides.

## How a trip is created

1. Enter the destination, date, arrival/departure time, pace, and party needs.
2. Add only performances, tickets, or reservations that the user has already
   confirmed. Their names and times become hard constraints.
3. The phone makes one structured AI request to create candidate stops, a
   chronological route, short Passport summaries, full guide scripts, and
   verification items.
4. Review the draft. Non-fixed stops can be reordered or removed; confirmed
   events cannot be silently changed by AI.
5. Save the trip locally, optionally prepare offline audio, then connect and
   sync it to Passport.

Route generation may take longer than an ordinary chat response because it
returns all guide scripts in one structured result. The progress page displays
elapsed time and allows cancellation without clearing the form.

## Required services and access

Two independent service groups are used. Credentials must belong to the same
environment and region as the endpoints being called.

### 1. Volcengine Ark: itinerary generation and questions

Apply for or prepare:

1. A Volcengine account with Ark access in the **CN production region**.
2. A chat-capable model deployment/inference endpoint that supports the
   Chat Completions API, JSON-object responses, and streaming.
3. An Ark API key authorized to call that endpoint.
4. Sufficient output-token and request-time quotas. Itinerary generation can
   return several thousand tokens.

In the phone app, open **Settings** and enter:

- **Ark model / Endpoint**: the endpoint ID shown by Ark, commonly beginning
  with `ep-`;
- **Ark API Key**: the corresponding API key.

The app currently calls the CN Ark base URL
`https://ark.cn-beijing.volces.com/api/v3` and `/chat/completions`. If a private
proxy is used, the phone must already be able to reach it, for example through
an active VPN. Never put a proxy credential in this repository.

### 2. ByteDance Speech/SAIL: speech recognition and synthesis

Ask the Speech/SAIL service owner to create or authorize one application in the
**CN production environment** with all of the following:

- an application-level **AppKey**;
- an application-scoped **Access Key (AK)** and **Secret Key (SK)**;
- streaming large-model ASR access, using resource
  `asr.streaming.model.big` (or the authorized two-pass variant);
- SAIL/SAMI TTS access for the selected Chinese voice;
- request-rate quota appropriate for conversational TTS. The app serializes
  synthesis requests and retries one rate-limit response, but cannot bypass the
  service quota.

Enter the resulting **Speech AppKey**, **Speech AK**, and **Speech SK** in the
phone settings. The CN ASR endpoint
`wss://speech.bytedance.com/api/v3/sauc/v2/bigmodel_async` (the client-facing
external endpoint), resource IDs, and default voice are already configured in
the app. A bad ASR URL saved by an older build is migrated automatically at
startup.

`UserNotFound` / `40200141` normally means the AppKey or credentials belong to
a different environment or region, such as BOE credentials being sent to the
CN production endpoint. Confirm the region and application binding instead of
rotating keys blindly.

The Ark key and Speech AK/SK are different credentials and are not
interchangeable. Do not commit either set. The phone stores secrets through the
platform secure-storage API and never sends them to Passport.

## Build and run

### Phone

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run -d <device-id> --profile
```

Use profile or release mode for an iPhone build that can be opened later from
the Home Screen. An iOS debug build can only launch while attached to Flutter
tooling or Xcode.

### Passport

Use ESP-IDF 5.5.3:

```bash
cd passport
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
idf.py -p <serial-port> flash monitor
```

Flashing is a hardware write. Confirm the target port and intended image before
running it.

## Use

1. Configure both service groups in phone settings.
2. Create, review, and save a trip. Route browsing and progress are immediately
   local; guide audio is not synthesized automatically.
3. In **Offline pack**, explicitly cache missing guide audio while connectivity
   is reliable. The same stop text and voice reuse the cached file.
4. Power on Passport, connect to `Passport Guide`, and sync the route.
5. On Passport, use UP/DOWN to change stops, OK to play a cached guide,
   double-press OK to toggle completion, and hold OK to record a question.
   During playback, UP/DOWN changes volume and OK stops.

If Passport is disconnected, cached guides can still play through the phone.
After the app has connected to Passport, iOS can keep that BLE session active
while the phone is locked. A Passport voice question receives a bounded
background-processing window for ASR, AI, TTS, and BLE playback. iOS may still
suspend long work; network or VPN loss interrupts online questions, and
force-quitting the app from the app switcher disables lock-screen relay until
the app is opened and connected again.

## Network and cost boundaries

No network request is made when browsing a saved route, changing stops,
recording completion, replaying cached audio, or resuming the app. Network is
used only when the user:

- generates a new itinerary;
- explicitly asks AI;
- explicitly prepares missing offline guide audio.

This boundary reduces service usage and keeps the core trip usable under weak
network conditions.

## Validation

Phone checks:

```bash
cd mobile
flutter analyze
flutter test
```

Firmware checks:

```bash
cd passport
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
```

Live Speech integration tests are opt-in and read credentials only from
environment variables:

```bash
RUN_SAIL_LIVE=1 \
SAIL_APP=<appkey> \
SAIL_AK=<access-key> \
SAIL_SK=<secret-key> \
flutter test test/sail_live_integration_test.dart
```

Never commit API keys, AK/SK pairs, private proxy URLs, device secrets, or
unsanitized logs.

<p align="right"><a href="README.zh_CN.md">简体中文</a> · <strong>English</strong></p>

# AI Guide Companion Mobile App

This Flutter app owns itinerary generation, trip persistence, offline guide
audio, AI conversations, and the BLE session with FoloToy AI Passport. The
phone provides the network path; API credentials never leave the phone.

See the [application README](../README.md) for the complete product flow,
service-access checklist, credential fields, Passport controls, and offline
policy.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d <device-id> --profile
```

The app has been exercised on iPhone. Android uses the same Flutter code but
still requires platform-specific acceptance testing.

Use profile or release mode when an iPhone build must launch independently
from the Home Screen. Debug builds require an active Flutter/Xcode development
session on iOS 14 and later.

On iOS, connect Passport before locking the phone. The app opts into BLE
Central restoration and protects each Passport voice question with a bounded
background task. This supports lock-screen relay but not indefinite execution:
iOS may suspend long work, network or VPN loss interrupts online requests, and
force-quitting the app disables relay until it is reopened and reconnected.

## Runtime configuration

Open **Settings** and provide:

- Ark model/endpoint ID and Ark API key for route generation and questions;
- Speech AppKey, AK, and SK for streaming ASR and SAIL/SAMI TTS.

Application portals:

- [Volcengine Ark Console](https://ark.bytedance.net): enable a chat model,
  create an inference endpoint, and obtain its `ep-...` ID and API key;
- [Speech/SAIL Application Management](https://speech.bytedance.net/sail/cn/self/app):
  create or select a CN application, request streaming ASR and SAIL/SAMI TTS
  access, and obtain its AppKey, AK, and SK.

Settings are grouped into **LLM API** and **Speech API** sections. The LLM
section pre-fills the complete Volcengine Ark CN Chat Completions URL and allows
it to be replaced with a compatible custom address. Speech pre-fills the
standard Speech streaming-ASR WebSocket endpoint and SAIL/SAMI TTS HTTP
endpoint, and allows either endpoint to be replaced with a compatible custom
service. The SAIL token URL is derived from the configured TTS endpoint by
replacing its final path segment with `token`.

A custom LLM service must support OpenAI-compatible Chat Completions requests
and streaming responses. Obtain all credentials from the corresponding service
owner and keep the application, credentials, and endpoint region aligned.
Secrets are stored with `flutter_secure_storage`; non-secret preferences use
shared preferences.

The app expects synthesized audio that can be decoded as 16 kHz, 16-bit, mono
PCM/WAV before it is converted to the Passport streaming format.

## Optional live Speech tests

Normal tests never require real credentials. To exercise the authorized SAIL
application explicitly:

```bash
RUN_SAIL_LIVE=1 \
SAIL_APP=<appkey> \
SAIL_AK=<access-key> \
SAIL_SK=<secret-key> \
flutter test test/sail_live_integration_test.dart
```

Pass credentials only as local environment variables. Do not add them to Dart
source, test fixtures, shell scripts, `.env` files tracked by Git, screenshots,
or issue logs.

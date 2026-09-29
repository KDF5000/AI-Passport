<p align="right"><a href="README.zh_CN.md">简体中文</a> · <strong>English</strong></p>

# AI Guide Companion MVP

This application validates one complete voice turn between AI Passport and a
phone. Hold OK on Passport to record, release to send compressed audio over
BLE, let the phone call configurable speech/LLM services through its own
network or VPN, then read and hear the response on Passport.

The project is intentionally split into:

- `passport/`: ESP-IDF firmware and host tests;
- `mobile/`: Flutter app targeting iOS first and Android with the same code;
- `protocol/`: versioned BLE packet contract.

Route planning, destination data, maps, location, and user accounts are outside
this MVP.

## Quick start

1. Build and flash the firmware in `passport/`, then run `mobile/` on iOS or
   Android.
2. Configure an OpenAI-compatible base URL, STT/chat/TTS paths, model names,
   and API key in the phone settings. The key is stored in platform secure
   storage.
3. Tap **Scan and connect** and select the device advertised as
   `Passport Guide`.
4. When Passport shows Ready, hold OK to speak and release to send. Transcript
   and answer appear on both screens, and Passport plays the answer. Press OK
   during playback to stop it.

The phone uses its own network, including an already working iPhone VPN. The
current TTS endpoint must return 16 kHz, 16-bit, mono PCM WAV. Keep the app in
the foreground; background BLE is intentionally outside this MVP.

## Validation

```bash
cd mobile
flutter analyze
flutter test

cd ../passport
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
```

Never commit API keys, personal proxy URLs, or unsanitized logs.

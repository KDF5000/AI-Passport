<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# AI Guide Companion Mobile App

This Flutter app is the network and AI bridge for the Passport AI Guide MVP.
It receives speech from the Passport over Bluetooth Low Energy, calls
OpenAI-compatible speech-to-text, chat, and text-to-speech endpoints through
the phone's network connection, then returns the answer text and audio to the
Passport.

## Run

1. Install Flutter and prepare an iOS or Android development device.
2. Run `flutter pub get` in this directory.
3. Start the app with `flutter run`.
4. Enter the base URL, endpoint paths, model names, voice, and API key for your
   provider. The API key is stored with the platform's secure storage.
5. Power on the Passport firmware, tap **Connect**, and select
   `Passport Guide`.

Keep the app in the foreground during this MVP. The phone may use its normal
mobile data, Wi-Fi, or VPN route; the Passport itself never receives the API
key.

## Checks

```bash
flutter analyze
flutter test
```

The MVP expects the TTS endpoint to return 16 kHz, 16-bit, mono PCM WAV audio.
See the parent application README and the protocol documentation for complete
limitations and message formats.

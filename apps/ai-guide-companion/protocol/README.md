<p align="right"><a href="README.zh_CN.md">简体中文</a> · <strong>English</strong></p>

# Guide Companion BLE protocol v1

The Passport exposes one Nordic-UART-compatible GATT service:

- Service: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
- Phone writes to RX: `6e400002-b5a3-f393-e0a9-e50e24dcca9e`
- Passport notifies TX: `6e400003-b5a3-f393-e0a9-e50e24dcca9e`

Every packet starts with a one-byte type. Multi-packet text is UTF-8.

| Type | Direction | Payload |
| ---: | --- | --- |
| `0x01` | Passport → phone | recording start: little-endian `uint16` sample rate |
| `0x02` | Passport → phone | IMA-ADPCM audio block |
| `0x03` | Passport → phone | recording end |
| `0x10` | phone → Passport | recognized question text chunk |
| `0x11` | phone → Passport | answer text chunk |
| `0x12` | phone → Passport | playback start: little-endian `uint16` sample rate |
| `0x13` | phone → Passport | IMA-ADPCM audio block |
| `0x14` | phone → Passport | response/playback end |
| `0x7f` | either | UTF-8 error message |

Each ADPCM block is independently decodable. Its four-byte header contains
little-endian signed PCM predictor, step index, and a reserved byte, followed
by two 4-bit samples per byte. Independent blocks make packet loss bounded.

The MVP runs one half-duplex turn at a time. It does not define routing,
location, accounts, or model credentials.

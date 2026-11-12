# XAUGridScalper Android Demo

This is the first Android **paper-trading** implementation of the supplied `XAUGridScalper.mq4`.

## What is preserved

The demo uses the same core strategy rules and default parameters from the MT4 source:

- EMA 20 / 50 / 200
- RSI 14
- ADX 14
- ATR 14 + 100-bar ATR average
- Regime classification: Bull / Bear / Range / High Vol / Low Vol / Unsafe
- Trend score and range score, minimum 5/7
- Fixed lot 0.01, max lot 0.02
- Maximum 5 positions and 0.05 basket lots
- Grid spacing: 0.6 ATR range, 1.0 ATR trend, 1.5 ATR high-vol (high-vol grid disabled)
- Basket TP/SL logic
- Daily loss 2%, daily target 2%, equity DD 5%
- Consecutive-loss pause
- Trade-rate limits
- Spread protection

The original source is included unchanged at `reference/XAUGridScalper.mq4`.

## Important limitation

The app currently uses a deterministic **synthetic XAUUSD M1 feed**. It does not connect to Exness and does not place real orders.

This is intentional: first we validate the strategy behavior on Android. A later version can replace the demo feed with a real market-data source and, separately, add a verified broker-execution integration.

## Build

With Flutter installed:

```bash
flutter pub get
flutter build apk --release
```

The APK will be under:

`build/app/outputs/flutter-apk/app-release.apk`

## GitHub Actions

The included workflow `.github/workflows/build-apk.yml` builds the Android APK automatically.


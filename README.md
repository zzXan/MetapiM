# MetapiM

Flutter iOS client for your self-hosted [Metapi](https://github.com/wyf9661/metapi) server. Publication target: https://github.com/zzXan/MetapiM.

## Implemented source

- Flutter connection form, Keychain-backed saved connection, authenticated validation.
- WebView loads the server UI; web updates arrive from the server, not an embedded frontend copy.
- Origin-restricted navigation and web session bootstrap using the existing server auth keys.
- Foreground/manual refresh, logout and cached widget snapshot removal.
- WidgetKit medium/large widget with provider balances descending, latest calls, input/output, local cache-read percentage and estimated cost.

The local cache percentage is `cacheReadTokens / effectiveInput`, using the existing web helper's effective input rule (`cacheRead + cacheCreation > prompt ? prompt + cacheRead + cacheCreation : prompt`). Missing cache data remains unknown, not an invented zero. Cost is `estimatedCost`, displayed as USD with six decimals and `-` when missing. The server is not modified.

Widget snapshots refresh when the app opens/resumes or the user refreshes. The extension currently reads the last successful snapshot; its timeline does not independently fetch live server data. iOS schedules widget updates and does not guarantee real-time refresh.

## Build

Flutter stable, Xcode and CocoaPods on macOS are required:

```sh
flutter create --platforms=ios --org com.zzxan --project-name metapi_m .
rm -f test/widget_test.dart
flutter pub get
flutter build ios --config-only --no-codesign
gem install xcodeproj --no-document
ruby scripts/configure_ios.rb
(cd ios && pod install)
flutter analyze --no-fatal-infos
flutter test
flutter build ios --release --no-codesign
```

The GitHub Actions workflow runs these steps and packages `MetapiM-unsigned.ipa` and `MetapiM-iOS-unsigned.zip`. No Android/APK job is included. An unsigned IPA cannot normally be installed until re-signed; App Groups must be provisioned for both app and extension when signing.

Local environment currently lacks Flutter/Dart, Ruby and Xcode; the first macOS build is not verified. Source checks are not a substitute for compilation. Plugin resolution, extension embedding, server login and widget layout still require that build/device verification.

Legacy Swift-only prototypes are not used by the Flutter build and remain as reference material pending cleanup.

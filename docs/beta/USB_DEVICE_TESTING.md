# USB Device Testing Guide

Run mo-code on a physical Android device connected via USB.

## Prerequisites

- Linux machine (Ubuntu/Debian)
- Flutter SDK installed
- Android phone with USB cable
- mo-code repo cloned

## 1. Install ADB

```bash
sudo apt install android-tools-adb
```

Verify:

```bash
adb version
```

## 2. Enable Developer Options on Phone

1. **Settings > About phone**
2. Tap **Build number** 7 times — "You are now a developer" toast appears
3. Go back to **Settings > System > Developer options**
4. Enable **USB debugging**

> On some phones, Developer options is under Settings > About phone > Software information. The exact path varies by manufacturer.

## 3. Connect Phone via USB

1. Plug in the USB cable
2. On the phone, a dialog appears: **"Allow USB debugging?"**
3. Tap **Allow** (check "Always allow from this computer")

Verify the device is detected:

```bash
adb devices
```

Expected output:

```
List of devices attached
XXXXXXXXXX    device
```

If it shows `unauthorized`, re-check the USB debugging prompt on the phone.

## 4. Verify Flutter Sees the Device

```bash
flutter devices
```

Should list your phone, e.g.:

```
Pixel 7 (mobile) • XXXXXXXXXX • android-arm64 • Android 14 (API 34)
```

## 5. Run the App

### Debug mode (hot reload, slower)

```bash
cd flutter
flutter run
```

### Release mode (optimized, no debug overhead)

```bash
cd flutter
flutter run --release
```

### Install without running

```bash
cd flutter
flutter install --release
```

## 6. View Logs

While the app is running:

```bash
adb logcat -s MoCodeDaemon:* RuntimeBootstrap:* flutter:*
```

Or all logs:

```bash
adb logcat | grep -E "MoCode|Runtime|flutter"
```

## 7. First Launch Behavior

On first launch, the app will:

1. Extract proot binary + Alpine Linux rootfs from APK assets (~5MB)
2. Show progress in the notification: "Setting up runtime..."
3. Start the Go daemon with proot environment configured
4. Connect Flutter UI to the daemon via WebSocket

This takes 10-30 seconds on first launch. Subsequent launches skip extraction.

## Troubleshooting

### `adb devices` shows nothing

- Try a different USB cable (some cables are charge-only, no data)
- Try a different USB port
- Run `adb kill-server && adb start-server`
- Check that USB debugging is enabled in Developer options

### `adb devices` shows `unauthorized`

- Unlock the phone and accept the USB debugging prompt
- If no prompt appears: revoke USB debugging authorizations in Developer options, reconnect

### `flutter devices` doesn't show the phone

```bash
flutter doctor -v
```

Check the Android toolchain section for missing components.

### App crashes on launch

```bash
adb logcat -s MoCodeDaemon:E RuntimeBootstrap:E AndroidRuntime:E
```

Common causes:
- Missing `assets/runtime/` — run `./scripts/download-runtime.sh` before building
- Architecture mismatch — proot binary is ARM64 only; x86 emulators won't work

### Build fails with signing errors

Ensure `flutter/android/key.properties` exists and points to the keystore correctly. See `docs/PLAY_STORE_DEPLOYMENT.md` for setup.

## Quick Reference

| Command | What it does |
|---------|-------------|
| `adb devices` | List connected devices |
| `flutter devices` | List Flutter-compatible devices |
| `flutter run` | Build + install + launch (debug) |
| `flutter run --release` | Build + install + launch (release) |
| `flutter install --release` | Install without launching |
| `adb logcat -s MoCodeDaemon:*` | View daemon logs |
| `adb shell pm uninstall io.github.omashishsoni.mocode` | Uninstall the app |
| `adb shell am force-stop io.github.omashishsoni.mocode` | Force stop the app |

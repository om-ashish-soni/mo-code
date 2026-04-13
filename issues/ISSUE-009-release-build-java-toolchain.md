# ISSUE-009: Release Build Fails — Gradle Java Toolchain Error

## Status
OPEN

## Problem
`flutter build appbundle --release` fails with:

```
Could not create task ':shared_preferences_android:compileDebugJavaWithJavac'.
> Failed to calculate the value of task ':shared_preferences_android:compileDebugJavaWithJavac' property 'javaCompiler'.
   > Toolchain installation '/usr/lib/jvm/java-21-openjdk-amd64' does not provide the required capabilities: [JAVA_COMPILER]
```

## Environment
- Ubuntu 24.04, Linux 6.17.0
- Flutter 3.41.6 (stable)
- OpenJDK 21.0.10 (`openjdk-21-jdk` installed, `javac` works)
- Gradle from Flutter's embedded wrapper

## What's been tried
1. Installed `openjdk-21-jdk` (was JRE-only before) — `javac` now works at `/usr/lib/jvm/java-21-openjdk-amd64/bin/javac`
2. Set `JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64` explicitly — same error
3. Gradle still reports the toolchain "does not provide JAVA_COMPILER"

## What's been fixed already (don't revert)
- `compileSdk` bumped 35 → 36 in `flutter/android/app/build.gradle.kts` (required by `speech_to_text` plugin)
- Kotlin type fix in `DaemonService.kt:150` — extracted `workDir` variable to avoid `Serializable` inference
- `key.properties` created at `flutter/android/key.properties`
- Keystore generated at `flutter/mocode-release.keystore` (password: 123456, alias: mocode)

## Likely root causes to investigate
1. **Stale Gradle daemon cache** — try `cd flutter/android && ./gradlew --stop` then rebuild
2. **Gradle JDK auto-detection bug** — Gradle may have cached the old JRE-only probe. Try deleting `~/.gradle/caches/` or at least `~/.gradle/jdks/`
3. **Gradle toolchain config** — may need to set `org.gradle.java.home` in `flutter/android/gradle.properties`
4. **shared_preferences_android plugin** — version 2.4.7 may have a toolchain requirement. Could try upgrading deps with `flutter pub upgrade`

## Quick resume steps
```bash
# Option A: Force Gradle to re-detect JDK
cd /mnt/linux_disk/opensource/mo-code/flutter/android
./gradlew --stop
echo "org.gradle.java.home=/usr/lib/jvm/java-21-openjdk-amd64" >> gradle.properties
cd .. && flutter build appbundle --release

# Option B: Clear Gradle caches entirely
rm -rf ~/.gradle/caches/
cd /mnt/linux_disk/opensource/mo-code/flutter
flutter build appbundle --release
```

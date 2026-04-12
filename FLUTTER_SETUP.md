# Flutter Installation/Repair Guide (Linux)

## Quick Install (If Not Installed)

1. **Download Flutter SDK**:
   ```bash
   wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.3-stable.tar.xz
   ```

2. **Extract**:
   ```bash
   tar xf flutter_linux_3.24.3-stable.tar.xz
   ```

3. **Move to /opt** (or ~/flutter):
   ```bash
   sudo mv flutter /opt/
   ```

4. **Add to PATH** (add to ~/.bashrc or ~/.zshrc):
   ```bash
   export PATH="$PATH:/opt/flutter/bin"
   source ~/.bashrc
   ```

5. **Verify**:
   ```bash
   flutter --version
   flutter doctor
   ```

## Repair Existing Installation

1. **Check current status**:
   ```bash
   flutter doctor
   ```

2. **Update Flutter**:
   ```bash
   flutter upgrade
   ```

3. **Install missing Android SDK** (if needed):
   ```bash
   flutter doctor --android-licenses
   ```

4. **Install missing tools**:
   ```bash
   sudo apt update
   sudo apt install -y openjdk-11-jdk android-tools-adb android-tools-fastboot
   ```

5. **Accept Android licenses**:
   ```bash
   flutter doctor --android-licenses
   ```

## Common Issues

- **PATH not set**: Re-add `/opt/flutter/bin` to PATH and source shell config
- **Java not found**: Install OpenJDK 11+
- **Android SDK missing**: Flutter doctor will guide you
- **Permission denied**: Use sudo for system-wide installs

Run `flutter doctor` after each step to check progress.
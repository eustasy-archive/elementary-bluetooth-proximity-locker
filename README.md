Bluetooth Proximity Locker for elementary OS
==============

Lock or unlock your session based on the connection state of a paired Bluetooth device.

### Quick Start

Build and install the Flatpak:

```sh
flatpak-builder build io.github.eustasy.BluetoothProximityLocker.yml --user --install --force-clean
```

Open the settings window (normal app launch):

```sh
flatpak run io.github.eustasy.BluetoothProximityLocker
```

Run in background service mode (no UI window):

```sh
flatpak run io.github.eustasy.BluetoothProximityLocker --gapplication-service
```

### Setup

1. Pair your phone/tablet in system Bluetooth settings.
2. Launch the app in UI mode.
3. Select the paired device to monitor from the list.
4. Keep the service running (autostart uses service mode automatically).

### How It Works

1. On startup, the app reads the configured device address from GSettings.
2. It watches BlueZ device state over D-Bus.
3. When the monitored device disconnects, it requests a session lock.
4. When the device reconnects, it requests an unlock.

### Run Modes

- UI mode: opens the settings window.
- Service mode: starts monitoring without opening a window.

Autostart uses service mode so login does not pop up the settings window.

### Troubleshooting

- If you see `Unable to acquire bus name 'io.github.eustasy.BluetoothProximityLocker'`, another instance is already running:

```sh
flatpak kill io.github.eustasy.BluetoothProximityLocker
flatpak run io.github.eustasy.BluetoothProximityLocker
```

- If you see `Settings schema 'io.github.eustasy.BluetoothProximityLocker' is not installed`, rebuild and reinstall:

```sh
flatpak-builder build io.github.eustasy.BluetoothProximityLocker.yml --user --install --force-clean
```
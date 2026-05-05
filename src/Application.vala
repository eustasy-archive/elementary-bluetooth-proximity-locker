/*
 * SPDX-FileCopyrightText: 2026 eustasy
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Startup / activation split:
 *
 *   startup()  — called once when the process starts, regardless of how it
 *                was started. Initialises settings, starts the background
 *                Bluetooth monitor. IS_SERVICE keeps the process alive with
 *                no windows open.
 *
 *   activate() — called when the user launches the app from the dock / app
 *                grid, or when another instance is launched while this one
 *                is already running. Opens (or raises) the settings window.
 *
 * Autostart at login uses --gapplication-service so activate() is NOT called
 * and no window appears. The user opens the settings window on demand.
 */

namespace BTProx {

    public class Application : Gtk.Application {

        private BluetoothMonitor? monitor;
        private LockManager? lock_manager;
        private AppSettings? settings;
        private SettingsWindow? settings_window;

        public Application () {
            Object (
                application_id: "io.github.eustasy.BluetoothProximityLocker",
                // Normal launches open the UI. Background mode is enabled
                // explicitly via --gapplication-service (autostart desktop file).
                flags: GLib.ApplicationFlags.FLAGS_NONE
            );
        }

        // ── Lifecycle ─────────────────────────────────────────────────────

        protected override void startup () {
            base.startup (); // must call to initialise GTK

            settings = new AppSettings ();
            lock_manager = new LockManager (settings);

            settings.changed["device-address"].connect (() => {
                restart_monitor ();
            });

            restart_monitor ();
        }

        /**
         * Called when the user opens the app. Shows (or raises) the settings
         * window so they can choose which Bluetooth device to monitor.
         */
        protected override void activate () {
            if (settings_window == null) {
                settings_window = new SettingsWindow (this, settings);
                settings_window.close_request.connect (() => {
                    settings_window = null;
                    return false; // allow the window to close normally
                });
            }
            settings_window.present ();
        }

        // ── Monitor management ────────────────────────────────────────────

        private void restart_monitor () {
            if (monitor != null) {
                monitor.stop ();
                monitor = null;
            }

            string address = settings.device_address;
            if (address.length == 0) {
                message (
                    "No device configured. " +
                    "Open the app to select a Bluetooth device."
                );
                return;
            }

            message ("Starting monitor for device %s.", address);
            monitor = new BluetoothMonitor (address, settings);

            monitor.device_in_range.connect (() => {
                message ("Device in range — unlocking session.");
                lock_manager.unlock ();
            });

            monitor.device_out_of_range.connect (() => {
                message ("Device out of range — locking session.");
                lock_manager.lock_session ();
            });

            monitor.start ();
        }

    }

} // namespace BTProx

int main (string[] args) {
    return new BTProx.Application ().run (args);
}

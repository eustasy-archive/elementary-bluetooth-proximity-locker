/*
 * SPDX-FileCopyrightText: 2026 eustasy
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace BTProx {

    public class Application : GLib.Application {

        private BluetoothMonitor? monitor;
        private LockManager lock_manager;
        private AppSettings settings;

        public Application () {
            Object (
                application_id: "io.github.eustasy.BluetoothProximityLocker",
                flags: GLib.ApplicationFlags.IS_SERVICE
            );
        }

        protected override void activate () {
            hold ();

            settings = new AppSettings ();
            lock_manager = new LockManager (settings);

            settings.changed["device-address"].connect (() => {
                restart_monitor ();
            });

            restart_monitor ();
        }

        private void restart_monitor () {
            if (monitor != null) {
                monitor.stop ();
                monitor = null;
            }

            string address = settings.device_address;
            if (address.length == 0) {
                warning (
                    "No Bluetooth device address configured. " +
                    "Run: gsettings set %s device-address 'AA:BB:CC:DD:EE:FF'",
                    application_id
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

/*
 * SPDX-FileCopyrightText: 2026 eustasy
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace BTProx {

    public class AppSettings : GLib.Settings {

        /**
         * MAC address of the Bluetooth device to monitor (e.g. "AA:BB:CC:DD:EE:FF").
         * Set via: gsettings set io.github.eustasy.BluetoothProximityLocker device-address 'XX:XX:XX:XX:XX:XX'
         */
        public string device_address {
            owned get { return get_string ("device-address"); }
            set { set_string ("device-address", value); }
        }

        /**
         * Seconds after an unlock event during which the screen will NOT re-lock,
         * even if the device goes out of range. Prevents a lock/unlock race when
         * you return to your desk.
         */
        public uint freeze_time {
            get { return get_uint ("freeze-time"); }
            set { set_uint ("freeze-time", value); }
        }

        /**
         * Seconds to wait after the device reports as disconnected before
         * actually locking. Guards against brief Bluetooth dropouts.
         */
        public uint disconnect_delay {
            get { return get_uint ("disconnect-delay"); }
            set { set_uint ("disconnect-delay", value); }
        }

        public AppSettings () {
            Object (schema_id: "io.github.eustasy.BluetoothProximityLocker");
        }

    }

} // namespace BTProx

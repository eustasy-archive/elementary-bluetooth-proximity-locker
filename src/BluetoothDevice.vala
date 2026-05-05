/*
 * SPDX-FileCopyrightText: 2026 eustasy
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace BTProx {

    /**
     * Simple data class representing a Bluetooth device returned by BlueZ.
     * Populated by querying org.freedesktop.DBus.ObjectManager.GetManagedObjects
     * on the org.bluez service.
     */
    public class BluetoothDevice : GLib.Object {

        /** Hardware address, e.g. "AA:BB:CC:DD:EE:FF". Always present. */
        public string address { get; set; default = ""; }

        /**
         * User-editable alias (set via bluetoothctl set-alias).
         * Preferred display name when present.
         */
        public string? alias_name { get; set; default = null; }

        /**
         * Firmware name reported by the device itself.
         * Used as display name if no alias is set.
         */
        public string? firmware_name { get; set; default = null; }

        /**
         * Freedesktop icon name hint from BlueZ (e.g. "phone", "computer",
         * "audio-headset"). May be null.
         */
        public string? icon { get; set; default = null; }

        /** True if the device has been paired with this computer. */
        public bool paired { get; set; default = false; }

        /** True if the device is currently connected over Bluetooth. */
        public bool connected { get; set; default = false; }

        /** Best available human-readable name for this device. */
        public string display_name {
            owned get { return alias_name ?? firmware_name ?? address; }
        }

    }

} // namespace BTProx

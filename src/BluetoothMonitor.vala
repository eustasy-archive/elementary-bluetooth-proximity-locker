/*
 * SPDX-FileCopyrightText: 2026 eustasy
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Watches a paired Bluetooth device via the BlueZ D-Bus API (org.bluez).
 *
 * Strategy: monitor the org.bluez.Device1 "Connected" property.
 * When the device connects → emit device_in_range.
 * When the device disconnects (and stays disconnected for disconnect_delay
 * seconds) → emit device_out_of_range.
 *
 * The device must be paired before this monitor will find it.
 * Pair with: bluetoothctl pair AA:BB:CC:DD:EE:FF
 */

namespace BTProx {

    public class BluetoothMonitor : GLib.Object {

        /** Emitted when the target device connects / is found connected. */
        public signal void device_in_range ();

        /** Emitted after the target device has been disconnected for
         *  disconnect_delay seconds. */
        public signal void device_out_of_range ();

        private string target_address;
        private AppSettings settings;

        private GLib.DBusProxy? object_manager_proxy = null;
        private GLib.DBusProxy? device_proxy = null;

        private bool running = false;
        private uint disconnect_timer_id = 0;

        public BluetoothMonitor (string address, AppSettings settings) {
            this.target_address = address.ascii_up ();
            this.settings = settings;
        }

        public void start () {
            running = true;
            connect_to_bluez.begin ();
        }

        public void stop () {
            running = false;
            cancel_disconnect_timer ();
            device_proxy = null;
            object_manager_proxy = null;
        }

        // ── BlueZ connection ──────────────────────────────────────────────

        private async void connect_to_bluez () {
            try {
                object_manager_proxy = yield new GLib.DBusProxy.for_bus (
                    GLib.BusType.SYSTEM,
                    GLib.DBusProxyFlags.NONE,
                    null,
                    "org.bluez",
                    "/",
                    "org.freedesktop.DBus.ObjectManager",
                    null
                );

                // Watch for devices appearing / disappearing
                object_manager_proxy.g_signal.connect (on_object_manager_signal);

                // Find the device in the objects already known to BlueZ
                yield find_and_setup_device ();

            } catch (GLib.Error e) {
                critical ("Cannot connect to BlueZ D-Bus service: %s", e.message);
            }
        }

        // ── Device discovery ──────────────────────────────────────────────

        private async void find_and_setup_device () {
            if (object_manager_proxy == null) return;

            try {
                var result = yield object_manager_proxy.call (
                    "GetManagedObjects",
                    null,
                    GLib.DBusCallFlags.NONE,
                    -1,
                    null
                );

                // Result type: (a{oa{sa{sv}}})
                var managed_objects = result.get_child_value (0);
                string? path = find_device_path (managed_objects);

                if (path != null) {
                    yield setup_device_proxy (path);
                } else {
                    message (
                        "Device %s not yet visible in BlueZ — " +
                        "waiting for it to be paired / appear.",
                        target_address
                    );
                }

            } catch (GLib.Error e) {
                warning ("GetManagedObjects failed: %s", e.message);
            }
        }

        /**
         * Walk a{oa{sa{sv}}} looking for an entry whose org.bluez.Device1
         * "Address" property matches target_address. Returns the object path
         * or null if not found.
         */
        private string? find_device_path (GLib.Variant managed_objects) {
            for (size_t i = 0; i < managed_objects.n_children (); i++) {
                var entry = managed_objects.get_child_value (i);
                // entry = {o, a{sa{sv}}}
                string obj_path = entry.get_child_value (0).get_string ();
                var interfaces = entry.get_child_value (1); // a{sa{sv}}

                string? addr = extract_device1_address (interfaces);
                if (addr != null && addr.ascii_up () == target_address) {
                    return obj_path;
                }
            }
            return null;
        }

        /**
         * Given a{sa{sv}} (map of interface name → properties), return the
         * "Address" string from "org.bluez.Device1", or null if not present.
         */
        private string? extract_device1_address (GLib.Variant interfaces) {
            for (size_t i = 0; i < interfaces.n_children (); i++) {
                var iface_entry = interfaces.get_child_value (i); // {s, a{sv}}
                string iface_name = iface_entry.get_child_value (0).get_string ();

                if (iface_name == "org.bluez.Device1") {
                    var props = iface_entry.get_child_value (1); // a{sv}
                    var addr_v = props.lookup_value ("Address", GLib.VariantType.STRING);
                    return addr_v != null ? addr_v.get_string () : null;
                }
            }
            return null;
        }

        // ── Device proxy setup ────────────────────────────────────────────

        private async void setup_device_proxy (string path) {
            if (!running) return;

            try {
                device_proxy = yield new GLib.DBusProxy.for_bus (
                    GLib.BusType.SYSTEM,
                    GLib.DBusProxyFlags.NONE,
                    null,
                    "org.bluez",
                    path,
                    "org.bluez.Device1",
                    null
                );

                // Emit based on the current state before any changes arrive
                var connected_v = device_proxy.get_cached_property ("Connected");
                if (connected_v != null && connected_v.get_boolean ()) {
                    message ("Device %s is already connected.", target_address);
                    device_in_range ();
                }

                device_proxy.g_properties_changed.connect (on_device_properties_changed);

            } catch (GLib.Error e) {
                warning ("Failed to create proxy for %s at %s: %s",
                         target_address, path, e.message);
            }
        }

        // ── Property change handler ───────────────────────────────────────

        private void on_device_properties_changed (GLib.Variant changed,
                                                    string[] invalidated) {
            if (!running) return;

            var connected_v = changed.lookup_value ("Connected",
                                                     GLib.VariantType.BOOLEAN);
            if (connected_v == null) return;

            bool connected = connected_v.get_boolean ();

            if (connected) {
                // Device just connected — cancel any pending lock and notify
                cancel_disconnect_timer ();
                message ("Device %s connected.", target_address);
                device_in_range ();
            } else {
                // Device disconnected — wait disconnect_delay before locking
                // to guard against brief Bluetooth dropouts
                schedule_out_of_range ();
            }
        }

        private void schedule_out_of_range () {
            if (disconnect_timer_id != 0) return; // timer already running

            uint delay = settings.disconnect_delay;
            message (
                "Device %s disconnected — will lock in %u second(s) if not " +
                "reconnected.",
                target_address, delay
            );

            disconnect_timer_id = GLib.Timeout.add_seconds (delay, () => {
                disconnect_timer_id = 0;
                if (!running) return GLib.Source.REMOVE;

                // Confirm the device is still disconnected before locking
                var connected_v = device_proxy != null
                    ? device_proxy.get_cached_property ("Connected")
                    : null;

                bool still_disconnected = (connected_v == null ||
                                           !connected_v.get_boolean ());
                if (still_disconnected) {
                    device_out_of_range ();
                }
                return GLib.Source.REMOVE;
            });
        }

        private void cancel_disconnect_timer () {
            if (disconnect_timer_id != 0) {
                GLib.Source.remove (disconnect_timer_id);
                disconnect_timer_id = 0;
            }
        }

        // ── ObjectManager signal handler ──────────────────────────────────

        private void on_object_manager_signal (string? sender_name,
                                                string signal_name,
                                                GLib.Variant parameters) {
            if (!running) return;

            if (signal_name == "InterfacesAdded") {
                // parameters = (o, a{sa{sv}})
                string path = parameters.get_child_value (0).get_string ();
                var interfaces = parameters.get_child_value (1);

                string? addr = extract_device1_address (interfaces);
                if (addr != null && addr.ascii_up () == target_address) {
                    message ("Target device %s appeared in BlueZ.", target_address);
                    setup_device_proxy.begin (path);
                }

            } else if (signal_name == "InterfacesRemoved") {
                // parameters = (o, as)
                if (device_proxy == null) return;

                string path = parameters.get_child_value (0).get_string ();
                if (path != device_proxy.g_object_path) return;

                var ifaces = parameters.get_child_value (1); // as
                for (size_t i = 0; i < ifaces.n_children (); i++) {
                    if (ifaces.get_child_value (i).get_string () ==
                            "org.bluez.Device1") {
                        message (
                            "Target device %s removed from BlueZ " +
                            "(unpaired or adapter reset).",
                            target_address
                        );
                        device_proxy = null;
                        cancel_disconnect_timer ();
                        device_out_of_range ();
                        break;
                    }
                }
            }
        }

    }

} // namespace BTProx

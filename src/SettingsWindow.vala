/*
 * SPDX-FileCopyrightText: 2026 eustasy
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Settings window that lists paired Bluetooth devices and lets the user
 * select which one to use for proximity detection.
 *
 * Opening flow:
 *   1. Window opens and calls load_devices() which queries BlueZ over D-Bus.
 *   2. Paired devices are shown in a list. The currently monitored device
 *      (stored in GSettings) is shown with a checkmark.
 *   3. Clicking a row updates GSettings which triggers the background monitor
 *      to restart watching the new device.
 *   4. "Pair a Device…" opens the system Bluetooth settings panel so the user
 *      can pair a new device before selecting it here.
 */

namespace BTProx {

    /**
     * A single row in the paired-device list. Stores the device address so we
     * can write it back to GSettings when the row is activated.
     */
    private class DeviceRow : Gtk.ListBoxRow {

        public string device_address;

        public DeviceRow (BluetoothDevice device, string monitored_address) {
            Object ();

            device_address = device.address;

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            box.margin_top = 10;
            box.margin_bottom = 10;
            box.margin_start = 12;
            box.margin_end = 12;

            // Icon: map BlueZ icon hints to symbolic GTK icon names
            var icon = new Gtk.Image.from_icon_name (
                map_bluez_icon (device.icon)
            );
            box.append (icon);

            // Name label stack (device name above, address below)
            var label_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            label_box.hexpand = true;

            var name_label = new Gtk.Label (device.display_name);
            name_label.xalign = 0;
            label_box.append (name_label);

            // Only show the address line when we have a distinct display name
            if (device.display_name != device.address) {
                var addr_label = new Gtk.Label (device.address);
                addr_label.xalign = 0;
                addr_label.add_css_class ("dim-label");
                label_box.append (addr_label);
            }

            box.append (label_box);

            // "Connected" badge
            if (device.connected) {
                var badge = new Gtk.Label ("Connected");
                badge.add_css_class ("dim-label");
                box.append (badge);
            }

            // Checkmark for the currently monitored device
            if (device.address.ascii_up () == monitored_address.ascii_up ()) {
                var check = new Gtk.Image.from_icon_name ("object-select-symbolic");
                check.tooltip_text = "Currently monitored";
                box.append (check);
            }

            child = box;
        }

        /**
         * Map BlueZ device class icon hints to freedesktop symbolic icon names.
         * BlueZ returns names like "phone", "computer", "audio-headset", etc.
         */
        private static string map_bluez_icon (string? bluez_icon) {
            if (bluez_icon == null) return "bluetooth-symbolic";
            switch (bluez_icon) {
                case "phone":
                    return "phone-symbolic";
                case "computer":
                    return "computer-symbolic";
                case "audio-headset":
                    return "audio-headset-symbolic";
                case "audio-headphones":
                    return "audio-headphones-symbolic";
                case "audio-card":
                    return "audio-card-symbolic";
                case "input-mouse":
                    return "input-mouse-symbolic";
                case "input-keyboard":
                    return "input-keyboard-symbolic";
                case "input-gaming":
                    return "input-gaming-symbolic";
                case "camera-photo":
                    return "camera-photo-symbolic";
                default:
                    return "bluetooth-symbolic";
            }
        }

    } // class DeviceRow


    public class SettingsWindow : Gtk.ApplicationWindow {

        private AppSettings settings;

        private Gtk.ListBox device_list;
        private Gtk.Label status_label;
        private Gtk.Button refresh_button;

        public SettingsWindow (Gtk.Application app, AppSettings settings) {
            Object (
                application: app,
                title: "Bluetooth Proximity Locker"
            );
            this.settings = settings;
            build_ui ();
            load_devices.begin ();
        }

        // ── UI construction ───────────────────────────────────────────────

        private void build_ui () {
            default_width = 420;
            default_height = 520;

            // Header bar
            var header = new Gtk.HeaderBar ();
            set_titlebar (header);

            // "Pair a Device…" opens the system Bluetooth settings panel
            var pair_button = new Gtk.Button.with_label ("Pair a Device…");
            pair_button.tooltip_text =
                "Open system Bluetooth settings to pair a new device";
            pair_button.clicked.connect (open_bluetooth_settings);
            header.pack_start (pair_button);

            // Refresh button
            refresh_button = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
            refresh_button.tooltip_text = "Refresh device list";
            refresh_button.clicked.connect (() => load_devices.begin ());
            header.pack_end (refresh_button);

            // Main layout
            var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            // Introductory description
            var intro = new Gtk.Label (
                "Select the paired Bluetooth device to monitor. " +
                "Your screen will lock when it disconnects and " +
                "unlock when it reconnects."
            );
            intro.wrap = true;
            intro.xalign = 0;
            intro.margin_top = 12;
            intro.margin_bottom = 12;
            intro.margin_start = 12;
            intro.margin_end = 12;
            main_box.append (intro);

            main_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // Scrollable device list
            device_list = new Gtk.ListBox ();
            device_list.selection_mode = Gtk.SelectionMode.SINGLE;
            device_list.row_activated.connect (on_row_activated);

            // Placeholder shown when the list is empty
            var placeholder = new Gtk.Label (
                "No paired Bluetooth devices found.\n" +
                "Use \"Pair a Device…\" to pair one first."
            );
            placeholder.justify = Gtk.Justification.CENTER;
            placeholder.margin_top = 32;
            placeholder.margin_bottom = 32;
            placeholder.margin_start = 12;
            placeholder.margin_end = 12;
            placeholder.add_css_class ("dim-label");
            device_list.set_placeholder (placeholder);

            var scroll = new Gtk.ScrolledWindow ();
            scroll.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scroll.vexpand = true;
            scroll.child = device_list;
            main_box.append (scroll);

            main_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // Status / hint bar at the bottom
            status_label = new Gtk.Label ("");
            status_label.xalign = 0;
            status_label.margin_top = 8;
            status_label.margin_bottom = 8;
            status_label.margin_start = 12;
            status_label.margin_end = 12;
            status_label.add_css_class ("dim-label");
            main_box.append (status_label);

            child = main_box;
        }

        // ── Device loading ────────────────────────────────────────────────

        private async void load_devices () {
            refresh_button.sensitive = false;
            status_label.label = "Searching for paired devices…";

            // Clear the existing list (GTK 4.12+)
            device_list.remove_all ();

            try {
                var proxy = yield new GLib.DBusProxy.for_bus (
                    GLib.BusType.SYSTEM,
                    GLib.DBusProxyFlags.NONE,
                    null,
                    "org.bluez",
                    "/",
                    "org.freedesktop.DBus.ObjectManager",
                    null
                );

                var result = yield proxy.call (
                    "GetManagedObjects",
                    null,
                    GLib.DBusCallFlags.NONE,
                    -1,
                    null
                );

                // a{oa{sa{sv}}}  — map of object path → map of interface → properties
                var managed_objects = result.get_child_value (0);
                string current = settings.device_address;
                uint count = 0;

                for (size_t i = 0; i < managed_objects.n_children (); i++) {
                    var entry = managed_objects.get_child_value (i);
                    var interfaces = entry.get_child_value (1);

                    BluetoothDevice? dev = extract_device (interfaces);
                    if (dev != null && dev.paired) {
                        device_list.append (new DeviceRow (dev, current));
                        count++;
                    }
                }

                if (count == 0) {
                    status_label.label =
                        "No paired devices. Click \"Pair a Device…\" to " +
                        "pair your phone or tablet first.";
                } else {
                    status_label.label = "%u paired device(s) found.".printf (count);
                }

            } catch (GLib.Error e) {
                status_label.label = format_bluetooth_error (e.message);
                warning ("BlueZ GetManagedObjects failed: %s", e.message);
            }

            refresh_button.sensitive = true;
        }

        /**
         * Make common BlueZ startup failures easier to understand for users.
         */
        private string format_bluetooth_error (string raw_message) {
            string msg = raw_message.down ();

            bool bluez_start_timeout =
                msg.contains ("org.bluez") &&
                msg.contains ("startservicebyname") &&
                (
                    msg.contains ("timed out") ||
                    msg.contains ("timeout was reached") ||
                    msg.contains ("service_start_timeout")
                );

            if (bluez_start_timeout) {
                return
                    "Bluetooth could not start. No adapter was detected. " +
                    "Plug in/enable a Bluetooth adapter, then refresh.";
            }

            return "Could not query Bluetooth: " + raw_message;
        }

        /**
         * Given a{sa{sv}} (interface name → properties map), extract a
         * BluetoothDevice from the org.bluez.Device1 interface if present.
         * Returns null if the entry is not a Device1 or is missing Address.
         */
        private BluetoothDevice? extract_device (GLib.Variant interfaces) {
            for (size_t i = 0; i < interfaces.n_children (); i++) {
                var iface_entry = interfaces.get_child_value (i);
                string iface_name = iface_entry.get_child_value (0).get_string ();

                if (iface_name != "org.bluez.Device1") continue;

                var props = iface_entry.get_child_value (1); // a{sv}

                var addr_v = props.lookup_value ("Address", GLib.VariantType.STRING);
                if (addr_v == null) return null;

                var paired_v = props.lookup_value ("Paired", GLib.VariantType.BOOLEAN);
                if (paired_v == null) return null;

                var dev = new BluetoothDevice ();
                dev.address = addr_v.get_string ();
                dev.paired = paired_v.get_boolean ();

                var alias_v = props.lookup_value ("Alias", GLib.VariantType.STRING);
                if (alias_v != null) dev.alias_name = alias_v.get_string ();

                var name_v = props.lookup_value ("Name", GLib.VariantType.STRING);
                if (name_v != null) dev.firmware_name = name_v.get_string ();

                var icon_v = props.lookup_value ("Icon", GLib.VariantType.STRING);
                if (icon_v != null) dev.icon = icon_v.get_string ();

                var connected_v = props.lookup_value (
                    "Connected", GLib.VariantType.BOOLEAN
                );
                if (connected_v != null) dev.connected = connected_v.get_boolean ();

                return dev;
            }
            return null;
        }

        // ── Event handlers ────────────────────────────────────────────────

        private void on_row_activated (Gtk.ListBoxRow row) {
            var device_row = row as DeviceRow;
            if (device_row == null) return;

            string address = device_row.device_address;
            message ("User selected device %s.", address);
            settings.device_address = address;

            // Reload to move the checkmark to the new selection
            load_devices.begin ();
        }

        /**
         * Open the system Bluetooth settings panel so the user can pair a
         * new device. Uses the XDG URI scheme which works inside the
         * Flatpak sandbox via xdg-desktop-portal.
         *
         * On elementary OS this opens the Bluetooth panel in System Settings.
         * On other GNOME-based systems it opens GNOME Control Center.
         */
        private void open_bluetooth_settings () {
            try {
                GLib.AppInfo.launch_default_for_uri ("settings://bluetooth", null);
            } catch (GLib.Error e) {
                warning ("Could not open Bluetooth settings: %s", e.message);

                // Fallback: try launching the elementary Settings app directly
                try {
                    var app = GLib.AppInfo.create_from_commandline (
                        "io.elementary.settings bluetooth",
                        null,
                        GLib.AppInfoCreateFlags.NONE
                    );
                    app.launch (null, null);
                } catch (GLib.Error e2) {
                    warning ("Could not launch elementary Settings: %s", e2.message);
                }
            }
        }

    } // class SettingsWindow

} // namespace BTProx

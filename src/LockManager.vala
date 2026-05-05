/*
 * SPDX-FileCopyrightText: 2026 eustasy
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Locks and unlocks the user session via standard D-Bus interfaces,
 * without requiring root or any deprecated tools.
 *
 * Lock:   org.freedesktop.ScreenSaver (session bus) — works in Flatpak sandbox
 *         Fallback: org.freedesktop.login1.Manager.LockSessions (system bus)
 *
 * Unlock: org.freedesktop.login1.Manager.UnlockSessions (system bus)
 *
 * Freeze time: after unlocking, the screen will NOT re-lock for
 * settings.freeze_time seconds, preventing an immediate re-lock if you
 * walk away briefly right after returning to your desk.
 */

namespace BTProx {

    public class LockManager : GLib.Object {

        private AppSettings settings;

        /** Monotonic timestamp (seconds) of the last unlock. */
        private int64 last_unlock_time = 0;

        /** Whether we believe the session is currently locked. */
        private bool session_is_locked = false;

        public LockManager (AppSettings settings) {
            this.settings = settings;
        }

        // ── Public API ────────────────────────────────────────────────────

        /**
         * Lock the session, unless we are still within the freeze window
         * that follows an unlock.
         */
        public void lock_session () {
            int64 now = monotonic_seconds ();
            int64 elapsed = now - last_unlock_time;

            if (elapsed < (int64) settings.freeze_time) {
                message (
                    "Skipping lock — %lld s since last unlock (freeze window: %u s).",
                    elapsed, settings.freeze_time
                );
                return;
            }

            if (session_is_locked) return;

            session_is_locked = true;
            do_lock.begin ();
        }

        /**
         * Unlock the session and record the time so the freeze window starts.
         */
        public void unlock () {
            last_unlock_time = monotonic_seconds ();

            if (!session_is_locked) return;

            session_is_locked = false;
            do_unlock.begin ();
        }

        // ── D-Bus lock helpers ────────────────────────────────────────────

        private async void do_lock () {
            // Primary: org.freedesktop.ScreenSaver on the session bus.
            // This is the standard way inside a Flatpak sandbox.
            try {
                var proxy = yield new GLib.DBusProxy.for_bus (
                    GLib.BusType.SESSION,
                    GLib.DBusProxyFlags.NONE,
                    null,
                    "org.freedesktop.ScreenSaver",
                    "/org/freedesktop/ScreenSaver",
                    "org.freedesktop.ScreenSaver",
                    null
                );
                yield proxy.call (
                    "Lock", null, GLib.DBusCallFlags.NONE, -1, null
                );
                message ("Session locked via org.freedesktop.ScreenSaver.");
                return;
            } catch (GLib.Error e) {
                warning (
                    "ScreenSaver lock failed (%s) — trying login1 fallback.",
                    e.message
                );
            }

            // Fallback: org.freedesktop.login1 on the system bus.
            try {
                var proxy = yield new GLib.DBusProxy.for_bus (
                    GLib.BusType.SYSTEM,
                    GLib.DBusProxyFlags.NONE,
                    null,
                    "org.freedesktop.login1",
                    "/org/freedesktop/login1",
                    "org.freedesktop.login1.Manager",
                    null
                );
                yield proxy.call (
                    "LockSessions", null, GLib.DBusCallFlags.NONE, -1, null
                );
                message ("Session locked via org.freedesktop.login1.");
            } catch (GLib.Error e) {
                critical ("All lock methods failed: %s", e.message);
            }
        }

        private async void do_unlock () {
            try {
                var proxy = yield new GLib.DBusProxy.for_bus (
                    GLib.BusType.SYSTEM,
                    GLib.DBusProxyFlags.NONE,
                    null,
                    "org.freedesktop.login1",
                    "/org/freedesktop/login1",
                    "org.freedesktop.login1.Manager",
                    null
                );
                yield proxy.call (
                    "UnlockSessions", null, GLib.DBusCallFlags.NONE, -1, null
                );
                message ("Session unlocked via org.freedesktop.login1.");
            } catch (GLib.Error e) {
                warning ("Session unlock failed: %s", e.message);
            }
        }

        // ── Utilities ─────────────────────────────────────────────────────

        private static int64 monotonic_seconds () {
            return GLib.get_monotonic_time () / 1000000;
        }

    }

} // namespace BTProx

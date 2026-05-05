app_id = meson.project_name()

# ── GSettings schema ──────────────────────────────────────────────────────────
install_data(
    app_id + '.gschema.xml',
    install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

# Compile schemas into the build dir so the app can be run un-installed
gnome.compile_schemas(
    depend_files: app_id + '.gschema.xml'
)

# ── Application launcher .desktop ─────────────────────────────────────────────
install_data(
    app_id + '.desktop',
    install_dir: get_option('datadir') / 'applications'
)

# ── Autostart .desktop (starts the daemon at login) ──────────────────────────
install_data(
    app_id + '.autostart.desktop',
    rename: app_id + '.desktop',
    install_dir: get_option('sysconfdir') / 'xdg' / 'autostart'
)

# ── D-Bus session service file (enables D-Bus activation) ────────────────────
install_data(
    app_id + '.dbus.service',
    rename: app_id + '.service',
    install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

# ── AppStream MetaInfo ────────────────────────────────────────────────────────
install_data(
    app_id + '.metainfo.xml',
    install_dir: get_option('datadir') / 'metainfo'
)

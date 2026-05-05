app_id = meson.project_name()

executable(
    app_id,
    'Application.vala',
    'AppSettings.vala',
    'BluetoothMonitor.vala',
    'LockManager.vala',
    dependencies: [
        dependency('glib-2.0'),
        dependency('gobject-2.0'),
        dependency('gio-2.0'),
        dependency('gio-unix-2.0'),
    ],
    install: true,
    install_dir: get_option('bindir')
)

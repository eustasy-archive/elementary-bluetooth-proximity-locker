app_id = meson.project_name()

executable(
    app_id,
    'Application.vala',
    'AppSettings.vala',
    'BluetoothDevice.vala',
    'BluetoothMonitor.vala',
    'LockManager.vala',
    'SettingsWindow.vala',
    dependencies: [
        dependency('glib-2.0'),
        dependency('gobject-2.0'),
        dependency('gio-2.0'),
        dependency('gio-unix-2.0'),
        dependency('gtk4'),
    ],
    install: true,
    install_dir: get_option('bindir')
)

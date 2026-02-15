dependencies = [
    dep_dino,
    dep_gee,
    dep_glib,
    dep_gmodule,
    dep_gtk4,
    dep_ayatana_appindicator,
    dep_qlite,
    dep_xmpp_vala,
]
sources = files(
    'src/plugin.vala',
    'src/register_plugin.vala',
)
vala_args = [
    '--vapidir', meson.current_source_dir() / 'vapi',
]
lib_tray_icon = shared_library('tray-icon', sources, name_prefix: '', vala_args: vala_args, dependencies: dependencies, install: true, install_dir: get_option('libdir') / get_option('plugindir'), install_rpath: default_install_rpath)
dep_tray_icon = declare_dependency(link_with: lib_tray_icon, include_directories: include_directories('.'))
summary('System tray icon (tray-icon)', dep_tray_icon, section: 'Plugins')

dependencies = [
    dep_dino,
    dep_gee,
    dep_glib,
    dep_gmodule,
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
lib_fdp = shared_library('fdp', sources, name_prefix: '', vala_args: vala_args, dependencies: dependencies, install: true, install_dir: get_option('libdir') / get_option('plugindir'), install_rpath: default_install_rpath)
dep_fdp = declare_dependency(link_with: lib_fdp, include_directories: include_directories('.'))
summary('Form Discovery and Publishing (XEP-0346)', dep_fdp, section: 'Plugins')

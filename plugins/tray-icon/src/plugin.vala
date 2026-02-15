using Dino.Entities;

namespace Dino.Plugins.TrayIcon {

public class Plugin : RootInterface, Object {

    public Dino.Application app;
    private App.Indicator indicator;
    private GLib.Menu menu;
    private GLib.SimpleActionGroup actions;
    private Gtk.Window? main_window = null;

    public void registered(Dino.Application app) {
        this.app = app;

        // Keep app running when window closed
        ((GLib.Application) app).hold();

        // Create indicator
        indicator = new App.Indicator(
            "im.dino.Dino",
            "im.dino.Dino",
            App.IndicatorCategory.COMMUNICATIONS);

        // Connect to connection status for debugging
        indicator.connection_changed.connect((connected) => {
            debug("Tray icon connection changed: %s", connected ? "connected" : "disconnected");
        });

        indicator.set_status(App.IndicatorStatus.ACTIVE);
        indicator.set_title("Dino");

        // Setup menu with GMenu/GAction
        setup_menu();

        // Connect to window lifecycle
        ((Gtk.Application) app).window_added.connect(on_window_added);

        // Connect to notifications for attention state
        app.stream_interactor.get_module(NotificationEvents.IDENTITY)
            .notify_content_item.connect(on_new_message);
    }

    private void setup_menu() {
        actions = new GLib.SimpleActionGroup();
        menu = new GLib.Menu();

        // Create show action
        var show_action = new GLib.SimpleAction("show", null);
        show_action.activate.connect(() => {
            debug("Show action activated");
            toggle_window();
        });
        actions.add_action(show_action);
        var show_item = new GLib.MenuItem("Show Dino", "indicator.show");
        menu.append_item(show_item);

        // Create preferences action
        var preferences_action = new GLib.SimpleAction("preferences", null);
        preferences_action.activate.connect(() => {
            debug("Preferences action activated");
            if (main_window != null) {
                main_window.present();
            }
            ((GLib.Application) app).activate_action("preferences", null);
        });
        actions.add_action(preferences_action);
        var preferences_item = new GLib.MenuItem("Preferences", "indicator.preferences");
        menu.append_item(preferences_item);

        // Create quit action
        var quit_action = new GLib.SimpleAction("quit", null);
        quit_action.activate.connect(() => {
            debug("Quit action activated");
            app.quit();
        });
        actions.add_action(quit_action);
        var quit_item = new GLib.MenuItem("Quit", "indicator.quit");
        menu.append_item(quit_item);

        // Set menu and actions on indicator
        indicator.set_menu(menu);
        indicator.set_actions(actions);
        indicator.set_secondary_activate_target("indicator.show");

        debug("Tray icon menu setup complete with %d items", menu.get_n_items());
    }

    private void on_window_added(Gtk.Window window) {
        if (main_window == null) {
            main_window = window;
            main_window.hide_on_close = true;

            // When window is shown, clear attention state
            main_window.notify["visible"].connect(() => {
                if (main_window.visible) {
                    indicator.set_status(App.IndicatorStatus.ACTIVE);
                }
            });

            debug("Tray icon: main window registered");
        }
    }

    private void toggle_window() {
        if (main_window == null) {
            ((GLib.Application) app).activate();
            return;
        }

        if (main_window.visible) {
            main_window.set_visible(false);
        } else {
            main_window.present();
        }
    }

    private void on_new_message(ContentItem item, Conversation conv) {
        // Only show attention if window is not visible
        if (main_window == null || !main_window.visible) {
            indicator.set_status(App.IndicatorStatus.ATTENTION);
        }
    }

    public void shutdown() {
        ((GLib.Application) app).release();
    }
}

}

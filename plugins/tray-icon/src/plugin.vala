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

        var show_action = new GLib.SimpleAction("show", null);
        show_action.activate.connect(() => toggle_window());
        actions.add_action(show_action);

        var preferences_action = new GLib.SimpleAction("preferences", null);
        preferences_action.activate.connect(() => {
            ((GLib.Application) app).activate_action("preferences", null);
        });
        actions.add_action(preferences_action);

        var quit_action = new GLib.SimpleAction("quit", null);
        quit_action.activate.connect(() => app.quit());
        actions.add_action(quit_action);

        menu = new GLib.Menu();
        menu.append("Show Dino", "indicator.show");
        menu.append("Preferences", "indicator.preferences");
        menu.append("Quit", "indicator.quit");

        indicator.set_menu(menu);
        indicator.set_actions(actions);
        indicator.set_secondary_activate_target("indicator.show");
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

namespace Dino {

// tip: gdbus introspect   --session   --dest org.freedesktop.portal.Desktop   --object-path /org/freedesktop/portal/desktop
// to examine all the available sub-interfaces on xdg-desktop-portal
// TODO: rename this libdino/src/dbus/portal/background?

public errordomain PortalError {
    CANCELLED,
    DENIED,
    FAILED
}

[DBus (name = "org.freedesktop.portal.Background")]
public interface PortalBackground : GLib.Object {
    // https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Background.html

    // v2 API
    public abstract async ObjectPath RequestBackground (
        string parent_window,
        HashTable<string, Variant> options
    ) throws GLib.Error;

    public abstract async void SetStatus (
        HashTable<string, Variant> options
    ) throws GLib.Error;

    [DBus (name = "version")]
    public abstract uint version { get; }
}

[DBus (name = "org.freedesktop.portal.Request")]
public interface PortalRequest : GLib.Object {

    public signal void Response (
        uint response,
        HashTable<string, Variant> results
    );

    public abstract void Close () throws GLib.Error;
}

public static async bool has_background_portal() {
    debug("has_background_portal(): start");
    try {
        if(yield dbus_service_available ("org.freedesktop.portal.Desktop")) {
          PortalBackground portal = yield Bus.get_proxy(
              BusType.SESSION,
              "org.freedesktop.portal.Desktop",
              "/org/freedesktop/portal/desktop",
              DBusProxyFlags.NONE
          );

          // Version 1 has RequestBackground, Version 2 adds SetStatus
          debug("org.freedesktop.portal.Background.version = %u", portal.version);
          return portal.version >= 1;
        }
        return false;
    } catch (Error e) {
        debug("has_background_portal(): error: %s", e.message);
        return false;
    }
}

public static async bool request_background_portal() throws Error {
    debug("request_background_portal: start");
    try {
        PortalBackground portal = yield Bus.get_proxy(BusType.SESSION, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop");



        // Build a predictable handle token and object path
        string handle_token = "dino_%u".printf(GLib.Random.next_int());

        // Get the sender name (e.g. ":1.169") and sanitize for use in a path
        string sender = (yield Bus.get(BusType.SESSION)).get_unique_name();
        string sender_path = sender.replace(".", "_").replace(":", "");

        string predicted_path = "/org/freedesktop/portal/desktop/request/%s/%s"
            .printf(sender_path, handle_token);

        debug("request_background_portal: pre-subscribing to result-handle %s", predicted_path);

        // Subscribe BEFORE making the call to avoid the race
        PortalRequest request = yield Bus.get_proxy(
            BusType.SESSION,
            "org.freedesktop.portal.Desktop",
            predicted_path
        );

        var options = new HashTable<string, Variant> (str_hash, str_equal);
        options.insert ("reason", new Variant.string ("Allow Dino to continue receiving messages"));
        // options.insert ("autostart", new Variant.boolean (true));
        // options.insert ("commandline", new Variant.strv ({"dino", "--gapplication-service"}));
        options.insert ("dbus-activatable", new Variant.boolean (true));
        options.insert ("handle_token", new Variant.string (handle_token));

        ObjectPath handle = yield portal.RequestBackground ("", options);
        // PortalRequest request = yield Bus.get_proxy (
        //         BusType.SESSION,
        //         "org.freedesktop.portal.Desktop",
        //         handle
        //     );
        debug("request_background_portal: actual temporary result handle is %s", handle);

        // var result = yield wait_for_response(request);

        // debug("DBUS Background Request returned %d", result);
        // return (result == 0);
        //
        //
        // Our helper now returns both the status and the data
      HashTable<string, Variant> results;
      uint response_code = yield wait_for_response(request, out results);
      debug("request_background_portal: got results:");

      // 1. Extract and format details for debugging
      string details = "";
      var iter = HashTableIter<string, Variant>(results);
      string key;
      Variant val;
      while (iter.next (out key, out val)) {
          details += @"\n - $key: $(val.print(false))";
      }
      debug("Portal Response Details: %s", details);

      // 2. Handle failure states
      if (response_code != 0) {
          if (response_code == 1) {
              throw new PortalError.CANCELLED("User cancelled background request.");
          } else {
              // Include the raw result and the details string in the error message
              throw new PortalError.FAILED(@"Portal returned error $response_code. Details: $details");
          }
      }

      debug("request_background_portal: returning true");
      return true;
    } catch (IOError e) {
        warning("Failed to query D-Bus: %s", e.message);
        debug("request_background_portal: returning false because %s", e.message);
        return false;
    }
    debug("request_background_portal: returning false");
    return false;
}

// displays a small status message alongside the tray
public static async void update_background_portal_status(string message) {
    try {
        PortalBackground portal = yield Bus.get_proxy(
            BusType.SESSION,
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop"
        );

        var status_options = new HashTable<string, Variant>(str_hash, str_equal);
        status_options.insert("message", new Variant.string(message));

        yield portal.SetStatus(status_options);
    } catch (Error e) {
        debug("Could not set background status: %s", e.message);
    }
}

private static async uint wait_for_response (PortalRequest request, out HashTable<string, Variant> results_out) {
    SourceFunc callback = wait_for_response.callback;
    uint response_val = 2; // Default to 'Other'
    HashTable<string, Variant> data = null;

    var h = request.Response.connect ((response, results) => {
        response_val = response;
        data = results;
        callback ();
    });

    yield;
    request.disconnect (h);

    results_out = data;
    return response_val;
}
        //
// private static async int wait_for_response (PortalRequest request) {
//     var task = new Task (request, null, (obj, res) => {
//         // This is the "finish" callback
//         debug("dbus portal background: in response finish callback");
//     });

//     ulong handler_id = 0;
//     handler_id = request.Response.connect ((response, results) => {
//         request.disconnect (handler_id);
//         task.return_int ((int) response);
//     });

//     // This is the standard Vala pattern to "wait" for a Task
//     return (int)task.propagate_int ();
// }

// private static async int wait_for_response (PortalRequest request) {
//     SourceFunc callback = wait_for_response.callback;
//     int response_val = -1;

//     ulong handler_id = request.Response.connect ((response, results) => {
//         response_val = (int) response;
//         callback (); // Resumes the async function
//     });

//     yield; // This suspends the method until callback() is called above

//     request.disconnect (handler_id);
//     return response_val;
// }
// private static async int wait_for_response (PortalRequest request) {
//     var task = new Task<int> (null, null);

//     var h = request.Response.connect ((response, results) => {
//         request.disconnect (h);
//         task.return ((int) response);
//     });

//     return yield task;
// }

}

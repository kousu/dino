using Gee;
using Gtk;
using Xmpp.Xep;

namespace Dino.Ui {

public class FormEditorDialog : Adw.Dialog {
    public signal void form_submitted(DataForms.DataForm form);

    private FormEditorWidget form_editor;
    private Button cancel_button;
    private Button submit_button;

    public FormEditorDialog(DataForms.DataForm? initial_form = null) {
        this.title = "Form Editor";
        this.content_width = 500;
        this.content_height = 600;

        build_ui(initial_form);
    }

    private void build_ui(DataForms.DataForm? initial_form) {
        var toolbar_view = new Adw.ToolbarView();

        // Header bar
        var header_bar = new Adw.HeaderBar();

        cancel_button = new Button.with_label("Cancel");
        cancel_button.clicked.connect(() => this.close());
        header_bar.pack_start(cancel_button);

        submit_button = new Button.with_label("Submit");
        submit_button.add_css_class("suggested-action");
        submit_button.clicked.connect(on_submit_clicked);
        header_bar.pack_end(submit_button);

        toolbar_view.add_top_bar(header_bar);

        // Main content
        var scrolled_window = new ScrolledWindow();
        scrolled_window.hscrollbar_policy = PolicyType.NEVER;
        scrolled_window.vscrollbar_policy = PolicyType.AUTOMATIC;

        form_editor = new FormEditorWidget(initial_form);
        scrolled_window.child = form_editor;

        toolbar_view.content = scrolled_window;

        this.child = toolbar_view;
    }

    private void on_submit_clicked() {
        var form = form_editor.get_form();
        string xml = form_editor.get_xml_string();
        debug("Form submitted:\n%s", xml);
        form_submitted(form);
        this.close();
    }

    public DataForms.DataForm get_form() {
        return form_editor.get_form();
    }
}

}

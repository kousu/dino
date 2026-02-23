using Gee;
using Gtk;
using Xmpp.Xep;

namespace Dino.Ui {

public class FormEditorWidget : Box {
    public signal void form_changed();

    private DataForms.DataForm form;
    private int field_counter = 0;

    // Header widgets
    private Adw.EntryRow title_entry;
    private Adw.EntryRow instructions_entry;
    private Adw.EntryRow form_type_entry;

    // Fields list
    private Adw.PreferencesGroup fields_group;
    private ListBox fields_list;
    private Button add_field_button;
    private Button remove_field_button;

    public FormEditorWidget(DataForms.DataForm? form = null) {
        Object(orientation: Orientation.VERTICAL, spacing: 12);

        this.margin_start = 12;
        this.margin_end = 12;
        this.margin_top = 12;
        this.margin_bottom = 12;

        if (form == null) {
            this.form = DataForms.DataForm.create_empty();
        } else {
            this.form = form;
        }

        build_ui();
        populate_fields();
    }

    private void build_ui() {
        // Header section
        var header_group = new Adw.PreferencesGroup() { title = "Form Properties" };

        title_entry = new Adw.EntryRow() { title = "Title" };
        title_entry.text = form.title ?? "";
        title_entry.changed.connect(() => form_changed());
        header_group.add(title_entry);

        instructions_entry = new Adw.EntryRow() { title = "Instructions" };
        instructions_entry.text = form.instructions ?? "";
        instructions_entry.changed.connect(() => form_changed());
        header_group.add(instructions_entry);

        form_type_entry = new Adw.EntryRow() { title = "Form Type (FORM_TYPE)" };
        form_type_entry.text = form.form_type ?? "";
        form_type_entry.changed.connect(() => form_changed());
        header_group.add(form_type_entry);

        this.append(header_group);

        // Fields section
        fields_group = new Adw.PreferencesGroup() { title = "Fields" };

        fields_list = new ListBox() { selection_mode = SelectionMode.NONE };
        fields_list.add_css_class("boxed-list");
        fields_group.add(fields_list);

        // Toolbar for add/remove
        var toolbar_box = new Box(Orientation.HORIZONTAL, 6);
        toolbar_box.margin_top = 6;
        toolbar_box.halign = Align.END;

        add_field_button = new Button.from_icon_name("list-add-symbolic");
        add_field_button.tooltip_text = "Add field";
        add_field_button.add_css_class("flat");
        add_field_button.clicked.connect(on_add_field);
        toolbar_box.append(add_field_button);

        remove_field_button = new Button.from_icon_name("list-remove-symbolic");
        remove_field_button.tooltip_text = "Remove selected field";
        remove_field_button.add_css_class("flat");
        remove_field_button.sensitive = false;
        toolbar_box.append(remove_field_button);

        fields_group.add(toolbar_box);

        this.append(fields_group);
    }

    private void populate_fields() {
        foreach (var field in form.fields) {
            add_field_row(field);
        }
    }

    private void add_field_row(DataForms.DataForm.Field field) {
        var row = new FormFieldEditorRow(field);
        row.remove_requested.connect(() => {
            fields_list.remove(row.parent);
            form_changed();
        });
        row.field_changed.connect(() => form_changed());
        fields_list.append(row);
    }

    private void on_add_field() {
        field_counter++;
        string var_name = "field_%d".printf(field_counter);
        var field = DataForms.DataForm.Field.create(
            DataForms.DataForm.Type.TEXT_SINGLE,
            var_name,
            null
        );
        add_field_row(field);

        // Expand the new row for editing
        Widget? child = fields_list.get_last_child();
        if (child != null) {
            var row = child as ListBoxRow;
            if (row != null) {
                var expander_row = row.child as FormFieldEditorRow;
                if (expander_row != null) {
                    expander_row.expanded = true;
                }
            }
        }

        form_changed();
    }

    public DataForms.DataForm get_form() {
        // Create a fresh form with current values
        var result = DataForms.DataForm.create_empty();

        // Set title
        if (title_entry.text != "") {
            var title_node = new Xmpp.StanzaNode.build("title", DataForms.NS_URI);
            title_node.put_node(new Xmpp.StanzaNode.text(title_entry.text));
            result.stanza_node.put_node(title_node);
            result.title = title_entry.text;
        }

        // Set instructions
        if (instructions_entry.text != "") {
            var instructions_node = new Xmpp.StanzaNode.build("instructions", DataForms.NS_URI);
            instructions_node.put_node(new Xmpp.StanzaNode.text(instructions_entry.text));
            result.stanza_node.put_node(instructions_node);
            result.instructions = instructions_entry.text;
        }

        // Set form type as hidden field
        if (form_type_entry.text != "") {
            var form_type_field = new DataForms.DataForm.HiddenField();
            form_type_field.var = "FORM_TYPE";
            form_type_field.set_value_string(form_type_entry.text);
            result.stanza_node.put_node(form_type_field.node);
            result.form_type = form_type_entry.text;
        }

        // Add all fields
        Widget? child = fields_list.get_first_child();
        while (child != null) {
            var row = child as ListBoxRow;
            if (row != null) {
                var field_row = row.child as FormFieldEditorRow;
                if (field_row != null) {
                    var field = field_row.get_field();
                    result.add_field(field);
                }
            }
            child = child.get_next_sibling();
        }

        return result;
    }

    public string get_xml_string() {
        var form = get_form();
        return form.stanza_node.to_xml();
    }
}

}

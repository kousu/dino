using Gee;
using Gtk;
using Xmpp.Xep;

namespace Dino.Ui {

public class FormFieldEditorRow : Adw.ExpanderRow {
    public signal void remove_requested();
    public signal void field_changed();

    private DataForms.DataForm.Field field;

    // Collapsed state widgets (value editing)
    private Widget? value_widget = null;

    // Expanded state widgets (field editing)
    private Adw.EntryRow label_entry;
    private Adw.EntryRow var_entry;
    private Adw.ComboRow type_combo;
    private Adw.PreferencesGroup options_group;
    private ListBox options_list;
    private Button add_option_button;
    private Button remove_field_button;

    private static string[] TYPE_LABELS = {
        "Text",
        "Password",
        "Boolean",
        "List (single)",
        "List (multi)",
        "Fixed",
        "Hidden"
    };

    private static DataForms.DataForm.Type[] TYPE_VALUES = {
        DataForms.DataForm.Type.TEXT_SINGLE,
        DataForms.DataForm.Type.TEXT_PRIVATE,
        DataForms.DataForm.Type.BOOLEAN,
        DataForms.DataForm.Type.LIST_SINGLE,
        DataForms.DataForm.Type.LIST_MULTI,
        DataForms.DataForm.Type.FIXED,
        DataForms.DataForm.Type.HIDDEN
    };

    public FormFieldEditorRow(DataForms.DataForm.Field field) {
        this.field = field;
        this.show_enable_switch = false;

        update_title();
        build_collapsed_widget();
        build_expanded_widgets();

        this.notify["expanded"].connect(() => {
            if (!expanded) {
                apply_changes();
            }
        });
    }

    private void update_title() {
        string title_text = field.label ?? field.var ?? "Untitled Field";
        this.title = title_text;
        this.subtitle = get_type_label(field.type_);
    }

    private string get_type_label(DataForms.DataForm.Type? type_) {
        if (type_ == null) return "Unknown";
        for (int i = 0; i < TYPE_VALUES.length; i++) {
            if (TYPE_VALUES[i] == type_) return TYPE_LABELS[i];
        }
        return "Unknown";
    }

    private int get_type_index(DataForms.DataForm.Type? type_) {
        if (type_ == null) return 0;
        for (int i = 0; i < TYPE_VALUES.length; i++) {
            if (TYPE_VALUES[i] == type_) return i;
        }
        return 0;
    }

    private void build_collapsed_widget() {
        value_widget = create_value_widget();
        if (value_widget != null) {
            this.add_suffix(value_widget);
        }
    }

    private Widget? create_value_widget() {
        if (field.type_ == null) return null;

        switch (field.type_) {
            case DataForms.DataForm.Type.BOOLEAN:
                var boolean_field = field as DataForms.DataForm.BooleanField;
                var toggle = new Switch() { valign = Align.CENTER };
                toggle.active = boolean_field.value;
                toggle.notify["active"].connect(() => {
                    boolean_field.value = toggle.active;
                    field_changed();
                });
                return toggle;

            case DataForms.DataForm.Type.TEXT_SINGLE:
                var text_field = field as DataForms.DataForm.TextSingleField;
                var entry = new Entry() { valign = Align.CENTER, width_chars = 20 };
                entry.text = text_field.value ?? "";
                entry.changed.connect(() => {
                    text_field.value = entry.text;
                    field_changed();
                });
                return entry;

            case DataForms.DataForm.Type.TEXT_PRIVATE:
                var private_field = field as DataForms.DataForm.TextPrivateField;
                var entry = new PasswordEntry() { valign = Align.CENTER, width_chars = 20 };
                entry.text = private_field.value ?? "";
                entry.changed.connect(() => {
                    private_field.value = entry.text;
                    field_changed();
                });
                return entry;

            case DataForms.DataForm.Type.LIST_SINGLE:
                var list_field = field as DataForms.DataForm.ListSingleField;
                var string_list = new StringList(null);
                int selected = 0;
                int i = 0;
                foreach (var option in list_field.options) {
                    string_list.append(option.label ?? option.value);
                    if (option.value == list_field.value) selected = i;
                    i++;
                }
                var dropdown = new DropDown(string_list, null) { valign = Align.CENTER };
                dropdown.selected = selected;
                dropdown.notify["selected"].connect(() => {
                    var options = list_field.options;
                    if (dropdown.selected < options.size) {
                        list_field.value = options[(int)dropdown.selected].value;
                        field_changed();
                    }
                });
                return dropdown;

            case DataForms.DataForm.Type.FIXED:
                var fixed_field = field as DataForms.DataForm.FixedField;
                var label = new Label(fixed_field.value ?? "") { valign = Align.CENTER };
                return label;

            case DataForms.DataForm.Type.HIDDEN:
                var label = new Label("(hidden)") { valign = Align.CENTER, sensitive = false };
                return label;

            default:
                return null;
        }
    }

    private void build_expanded_widgets() {
        // Type selector
        var type_string_list = new StringList(null);
        foreach (string label in TYPE_LABELS) {
            type_string_list.append(label);
        }
        type_combo = new Adw.ComboRow() { title = "Type" };
        type_combo.model = type_string_list;
        type_combo.selected = get_type_index(field.type_);
        type_combo.notify["selected"].connect(on_type_changed);
        this.add_row(type_combo);

        // Label entry
        label_entry = new Adw.EntryRow() { title = "Label" };
        label_entry.text = field.label ?? "";
        this.add_row(label_entry);

        // Var entry
        var_entry = new Adw.EntryRow() { title = "Variable ID" };
        var_entry.text = field.var ?? "";
        this.add_row(var_entry);

        // Options editor (for LIST_SINGLE/LIST_MULTI)
        options_group = new Adw.PreferencesGroup() { title = "Options" };
        options_list = new ListBox() { selection_mode = SelectionMode.NONE };
        options_list.add_css_class("boxed-list");
        options_group.add(options_list);

        add_option_button = new Button.with_label("Add Option");
        add_option_button.add_css_class("pill");
        add_option_button.margin_top = 6;
        add_option_button.clicked.connect(on_add_option_clicked);
        options_group.add(add_option_button);

        var options_box = new Box(Orientation.VERTICAL, 0);
        options_box.append(options_group);
        this.add_row(new Adw.PreferencesRow() { child = options_box });

        update_options_visibility();
        populate_options_list();

        // Remove button
        remove_field_button = new Button.with_label("Remove Field");
        remove_field_button.add_css_class("destructive-action");
        remove_field_button.add_css_class("pill");
        remove_field_button.margin_top = 12;
        remove_field_button.margin_bottom = 12;
        remove_field_button.halign = Align.CENTER;
        remove_field_button.clicked.connect(() => remove_requested());

        var remove_row = new Adw.PreferencesRow();
        var remove_box = new Box(Orientation.VERTICAL, 0);
        remove_box.append(remove_field_button);
        remove_row.child = remove_box;
        this.add_row(remove_row);
    }

    private void update_options_visibility() {
        bool show_options = field.type_ == DataForms.DataForm.Type.LIST_SINGLE ||
                           field.type_ == DataForms.DataForm.Type.LIST_MULTI;
        options_group.visible = show_options;
    }

    private void populate_options_list() {
        // Clear existing options
        Widget? child = options_list.get_first_child();
        while (child != null) {
            options_list.remove(child);
            child = options_list.get_first_child();
        }

        // Add current options
        if (field.type_ == DataForms.DataForm.Type.LIST_SINGLE) {
            var list_field = field as DataForms.DataForm.ListSingleField;
            foreach (var option in list_field.options) {
                add_option_row(option.label, option.value);
            }
        } else if (field.type_ == DataForms.DataForm.Type.LIST_MULTI) {
            var list_field = field as DataForms.DataForm.ListMultiField;
            foreach (var option in list_field.options) {
                add_option_row(option.label, option.value);
            }
        }
    }

    private void add_option_row(string label, string value) {
        var row = new Adw.ActionRow() { title = label, subtitle = value };
        var remove_btn = new Button.from_icon_name("user-trash-symbolic") { valign = Align.CENTER };
        remove_btn.add_css_class("flat");
        remove_btn.clicked.connect(() => {
            options_list.remove(row);
        });
        row.add_suffix(remove_btn);
        options_list.append(row);
    }

    private void on_add_option_clicked() {
        var dialog = new Adw.AlertDialog("Add Option", null);
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("add", "Add");
        dialog.default_response = "add";
        dialog.close_response = "cancel";

        var content_box = new Box(Orientation.VERTICAL, 12);
        content_box.margin_start = 24;
        content_box.margin_end = 24;
        content_box.margin_top = 12;
        content_box.margin_bottom = 12;

        var option_label_entry = new Adw.EntryRow() { title = "Label" };
        var option_value_entry = new Adw.EntryRow() { title = "Value" };

        var prefs_group = new Adw.PreferencesGroup();
        prefs_group.add(option_label_entry);
        prefs_group.add(option_value_entry);
        content_box.append(prefs_group);

        dialog.extra_child = content_box;

        dialog.response.connect((response) => {
            if (response == "add") {
                string opt_label = option_label_entry.text;
                string opt_value = option_value_entry.text;
                if (opt_value == "") opt_value = opt_label;
                if (opt_label == "") opt_label = opt_value;
                if (opt_label != "" || opt_value != "") {
                    add_option_row(opt_label, opt_value);
                }
            }
        });

        dialog.present((Window)this.get_root());
    }

    private void on_type_changed() {
        var new_type = TYPE_VALUES[type_combo.selected];
        if (new_type != field.type_) {
            // Create new field with new type
            string var_name = var_entry.text != "" ? var_entry.text : field.var ?? "field";
            string? label = label_entry.text != "" ? label_entry.text : field.label;
            field = DataForms.DataForm.Field.create(new_type, var_name, label);
            update_options_visibility();
            populate_options_list();
            rebuild_value_widget();
            update_title();
            field_changed();
        }
    }

    private void rebuild_value_widget() {
        if (value_widget != null) {
            this.remove(value_widget);
            value_widget = null;
        }
        value_widget = create_value_widget();
        if (value_widget != null) {
            this.add_suffix(value_widget);
        }
    }

    private void apply_changes() {
        // Apply label and var changes
        if (label_entry.text != "") {
            field.label = label_entry.text;
        }
        if (var_entry.text != "") {
            field.var = var_entry.text;
        }

        // Apply options changes for list types
        if (field.type_ == DataForms.DataForm.Type.LIST_SINGLE) {
            var list_field = field as DataForms.DataForm.ListSingleField;
            list_field.clear_options();
            Widget? child = options_list.get_first_child();
            while (child != null) {
                var row = child as ListBoxRow;
                if (row != null) {
                    var action_row = row.child as Adw.ActionRow;
                    if (action_row != null) {
                        list_field.add_option(action_row.title, action_row.subtitle);
                    }
                }
                child = child.get_next_sibling();
            }
        } else if (field.type_ == DataForms.DataForm.Type.LIST_MULTI) {
            var list_field = field as DataForms.DataForm.ListMultiField;
            list_field.clear_options();
            Widget? child = options_list.get_first_child();
            while (child != null) {
                var row = child as ListBoxRow;
                if (row != null) {
                    var action_row = row.child as Adw.ActionRow;
                    if (action_row != null) {
                        list_field.add_option(action_row.title, action_row.subtitle);
                    }
                }
                child = child.get_next_sibling();
            }
        }

        update_title();
        rebuild_value_widget();
        field_changed();
    }

    public DataForms.DataForm.Field get_field() {
        apply_changes();
        return field;
    }
}

}

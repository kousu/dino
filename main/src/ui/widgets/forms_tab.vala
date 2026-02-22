using Gtk;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/dino/Dino/forms_tab.ui")]
public class FormsTab : Box {

    [GtkChild] public unowned ListBox forms_list;
    [GtkChild] public unowned Button add_button;
    [GtkChild] public unowned Button remove_button;

    construct {
        forms_list.row_selected.connect((row) => {
            remove_button.sensitive = (row != null);
        });
        add_button.clicked.connect(() => {
            // TODO: Open dialog to add a form template
            print("Add form clicked\n");
        });
        remove_button.clicked.connect(() => {
            var selected_row = forms_list.get_selected_row();
            if (selected_row != null) {
                // TODO: Remove the selected form template
                print("Remove form clicked\n");
                forms_list.remove(selected_row);
            }
        });
    }
}

}

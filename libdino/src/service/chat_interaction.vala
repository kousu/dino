using Gee;

using Xmpp;
using Dino.Entities;

namespace Dino {

public class ChatInteraction : StreamInteractionModule, Object {
    public static ModuleIdentity<ChatInteraction> IDENTITY = new ModuleIdentity<ChatInteraction>("chat_interaction");
    public string id { get { return IDENTITY.id; } }

    public signal void focused_in(Conversation conversation);
    public signal void focused_out(Conversation conversation);

    private StreamInteractor stream_interactor;
    private Conversation? selected_conversation;

    private HashMap<Conversation, DateTime> last_input_interaction = new HashMap<Conversation, DateTime>(Conversation.hash_func, Conversation.equals_func);
    private HashMap<Conversation, DateTime> last_interface_interaction = new HashMap<Conversation, DateTime>(Conversation.hash_func, Conversation.equals_func);
    private HashMap<Conversation, int> unread_cache = new HashMap<Conversation, int>(Conversation.hash_func, Conversation.equals_func);
    public int total_unread { get; private set; default = 0; }
    private HashMap<Conversation, bool> notifications_cache = new HashMap<Conversation, bool>(Conversation.hash_func, Conversation.equals_func);
    public bool has_any_notifications { get; private set; default = false; }
    private HashMap<Conversation, ulong> conversation_NotifySetting_handlers = new HashMap<Conversation, ulong>(Conversation.hash_func, Conversation.equals_func);
    private bool focus_in = false;

    public static void start(StreamInteractor stream_interactor) {
        ChatInteraction m = new ChatInteraction(stream_interactor);
        stream_interactor.add_module(m);
    }

    private ChatInteraction(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
        Timeout.add_seconds(30, update_interactions);
        stream_interactor.get_module(MessageProcessor.IDENTITY).received_pipeline.connect(new ReceivedMessageListener(stream_interactor));
        stream_interactor.get_module(MessageProcessor.IDENTITY).message_sent.connect(on_message_sent);
        stream_interactor.get_module(ContentItemStore.IDENTITY).new_item.connect(new_item);
        // fill and empty caches:
        stream_interactor.get_module(ConversationManager.IDENTITY).conversation_activated.connect((conversation) => {
            get_num_unread(conversation);
            has_notifications(conversation);
            conversation_NotifySetting_handlers[conversation] = conversation.notify["notify-setting"].connect(() => {
                forget_notifications(conversation);
                has_notifications(conversation);
            });
        });
        stream_interactor.get_module(ConversationManager.IDENTITY).conversation_deactivated.connect((conversation) => {
            if (conversation_NotifySetting_handlers.has_key(conversation)) {
                conversation.disconnect(conversation_NotifySetting_handlers[conversation]);
                conversation_NotifySetting_handlers.unset(conversation);
            }
            forget_num_unread(conversation);
            forget_notifications(conversation);
        });
    }

    public int get_num_unread(Conversation conversation) {
        if (!unread_cache.has_key(conversation)) {
            unread_cache[conversation] = query_num_unread(conversation);
            total_unread += unread_cache[conversation];
        }
        return unread_cache[conversation];
    }

    public bool has_notifications(Conversation conversation) {
        if (!notifications_cache.has_key(conversation)) {
            bool result = query_has_unread_notifications(conversation);
            notifications_cache[conversation] = result;
            if (result) has_any_notifications = true;
        }
        return notifications_cache[conversation];
    }

    private void forget_notifications(Conversation conversation) {
        notifications_cache.unset(conversation);
        bool any = false;
        foreach (bool v in notifications_cache.values) {
            if (v) { any = true; break; }
        }
        has_any_notifications = any;
    }

    private void forget_num_unread(Conversation conversation) {
        // drop conversation from unread_cache
        // this doesn't change the _actual_ unread count, it's
        // just cold in the db instead of warm in the cache.
        if (unread_cache.has_key(conversation)) {
            total_unread -= unread_cache[conversation];
            unread_cache.unset(conversation);
        }
    }

    private int query_num_unread(Conversation conversation) {
        Database db = Dino.Application.get_default().db;

        Qlite.QueryBuilder query = db.content_item.select()
                .with(db.content_item.conversation_id, "=", conversation.id)
                .with(db.content_item.hide, "=", false);

        ContentItem? read_up_to_item = stream_interactor.get_module(ContentItemStore.IDENTITY).get_item_by_id(conversation, conversation.read_up_to_item);
        if (read_up_to_item != null) {
            string time = read_up_to_item.time.to_unix().to_string();
            string id = read_up_to_item.id.to_string();
            query.where(@"time > ? OR (time = ? AND id > ?)", { time, time, id });
        }
        // If it's a new conversation with read_up_to_item == null, all items are new.

        return (int) query.count();
    }

    private int query_num_unread_mentions(Conversation conversation) {
        // count the number of unread _mentions_ (corresponding to NotifySetting.HIGHLIGHT)
        // this could be inaccurate if the user has changed their nick recently

        // mentions (NotifySetting.HIGHLIGHT) only happens for MUCs;
        // in DMs, the only notify options are On (NotifySetting.ON) or Mute (NotifySetting.OFF)
        if(conversation.type_ != Conversation.Type.GROUPCHAT) return 0;

        Jid? nick = stream_interactor.get_module(MucManager.IDENTITY).get_own_jid(conversation.counterpart, conversation.account);
        if (nick == null || nick.resourcepart == null) return 0;

        Database db = Dino.Application.get_default().db;

        // use the full-text-search that's set up for searching message history
        // to efficiently find messages containing nick.resourcepart.
        Qlite.QueryBuilder query = db.message
            .match(db.message.body, "\"" + nick.resourcepart.replace("\"", "\"\"") + "\"") // this is what invokes full text search
            .join_on(db.content_item, "message.id=content_item.foreign_id AND content_item.content_type=1")
            .with(db.content_item.conversation_id, "=", conversation.id)
            .with(db.content_item.hide, "=", false);

        ContentItem? read_up_to_item = stream_interactor.get_module(ContentItemStore.IDENTITY).get_item_by_id(conversation, conversation.read_up_to_item);
        if (read_up_to_item != null) {
            string time = read_up_to_item.time.to_unix().to_string();
            string id = read_up_to_item.id.to_string();
            query.where(@"content_item.time > ? OR (content_item.time = ? AND content_item.id > ?)", { time, time, id });
        }

        // do a second more accurate pass using is_mention(), because the
        // full-text search has false-positives (e.g. the username "i-am-awesome"
        // matches sentence "I am awesome!" in sqlite FTS).
        int count = 0;
        foreach (Qlite.Row row in query) {
            string? body = row[db.message.body];
            if (body != null && is_mention(stream_interactor, conversation, body)) {
                count++;
            }
        }
        return count;
    }

    private bool query_has_unread_notifications(Conversation conversation) {
        switch (conversation.get_notification_setting(stream_interactor)) {
          case Conversation.NotifySetting.ON:
            return get_num_unread(conversation) > 0;
          case Conversation.NotifySetting.HIGHLIGHT:
            return query_num_unread_mentions(conversation) > 0;
          case Conversation.NotifySetting.OFF:
            return false;
          default:
            assert_not_reached();
        }
    }

    public bool is_active_focus(Conversation? conversation = null) {
        if (conversation != null) {
            return focus_in && conversation.equals(this.selected_conversation);
        } else {
            return focus_in;
        }
    }

    public void on_window_focus_in(Conversation? conversation) {
        on_conversation_focused(conversation);
    }

    public void on_window_focus_out(Conversation? conversation) {
        on_conversation_unfocused(conversation);
    }

    public void on_message_entered(Conversation? conversation) {
        if (!last_input_interaction.has_key(conversation)) {
            send_chat_state_notification(conversation, Xep.ChatStateNotifications.STATE_COMPOSING);
        }
        last_input_interaction[conversation] = new DateTime.now_utc();
        last_interface_interaction[conversation] = new DateTime.now_utc();
    }

    public void on_message_cleared(Conversation? conversation) {
        if (last_input_interaction.has_key(conversation)) {
            last_input_interaction.unset(conversation);
            send_chat_state_notification(conversation, Xep.ChatStateNotifications.STATE_ACTIVE);
        }
    }

    public void on_conversation_selected(Conversation conversation) {
        on_conversation_unfocused(selected_conversation);
        selected_conversation = conversation;
        on_conversation_focused(conversation);
    }

    private void new_item(ContentItem item, Conversation conversation) {
        bool mark_read = is_active_focus(conversation);

        if (!mark_read) {
            MessageItem? message_item = item as MessageItem;
            if (message_item != null) {
                if (message_item.message.direction == Message.DIRECTION_SENT) {
                    mark_read = true;
                }
            }
            if (message_item == null) {
                FileItem? file_item = item as FileItem;
                if (file_item != null) {
                    if (file_item.file_transfer.direction == FileTransfer.DIRECTION_SENT) {
                        mark_read = true;
                    }
                }
            }
        }
        if (mark_read) {
            ContentItem? read_up_to = stream_interactor.get_module(ContentItemStore.IDENTITY).get_item_by_id(conversation, conversation.read_up_to_item);
            if (read_up_to != null) {
                if (read_up_to.compare(item) < 0) {
                    conversation.read_up_to_item = item.id;
                }
            } else {
                conversation.read_up_to_item = item.id;
            }
        } else {
            // we're leaving this message unread.

            // keep unread_cache in sync:
            if (unread_cache.has_key(conversation)) {
                unread_cache[conversation] = unread_cache[conversation] + 1;
                total_unread++;
            }

            // keep notifications_cache in sync:
            if (!(notifications_cache.has_key(conversation) && notifications_cache[conversation])) {
                bool notifies;
                switch (conversation.get_notification_setting(stream_interactor)) {
                    case Conversation.NotifySetting.ON:
                        notifies = true;
                        break;
                    case Conversation.NotifySetting.HIGHLIGHT:
                        MessageItem? msg = item as MessageItem;
                        notifies = msg != null && msg.message.body != null
                            && is_mention(stream_interactor, conversation, msg.message.body);
                        break;
                    default:
                        notifies = false;
                        break;
                }
                if (notifies) {
                    notifications_cache[conversation] = true;
                    has_any_notifications = true;
                }
            }
        }
    }

    private void on_message_sent(Entities.Message message, Conversation conversation) {
        last_input_interaction.unset(conversation);
        last_interface_interaction.unset(conversation);
    }

    private void on_conversation_focused(Conversation? conversation) {
        focus_in = true;
        if (conversation == null) return;
        focused_in(conversation);
        check_send_read();

        ContentItem? latest_item = stream_interactor.get_module(ContentItemStore.IDENTITY).get_latest(conversation);
        if (latest_item != null) {
            conversation.read_up_to_item = latest_item.id;
        }

        // Dino currently assumes that an open conversation is one where all the
        // messages are read (whether or not actually it's scrolled to the bottom)
        // so zero out the unread count.
        forget_num_unread(conversation);
        forget_notifications(conversation);
    }

    private void on_conversation_unfocused(Conversation? conversation) {
        focus_in = false;
        if (conversation == null) return;
        focused_out(conversation);
        if (last_input_interaction.has_key(conversation)) {
            send_chat_state_notification(conversation, Xep.ChatStateNotifications.STATE_PAUSED);
            last_input_interaction.unset(conversation);
        }
    }

    private void check_send_read() {
        if (selected_conversation == null) return;
        Entities.Message? message = stream_interactor.get_module(MessageStorage.IDENTITY).get_last_message(selected_conversation);
        if (message != null && message.direction == Entities.Message.DIRECTION_RECEIVED) {
            send_chat_marker(message, null, selected_conversation, Xep.ChatMarkers.MARKER_DISPLAYED);
        }
    }

    private bool update_interactions() {
        for (MapIterator<Conversation, DateTime> iter = last_input_interaction.map_iterator(); iter.has_next(); iter.next()) {
            if (!iter.valid && iter.has_next()) iter.next();
            Conversation conversation = iter.get_key();
            if (last_input_interaction.has_key(conversation) &&
                    (new DateTime.now_utc()).difference(last_input_interaction[conversation]) >= 15 *  TimeSpan.SECOND) {
                iter.unset();
                send_chat_state_notification(conversation, Xep.ChatStateNotifications.STATE_PAUSED);
            }
        }
        for (MapIterator<Conversation, DateTime> iter = last_interface_interaction.map_iterator(); iter.has_next(); iter.next()) {
            if (!iter.valid && iter.has_next()) iter.next();
            Conversation conversation = iter.get_key();
            if (last_interface_interaction.has_key(conversation) &&
                    (new DateTime.now_utc()).difference(last_interface_interaction[conversation]) >= 1.5 *  TimeSpan.MINUTE) {
                iter.unset();
                send_chat_state_notification(conversation, Xep.ChatStateNotifications.STATE_GONE);
            }
        }
        return true;
    }

    private class ReceivedMessageListener : MessageListener {

        public string[] after_actions_const = new string[]{ "DEDUPLICATE", "FILTER_EMPTY", "STORE_CONTENT_ITEM" };
        public override string action_group { get { return "OTHER_NODES"; } }
        public override string[] after_actions { get { return after_actions_const; } }

        private StreamInteractor stream_interactor;

        public ReceivedMessageListener(StreamInteractor stream_interactor) {
            this.stream_interactor = stream_interactor;
        }

        public override async bool run(Entities.Message message, Xmpp.MessageStanza stanza, Conversation conversation) {
            if (Xmpp.MessageArchiveManagement.MessageFlag.get_flag(stanza) != null) return false;

            ChatInteraction outer = stream_interactor.get_module(ChatInteraction.IDENTITY);
            outer.send_delivery_receipt(message, stanza, conversation);

            // Send chat marker
            if (message.direction == Entities.Message.DIRECTION_SENT) return false;
            if (outer.is_active_focus(conversation)) {
                outer.check_send_read();
                outer.send_chat_marker(message, stanza, conversation, Xep.ChatMarkers.MARKER_DISPLAYED);
            } else {
                outer.send_chat_marker(message, stanza, conversation, Xep.ChatMarkers.MARKER_RECEIVED);
            }
            return false;
        }
    }


    private void send_chat_marker(Entities.Message message, Xmpp.MessageStanza? stanza, Conversation conversation, string marker) {
        XmppStream? stream = stream_interactor.get_stream(conversation.account);
        if (stream == null) return;

        switch (marker) {
            case Xep.ChatMarkers.MARKER_RECEIVED:
                if (stanza != null && Xep.ChatMarkers.Module.requests_marking(stanza) && message.type_ != Message.Type.GROUPCHAT) {
                    if (message.stanza_id == null) return;
                    stream.get_module(Xep.ChatMarkers.Module.IDENTITY).send_marker(stream, message.from, message.stanza_id, message.get_type_string(), Xep.ChatMarkers.MARKER_RECEIVED);
                }
                break;
            case Xep.ChatMarkers.MARKER_DISPLAYED:
                if (conversation.get_send_marker_setting(stream_interactor) == Conversation.Setting.ON) {
                    if (message.equals(conversation.read_up_to)) return;
                    conversation.read_up_to = message;

                    if (message.type_ == Message.Type.GROUPCHAT || message.type_ == Message.Type.GROUPCHAT_PM) {
                        if (message.server_id == null) return;
                        stream.get_module(Xep.ChatMarkers.Module.IDENTITY).send_marker(stream, message.from.bare_jid, message.server_id, message.get_type_string(), Xep.ChatMarkers.MARKER_DISPLAYED);
                    } else {
                        if (message.stanza_id == null) return;
                        stream.get_module(Xep.ChatMarkers.Module.IDENTITY).send_marker(stream, message.from, message.stanza_id, message.get_type_string(), Xep.ChatMarkers.MARKER_DISPLAYED);
                    }
                }
                break;
        }
    }

    private void send_delivery_receipt(Entities.Message message, Xmpp.MessageStanza stanza, Conversation conversation) {
        if (message.direction == Entities.Message.DIRECTION_SENT) return;
        if (!Xep.MessageDeliveryReceipts.Module.requests_receipt(stanza)) return;
        if (conversation.type_ == Conversation.Type.GROUPCHAT) return;

        XmppStream? stream = stream_interactor.get_stream(conversation.account);
        if (stream != null) {
            stream.get_module(Xep.MessageDeliveryReceipts.Module.IDENTITY).send_received(stream, message.from, message.stanza_id);
        }
    }

    private void send_chat_state_notification(Conversation conversation, string state) {
        if (conversation.get_send_typing_setting(stream_interactor) != Conversation.Setting.ON) return;

        XmppStream? stream = stream_interactor.get_stream(conversation.account);
        if (stream != null) {
            string message_type = conversation.type_ == Conversation.Type.GROUPCHAT ? Xmpp.MessageStanza.TYPE_GROUPCHAT : Xmpp.MessageStanza.TYPE_CHAT;
            stream.get_module(Xep.ChatStateNotifications.Module.IDENTITY).send_state(stream, conversation.counterpart, message_type, state);
        }
    }
}

}

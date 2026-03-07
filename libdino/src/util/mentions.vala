using Dino.Entities;
using Xmpp;

namespace Dino {

// Returns true if body contains a mention of the user's nick in conversation;
// only applies to group chats.
public bool is_mention(StreamInteractor stream_interactor, Conversation conversation, string body) {
    if (conversation.type_ != Conversation.Type.GROUPCHAT) return false;
    Jid? nick = stream_interactor.get_module(MucManager.IDENTITY).get_own_jid(conversation.counterpart, conversation.account);
    if (nick == null || nick.resourcepart == null) return false;
    string nick_pattern = "\\b" + Regex.escape_string(nick.resourcepart) + "\\b";
    return Regex.match_simple(nick_pattern, body, RegexCompileFlags.CASELESS);
}

}

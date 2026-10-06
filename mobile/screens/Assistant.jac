"""Ask Morrow: chat with the planning assistant, same as the web's.

Every message goes to the server's assistant (core/assistant.jac) through
the ChatSend walker; it may plan, move or add things and lists what it
changed.
"""

import from "react" { useRef }
import from "@jac/mobui" { View, Text, TextInput, ScrollView, Pressable }
import from core.mobile_api { ChatState, ChatSend, ChatReset }
import type from core.models { ChatMessage }
import from ..theme { C, S, R, F, Z, styles }
import from ..lib { error_text }
import from ..components.kit { Button }
import from ..components.MorrowFace { MorrowFace }
import from ..components.Icon { Icon }

glob EXAMPLES: list[str] = [
    "What's on my plate this week?",
    "Plan my week and explain the suggestions",
    "Add a 2-hour PSYCH paper due Friday 5pm",
    "I don't want to work after 8pm"
];

"""One chat bubble (client-side; server types can't be built on the client)."""
obj Bubble {
    has role: str, text: str, actions: list[str] = [];
}

def to_bubble(m: ChatMessage) -> Bubble {
    return Bubble(role=m.role, text=m.text, actions=m.actions);
}

def:pub AssistantScreen(pointer: list[float]) -> JsxElement {
    has messages: list[Bubble] = [],
        draft: str = "",
        busy: bool = False,
        error: str = "",
        configured: bool = True,
        model: str = "";
    log: any = useRef(None);                 # the message ScrollView

    async can with entry {
        try {
            r = (root spawn ChatState()).reports;
            configured = r[0].configured;
            model = r[0].model;
            messages = [to_bubble(m) for m in r[1]];
        } except Exception as e {
            error = error_text(e);
        }
    }

    async def send_text(text: str) {
        text = text.strip();
        if not text or busy {
            return;
        }
        error = "";
        draft = "";
        messages = messages + [Bubble(role="user", text=text, actions=[])];
        busy = True;
        try {
            r = (root spawn ChatSend(message=text)).reports[0];
            if r.error {
                error = r.error;
            } else {
                messages = messages + [Bubble(role="assistant", text=r.reply, actions=r.actions)];
            }
        } except Exception as e {
            error = error_text(e);
        }
        busy = False;
    }

    async def new_chat {
        try {
            root spawn ChatReset();
            messages = [];
            error = "";
        } except Exception as e {
            error = error_text(e);
        }
    }

    def scroll_to_end {
        el: any = log.current;
        if el { el.scrollToEnd({"animated": True}); }
    }

    bubble = {"maxWidth": "85%", "paddingVertical": S.sm, "paddingHorizontal": S.md, "borderRadius": R.card};

    <View style={styles.screen}>
        <View style={[styles.content, {"flex": 1, "paddingBottom": Z.tabBar + S.sm}]}>
            <View style={[styles.row, {"gap": S.md}]}>
                <MorrowFace pointer={pointer}/>
                <View style={{"flex": 1}}>
                    <Text style={styles.eyebrow}>ASK MORROW</Text>
                    <Text style={[styles.h1, {"fontSize": F.xl}]}>Planning assistant</Text>
                </View>
                <Button label="New chat" small={True} variant="ghost" onPress={new_chat} disabled={busy}/>
            </View>
            {(<Text style={styles.error}>The assistant needs a free Gemini key: add GEMINI_API_KEY to .env on the server and restart it.</Text>) if not configured else <View/>}

            <ScrollView ref={log} style={{"flex": 1}} contentContainerStyle={{"gap": S.sm, "paddingVertical": S.sm}}
                onContentSizeChange={scroll_to_end}>
                {(
                    <View style={{"gap": S.sm}}>
                        <Text style={styles.hint}>Ask about your schedule, or have it plan and change things for you. It lists everything it changes. Try:</Text>
                        {[<Pressable key={ex} onPress={lambda { send_text(ex); }}
                            style={{"alignSelf": "flex-start", "borderWidth": 1, "borderColor": C.borderStrong, "borderRadius": R.pill,
                                    "paddingVertical": S.xs + S.xxs, "paddingHorizontal": S.md, "backgroundColor": C.surface}}>
                            <Text style={{"color": C.text, "fontSize": F.sm}}>{ex}</Text></Pressable> for ex in EXAMPLES]}
                    </View>
                ) if len(messages) == 0 else <View/>}
                {[
                    <View key={str(i)} style={{"alignItems": "flex-end" if m.role == "user" else "flex-start", "gap": S.xs}}>
                        <View style={[bubble, {"backgroundColor": C.accent if m.role == "user" else C.sunken}]}>
                            <Text style={{"color": C.onAccent if m.role == "user" else C.text, "fontSize": F.md}}>{m.text}</Text>
                        </View>
                        {[<Text key={a} style={{"color": C.success, "fontSize": F.sm}}>✓ {a}</Text> for a in m.actions]}
                    </View>
                    for (i, m) in enumerate(messages)
                ]}
                {(<View style={[bubble, {"backgroundColor": C.sunken}]}><Text style={styles.hint}>Thinking…</Text></View>) if busy else <View/>}
            </ScrollView>

            {(<Text style={styles.error}>{error}</Text>) if error else <View/>}
            <View style={[styles.row, {"paddingBottom": S.md}]}>
                <TextInput testID="chat-input" style={[styles.input, {"flex": 1}]} value={draft} placeholder="Ask Morrow…"
                    placeholderTextColor={C.subtle} editable={not busy}
                    onChangeText={lambda (t: str) { draft = t; }} onSubmitEditing={lambda { send_text(draft); }}/>
                <Pressable testID="chat-send" onPress={lambda { send_text(draft); }} disabled={busy or not draft.strip()}
                    accessibilityLabel="Send"
                    style={{"padding": S.sm + S.xxs, "borderRadius": R.control, "backgroundColor": C.accent,
                            "opacity": 0.5 if busy or not draft.strip() else 1.0}}>
                    <Icon name="send" size={F.lg} color={C.onAccent}/>
                </Pressable>
            </View>
        </View>
    </View>
}

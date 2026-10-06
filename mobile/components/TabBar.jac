"""Bottom tab bar: Plan, Tasks, Ask Morrow (his face), Settings."""

import from "@jac/mobui" { View, Text, Pressable }
import from ..theme { C, S, F, Z }
import from .Icon { Icon }
import from .MorrowFace { MorrowFace }

obj Tab {
    has id: str, label: str, icon: str;
}

glob TABS: list[Tab] = [
    Tab(id="plan", label="Plan", icon="calendar"),
    Tab(id="tasks", label="Tasks", icon="tasks"),
    Tab(id="ask", label="Ask Morrow", icon=""),
    Tab(id="settings", label="Settings", icon="settings")
];

def:pub TabBar(tab: str, onTab: Callable[[str], None], pointer: list[float]) -> JsxElement {
    <View style={{"position": "absolute", "left": 0, "right": 0, "bottom": 0, "minHeight": Z.tabBar,
                  "flexDirection": "row", "backgroundColor": C.surface, "borderTopWidth": 1, "borderTopColor": C.border,
                  "paddingBottom": S.sm}}>
        {[
            <Pressable key={t.id} testID={"tab-" + t.id} onPress={lambda { onTab(t.id); }}
                accessibilityRole="tab" accessibilityState={{"selected": tab == t.id}}
                style={{"flex": 1, "alignItems": "center", "justifyContent": "center", "gap": S.xxs, "paddingTop": S.sm}}>
                {(<MorrowFace pointer={pointer} small={True}/>) if t.id == "ask" else
                    <Icon name={t.icon} size={F.xl} color={C.accent if tab == t.id else C.muted}/>}
                <Text style={{"fontSize": F.xxs, "fontWeight": "600", "color": C.accent if tab == t.id else C.muted}}>{t.label}</Text>
            </Pressable>
            for t in TABS
        ]}
    </View>
}

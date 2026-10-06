"""Small reusable pieces for the phone app, matching the web kit
(web/components/kit.jac): Button, Card, Chip, CheckCircle, Segmented,
PageHeader, Field and Sheet (a bottom-sheet dialog).

All values come from ../theme.jac, so a look is defined once.
"""

import from "@jac/mobui" { View, Text, TextInput, Pressable, ScrollView, Modal }
import from ..theme { C, S, R, F, Z, styles }
import from .Icon { Icon }

def _noop {}

"""variant: "primary" (filled terracotta) | "outline" | "ghost" | "danger"."""
def:pub Button(
    label: str,
    onPress: Callable[[], None] = _noop,
    variant: str = "outline",
    icon: str = "",
    small: bool = False,
    disabled: bool = False,
    testID: str = ""
) -> JsxElement {
    filled = variant == "primary";
    fg = C.onAccent if filled else (C.danger if variant == "danger" else (C.muted if variant == "ghost" else C.text));
    box = {
        "flexDirection": "row", "alignItems": "center", "justifyContent": "center", "gap": S.xs,
        "paddingVertical": S.xs if small else S.sm + S.xxs, "paddingHorizontal": S.md if small else S.lg,
        "borderRadius": R.control, "borderWidth": 1,
        "borderColor": C.accent if filled else (C.borderStrong if variant in ["outline", "danger"] else "transparent"),
        "backgroundColor": C.accent if filled else (C.surface if variant != "ghost" else "transparent"),
        "opacity": 0.5 if disabled else 1.0
    };
    <Pressable testID={testID or None} style={box} onPress={onPress} disabled={disabled} accessibilityRole="button">
        {(<Icon name={icon} size={F.sm if small else F.md} color={fg}/>) if icon else <View/>}
        <Text style={{"color": fg, "fontSize": F.sm if small else F.md, "fontWeight": "600"}}>{label}</Text>
    </Pressable>
}

def:pub Card(children: any = None, style: any = None) -> JsxElement {
    <View style={[styles.card, style or {}]}>{children}</View>
}

"""A small rounded label. tone: "neutral" | "accent" | "danger"."""
def:pub Chip(label: str, tone: str = "neutral") -> JsxElement {
    bg = C.accentTint if tone == "accent" else (C.dangerTint if tone == "danger" else C.sunken);
    fg = C.accentInk if tone == "accent" else (C.danger if tone == "danger" else C.muted);
    <View style={{"backgroundColor": bg, "borderRadius": R.pill, "paddingVertical": S.xxs, "paddingHorizontal": S.sm}}>
        <Text style={{"color": fg, "fontSize": F.xs, "fontWeight": "500"}}>{label}</Text>
    </View>
}

"""Round "done" checkbox; `label` says what tapping does (screen readers)."""
def:pub CheckCircle(checked: bool, label: str, onToggle: Callable[[], None], testID: str = "", size: int = 0) -> JsxElement {
    d = size or Z.check;
    box = {
        "width": d, "height": d, "borderRadius": R.pill, "borderWidth": 1.5,
        "alignItems": "center", "justifyContent": "center",
        "borderColor": C.accent if checked else C.subtle,
        "backgroundColor": C.accent if checked else C.surface
    };
    <Pressable testID={testID or None} style={box} onPress={onToggle} hitSlop={S.sm}
        accessibilityRole="checkbox" accessibilityLabel={label} accessibilityState={{"checked": checked}}>
        {(<Icon name="check" size={d - S.sm} color={C.onAccent}/>) if checked else <View/>}
    </Pressable>
}

"""One option of a Segmented switch."""
obj:pub Choice {
    has value: str, label: str;
}

def:pub Segmented(options: list[Choice], value: str, onChange: Callable[[str], None]) -> JsxElement {
    <View style={{"flexDirection": "row", "padding": S.xxs, "gap": S.xxs, "borderRadius": R.control,
                  "backgroundColor": C.sunken, "borderWidth": 1, "borderColor": C.border}}>
        {[<Pressable key={o.value} testID={"seg-" + o.value} onPress={lambda { onChange(o.value); }}
              style={{"paddingVertical": S.xs, "paddingHorizontal": S.md, "borderRadius": R.block,
                      "backgroundColor": C.surface if o.value == value else "transparent"}}>
            <Text style={{"fontSize": F.sm, "color": C.text if o.value == value else C.muted,
                          "fontWeight": "600" if o.value == value else "400"}}>{o.label}</Text>
          </Pressable>
          for o in options]}
    </View>
}

"""Eyebrow, big title and a muted line, like the web page headers."""
def:pub PageHeader(eyebrow: str, title: str, subtitle: str = "", children: any = None) -> JsxElement {
    <View style={{"gap": S.xs, "marginBottom": S.sm}}>
        <View style={styles.row}>
            <Text style={[styles.eyebrow, {"flex": 1}]}>{eyebrow.upper()}</Text>
            {children}
        </View>
        <Text style={styles.h1}>{title}</Text>
        {(<Text style={styles.subtitle}>{subtitle}</Text>) if subtitle else <View/>}
    </View>
}

"""A labelled text input."""
def:pub Field(
    label: str,
    value: str,
    onChange: Callable[[str], None],
    placeholder: str = "",
    testID: str = "",
    numeric: bool = False,
    grow: bool = False
) -> JsxElement {
    # Only set flex when growing: `flex: 0` would collapse the field's height.
    <View style={[{"gap": S.xs, "minWidth": 96}, {"flex": 1} if grow else {}]}>
        <Text style={styles.label}>{label}</Text>
        <TextInput testID={testID or None} style={styles.input} value={value} placeholder={placeholder}
            placeholderTextColor={C.subtle} autoCapitalize="none"
            keyboardType={"number-pad" if numeric else "default"}
            onChangeText={onChange}/>
    </View>
}

"""A bottom sheet: dims the screen and slides a card up. Tap outside or ✕ to close."""
def:pub Sheet(title: str, onClose: Callable[[], None], children: any = None, subtitle: str = "") -> JsxElement {
    <Modal visible={True} transparent={True} animationType="slide" onRequestClose={onClose}>
        <View style={{"flex": 1, "justifyContent": "flex-end", "backgroundColor": C.overlay}}>
            <Pressable style={{"flex": 1}} onPress={onClose} accessibilityLabel="Close"/>
            <View style={{"maxHeight": "88%", "backgroundColor": C.surface, "borderTopLeftRadius": R.card,
                          "borderTopRightRadius": R.card, "paddingTop": S.lg}}>
                <View style={[styles.row, {"paddingHorizontal": S.lg}]}>
                    <Text style={[styles.cardTitle, {"flex": 1, "fontSize": F.lg}]}>{title}</Text>
                    <Pressable testID="sheet-close" onPress={onClose} hitSlop={S.sm} accessibilityLabel="Close">
                        <Icon name="x" size={F.xl} color={C.muted}/>
                    </Pressable>
                </View>
                {(<Text style={[styles.hint, {"paddingHorizontal": S.lg, "marginTop": S.xs}]}>{subtitle}</Text>) if subtitle else <View/>}
                <ScrollView contentContainerStyle={{"padding": S.lg, "gap": S.md, "paddingBottom": S.xxl}}
                    keyboardShouldPersistTaps="handled">
                    {children}
                </ScrollView>
            </View>
        </View>
    </Modal>
}

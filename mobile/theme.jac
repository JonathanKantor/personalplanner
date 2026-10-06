"""Design tokens and the StyleSheet for the mobile app - the same "morrow"
look as the web app (web/styles/tokens.css): warm cream page, white cards,
terracotta accent, and the calendar's class / deadline / focus / event colours.

Tokens are `obj` types instantiated once into typed globals, so `C.accent`
is an attribute read the compiler checks. `styles` is a React Native
StyleSheet; the same objects work on the web preview and on a phone.
"""

import from "@jac/mobui" { StyleSheet }

obj Palette {
    has bg: str = "#FBF6EF",              # warm cream page
        surface: str = "#FFFFFF",         # cards
        sunken: str = "#F8F2EA",          # inset areas
        border: str = "#EFE6DA",
        borderStrong: str = "#E3D7C8",
        overlay: str = "rgba(31, 26, 23, 0.32)",
        text: str = "#1F1A17",
        muted: str = "#7A6E64",
        subtle: str = "#A6998C",
        accent: str = "#C8573E",          # terracotta
        accentTint: str = "#FBE5DB",      # peach
        accentInk: str = "#9C3F2A",
        onAccent: str = "#FFFFFF",
        ink: str = "#1F1A17",             # Morrow's face
        danger: str = "#B4412E",
        dangerTint: str = "#FBE4DE",
        success: str = "#3E7C4F",
        successTint: str = "#E2F0E5";
}

"""One calendar colour set: tinted background, left border, text."""
obj KindColors {
    has bg: str, border: str, text: str;
}

obj Spacing {
    has xxs: int = 2,
        xs: int = 4,
        sm: int = 8,
        md: int = 12,
        lg: int = 16,
        xl: int = 24,
        xxl: int = 32;
}

obj Radius {
    has block: int = 8,                   # calendar rows
        control: int = 10,                # buttons, inputs
        card: int = 16,
        pill: int = 999;
}

obj FontSize {
    has xxs: int = 10,
        xs: int = 11,
        sm: int = 13,
        md: int = 15,
        lg: int = 17,
        xl: int = 22,
        xxl: int = 28;
}

obj Sizes {
    has tabBar: int = 64,                 # bottom tab bar height
        check: int = 20,                  # round done-checkbox
        face: int = 44,                   # Morrow avatar
        faceSmall: int = 28,
        timeCol: int = 64,                # time column in day rows
        contentMax: int = 560;
}

glob:pub C: Palette = Palette(),
     S: Spacing = Spacing(),
     R: Radius = Radius(),
     F: FontSize = FontSize(),
     Z: Sizes = Sizes(),
     CLASS: KindColors = KindColors(bg="#E4ECF8", border="#7C9BD1", text="#2E4877"),
     DEADLINE: KindColors = KindColors(bg="#F8D9CE", border="#D4745A", text="#8A3B27"),
     FOCUS: KindColors = KindColors(bg="#F9EBC8", border="#D9A93A", text="#765714"),
     EVENT: KindColors = KindColors(bg="#F1ECE5", border="#BCAE9F", text="#4E453E");

"""Colours for a calendar style name (see components/EventRow.jac)."""
def:pub kind_colors(style: str) -> KindColors {
    if style == "class" { return CLASS; }
    if style == "event" { return EVENT; }
    if style == "focus" { return FOCUS; }
    return DEADLINE;
}

glob:pub styles = StyleSheet.create(
         {
             screen: {flex: 1, backgroundColor: C.bg},
             content: {
                 width: "100%", maxWidth: Z.contentMax, alignSelf: "center",
                 paddingHorizontal: S.lg, paddingTop: S.xl, paddingBottom: Z.tabBar + S.xl, gap: S.md
             },
             row: {flexDirection: "row", alignItems: "center", gap: S.sm},
             wrap: {flexDirection: "row", flexWrap: "wrap", alignItems: "center", gap: S.sm},
             spacer: {flex: 1},
             eyebrow: {color: C.accent, fontSize: F.xs, fontWeight: "600", letterSpacing: 1},
             h1: {color: C.text, fontSize: F.xxl, fontWeight: "600", letterSpacing: -0.5},
             subtitle: {color: C.muted, fontSize: F.sm},
             card: {
                 backgroundColor: C.surface, borderWidth: 1, borderColor: C.border,
                 borderRadius: R.card, padding: S.lg, gap: S.md
             },
             cardTitle: {color: C.text, fontSize: F.md, fontWeight: "600"},
             section: {color: C.subtle, fontSize: F.xs, fontWeight: "600", letterSpacing: 1, marginTop: S.sm},
             label: {color: C.muted, fontSize: F.sm},
             input: {
                 color: C.text, fontSize: F.md, backgroundColor: C.surface,
                 borderWidth: 1, borderColor: C.borderStrong, borderRadius: R.control,
                 paddingVertical: S.sm, paddingHorizontal: S.md
             },
             hint: {color: C.muted, fontSize: F.sm},
             error: {
                 color: C.danger, fontSize: F.sm, backgroundColor: C.dangerTint,
                 borderRadius: R.control, paddingVertical: S.sm, paddingHorizontal: S.md
             },
             notice: {
                 color: C.text, fontSize: F.sm, backgroundColor: C.sunken,
                 borderRadius: R.control, paddingVertical: S.sm, paddingHorizontal: S.md
             },
             empty: {color: C.muted, fontSize: F.sm, textAlign: "center", paddingVertical: S.lg},
             divider: {height: 1, backgroundColor: C.border}
         }
     );

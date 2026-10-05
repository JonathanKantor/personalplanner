"""Design tokens and the StyleSheet for the mobile app.

Tokens are `obj` types instantiated once into typed globals, so `C.accent`
is an attribute read the compiler checks. Colors match the web app.
`styles` is a React Native StyleSheet; the same objects work on the web
preview (react-native-web) and on a phone.
"""

import from "@jac/mobui" { StyleSheet }

obj Palette {
    has bg: str = "#f6f7f9",
        surface: str = "#ffffff",
        border: str = "#e3e6eb",
        text: str = "#1d2330",
        muted: str = "#667085",
        accent: str = "#3b5bdb",
        onAccent: str = "#ffffff",
        danger: str = "#c92a2a",
        classBg: str = "#dbe4ff",
        classFg: str = "#26387a",
        eventBg: str = "#eceef2",
        eventFg: str = "#3d4452",
        planBg: str = "#d3f2df",
        planFg: str = "#17613a",
        suggestBg: str = "#fff4d6",
        suggestFg: str = "#7a5600";
}

obj Spacing {
    has xs: int = 4,
        sm: int = 8,
        md: int = 12,
        lg: int = 16,
        xl: int = 24;
}

obj Radius {
    has sm: int = 8,
        md: int = 12,
        lg: int = 16,
        pill: int = 999;
}

obj FontSize {
    has xs: int = 12,
        sm: int = 14,
        md: int = 16,
        lg: int = 20,
        xl: int = 26;
}

glob:pub C: Palette = Palette(),
     S: Spacing = Spacing(),
     R: Radius = Radius(),
     F: FontSize = FontSize();

glob:pub styles = StyleSheet.create(
         {
             screen: {flex: 1, backgroundColor: C.bg},
             content: {width: "100%", maxWidth: 560, alignSelf: "center", padding: S.lg, gap: S.md},
             header: {gap: S.xs, paddingTop: S.lg},
             row: {flexDirection: "row", alignItems: "center", gap: S.sm},
             title: {color: C.text, fontSize: F.xl, fontWeight: "bold"},
             subtitle: {color: C.muted, fontSize: F.sm},
             section: {color: C.muted, fontSize: F.xs, fontWeight: "bold", marginTop: S.md, letterSpacing: 1},
             card: {
                 flexDirection: "row", alignItems: "center", gap: S.md,
                 borderRadius: R.md, paddingVertical: S.md, paddingHorizontal: S.lg
             },
             cardTime: {fontSize: F.sm, fontWeight: "600", width: 74},
             cardTitle: {flex: 1, fontSize: F.md},
             cardSub: {fontSize: F.xs},
             input: {
                 flex: 1, color: C.text, fontSize: F.md, backgroundColor: C.surface,
                 borderWidth: 1, borderColor: C.border, borderRadius: R.md,
                 paddingVertical: S.md, paddingHorizontal: S.lg
             },
             chip: {
                 paddingVertical: S.xs, paddingHorizontal: S.md, borderRadius: R.pill,
                 borderWidth: 1, borderColor: C.border, backgroundColor: C.surface
             },
             chipOn: {backgroundColor: C.accent, borderColor: C.accent},
             chipText: {color: C.text, fontSize: F.sm},
             chipTextOn: {color: C.onAccent, fontSize: F.sm},
             panel: {
                 backgroundColor: C.surface, borderWidth: 1, borderColor: C.border,
                 borderRadius: R.lg, padding: S.lg, gap: S.md
             },
             error: {color: C.danger, fontSize: F.sm},
             notice: {color: C.planFg, fontSize: F.sm},
             empty: {color: C.muted, fontSize: F.sm, textAlign: "center", paddingVertical: S.lg}
         }
     );

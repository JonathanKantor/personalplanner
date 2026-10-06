"""Icons for mobile - NATIVE variant (Lucide via `lucide-react-native`).

The compiler picks this file over `Icon.jac` for the react-native target.
`lucide-react-native` renders through `react-native-svg`, which Metro bundles
on native. Same `Icon` API; keep the `LUCIDE` keys identical in the two files.
"""

import from "lucide-react-native" {
    Check, Plus, Sparkles, ChevronLeft, ChevronRight, X, Circle, LogOut, CalendarDays,
    ListChecks, MessageCircle, Settings, Trash2, Clock, GraduationCap, BookOpen, Send
}

glob LUCIDE = {
    "check": Check, "plus": Plus, "sparkles": Sparkles, "left": ChevronLeft,
    "right": ChevronRight, "x": X, "circle": Circle, "logout": LogOut,
    "calendar": CalendarDays, "tasks": ListChecks, "chat": MessageCircle,
    "settings": Settings, "trash": Trash2, "clock": Clock, "cap": GraduationCap,
    "book": BookOpen, "send": Send
};

def:pub Icon(name: str, size: int, color: str) -> JsxElement {
    Glyph = LUCIDE[name];
    <Glyph size={size} color={color}/>
}

"""Small reusable UI pieces: Icon, Button, IconButton, Card, Chip, Avatar, Dialog.

Styling lives in web/styles/components.css (all values from tokens.css);
these components only pick class names, so a look is defined once.
"""

import from "react" { useEffect }
import from "lucide-react" {
    Sparkles, CalendarDays, ListChecks, MessageCircle, MoreHorizontal, Sun,
    ChevronDown, ChevronLeft, ChevronRight, Plus, Check, X, LayoutGrid, List,
    Clock, GraduationCap, Settings, LogOut, BookOpen, Trash2
}

"""Icon names used in the app -> Lucide components."""
glob ICONS: dict = {
    "sparkles": Sparkles, "calendar": CalendarDays, "tasks": ListChecks,
    "chat": MessageCircle, "more": MoreHorizontal, "sun": Sun,
    "chevron-down": ChevronDown, "chevron-left": ChevronLeft, "chevron-right": ChevronRight,
    "plus": Plus, "check": Check, "x": X, "grid": LayoutGrid, "list": List,
    "clock": Clock, "cap": GraduationCap, "settings": Settings, "logout": LogOut,
    "book": BookOpen, "trash": Trash2
};

"""A decorative icon (hidden from screen readers; label the button instead)."""
def:pub Icon(name: str, size: int = 16) -> JsxElement {
    Glyph = ICONS[name];
    <Glyph size={size} strokeWidth={1.75} aria-hidden="true" />
}

"""Default click handler for buttons that don't need one (e.g. type=submit)."""
def _noop(e: MouseEvent) {}

"""variant: "primary" (filled terracotta) | "outline" | "ghost" | "danger"."""
def:pub Button(
    label: str,
    onClick: Callable[[MouseEvent], None] = _noop,
    variant: str = "outline",
    icon: str = "",
    small: bool = False,
    disabled: bool = False,
    submit: bool = False,                            # True: submits its form
    id: str = ""
) -> JsxElement {
    dom_id: any = id if id else None;                  # no empty id="" attribute
    # (Not a `type` parameter: that name collides with Python's built-in type()
    # in the compiled code, and React would receive a function.)
    <button id={dom_id} type={"submit" if submit else "button"} disabled={disabled} onClick={onClick}
        className={"ui-btn " + variant + (" small" if small else "")}>
        {(<Icon name={icon} size={14 if small else 16} />) if icon else None}
        <span>{label}</span>
    </button>
}

"""An icon-only button. `label` is required: it's what screen readers announce."""
def:pub IconButton(
    icon: str,
    label: str,
    onClick: Callable[[MouseEvent], None] = _noop,
    active: bool = False,
    size: int = 18,
    className: str = ""
) -> JsxElement {
    current: any = "page" if active else None;
    <button type="button" aria-label={label} title={label} onClick={onClick}
        aria-current={current}
        className={"ui-iconbtn" + (" active" if active else "") + (" " + className if className else "")}>
        <Icon name={icon} size={size} />
    </button>
}

"""A navigation entry (rail icons, top-bar pills, menus)."""
obj NavItem {
    has to: str, icon: str, label: str;
}

def:pub Card(children: any = None, className: str = "") -> JsxElement {
    <section className={"ui-card" + (" " + className if className else "")}>{children}</section>
}

"""A small rounded label. tone: "neutral" | "accent"."""
def:pub Chip(label: str, tone: str = "neutral") -> JsxElement {
    <span className={"ui-chip " + tone}>{label}</span>
}

"""Round "done" checkbox (a button: label says what clicking does)."""
def:pub CheckCircle(checked: bool, label: str, onToggle: Callable[[], None]) -> JsxElement {
    <button type="button" className={"check-circle" + (" on" if checked else "")}
        aria-label={label} aria-pressed={checked}
        onClick={lambda (e: MouseEvent) { e.stopPropagation(); onToggle(); }}>
        {checked and <Icon name="check" size={10} />}
    </button>
}

"""A segmented switch (Week | Agenda, Open | All). Each option is a
(value, label, icon) Choice; the current one is pressed."""
obj:pub Choice {
    has value: str, label: str, icon: str = "";
}

def:pub Segmented(options: list[Choice], value: str, onChange: Callable[[str], None], label: str) -> JsxElement {
    <div className="segmented" role="group" aria-label={label}>
        {for o in options {
            <button type="button" key={o.value} aria-pressed={o.value == value}
                className={"seg" + (" on" if o.value == value else "")}
                onClick={lambda (e: MouseEvent) { onChange(o.value); }}>
                {(<Icon name={o.icon} size={14} />) if o.icon else None} {o.label}
            </button>
        }}
    </div>
}

"""Initials from a name: "Maya Chen" -> "MC", "maya" -> "MA"."""
def:pub initials_of(name: str) -> str {
    parts = [p for p in name.strip().split(" ") if p];
    if len(parts) >= 2 {
        return (parts[0][0] + parts[1][0]).upper();
    }
    return (name.strip()[0:2] or "?").upper();
}

def:pub Avatar(name: str, size: str = "md") -> JsxElement {
    <span className={"ui-avatar " + size} aria-hidden="true">{initials_of(name)}</span>
}

"""A modal dialog: dimmed backdrop, a card with a title and a close (✕)
button. Clicking the backdrop or pressing Esc calls `onClose`; clicks inside
the card don't."""
def:pub Dialog(title: str, onClose: Callable[[], None], children: any = None, subtitle: str = "") -> JsxElement {
    useEffect(lambda {
        def on_key(e: any) {
            if e.key == "Escape" { onClose(); }
        }
        window.addEventListener("keydown", on_key);
        return lambda { window.removeEventListener("keydown", on_key); };
    }, [onClose]);

    def stop(e: MouseEvent) {
        e.stopPropagation();
    }

    <div className="modal-backdrop" onClick={lambda (e: MouseEvent) { onClose(); }}>
        <section className="modal ui-card" role="dialog" aria-modal="true" aria-label={title} onClick={stop}>
            <header className="dialog-head">
                <h2 className="dialog-title">{title}</h2>
                <IconButton icon="x" label="Close" onClick={lambda (e: MouseEvent) { onClose(); }} />
            </header>
            {(<p className="dialog-subtitle">{subtitle}</p>) if subtitle else None}
            {children}
        </section>
    </div>
}

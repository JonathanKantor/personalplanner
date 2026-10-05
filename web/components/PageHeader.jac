"""Page header: small uppercase eyebrow, large title, muted subtitle, and
actions (buttons) on the right."""

def:pub PageHeader(title: str, eyebrow: str = "", subtitle: str = "", children: any = None) -> JsxElement {
    <div className="page-header">
        <div>
            {(<div className="eyebrow">{eyebrow}</div>) if eyebrow else None}
            <h1 className="page-h1">{title}</h1>
            {(<p className="page-subtitle">{subtitle}</p>) if subtitle else None}
        </div>
        <div className="page-actions">{children}</div>
    </div>
}

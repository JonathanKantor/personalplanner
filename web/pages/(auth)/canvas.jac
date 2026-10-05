"""/canvas - moved: Canvas import is now a section of Settings."""

import from "@jac/runtime" { Navigate }

def:pub CanvasPage() -> JsxPage {
    return <Navigate to="/settings#canvas" replace={True} />;
}

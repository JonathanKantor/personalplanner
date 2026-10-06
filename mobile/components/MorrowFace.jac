"""Morrow's avatar: a near-black circle with two white eyes that look toward
your last touch (or the mouse, in the web preview).

`pointer` is the last [x, y] on screen, tracked once by the app shell
(mobile/main.jac). When it changes we measure where this face is on screen
(measureInWindow) and shift both eyes up to EYE_REACH px toward the point -
less when it's close.
"""

import from "react" { useEffect, useRef }
import from "@jac/mobui" { View }
import from ..theme { C, R, Z }

glob EYE_REACH: float = 3.0,
     NEAR_PX: float = 120.0;

def:pub MorrowFace(pointer: list[float], small: bool = False) -> JsxElement {
    has look_x: float = 0.0,
        look_y: float = 0.0;
    face: any = useRef(None);                # the circle's native view

    def aim(x: float, y: float, w: float, h: float) {
        dx = pointer[0] - (x + w / 2);
        dy = pointer[1] - (y + h / 2);
        dist: float = Math.hypot(dx, dy) or 1;  # jac:ignore[E1001]
        reach = EYE_REACH * min(1.0, dist / NEAR_PX);
        look_x = dx / dist * reach;
        look_y = dy / dist * reach;
    }

    useEffect(lambda {
        el: any = face.current;
        if el and len(pointer) == 2 {
            el.measureInWindow(aim);
        }
    }, [pointer]);

    d = Z.faceSmall if small else Z.face;
    eye = {
        "width": d * 0.15, "height": d * 0.21, "borderRadius": R.pill, "backgroundColor": C.surface,
        "transform": [{"translateX": look_x}, {"translateY": look_y}]
    };
    <View ref={face} accessibilityElementsHidden={True}
        style={{"width": d, "height": d, "borderRadius": R.pill, "backgroundColor": C.ink,
                "flexDirection": "row", "alignItems": "center", "justifyContent": "center", "gap": d * 0.2}}>
        <View style={eye}/>
        <View style={eye}/>
    </View>
}

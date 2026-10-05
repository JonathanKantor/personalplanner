"""Morrow's avatar: a near-black circle with two white eyes that look toward
the mouse pointer.

How it works: one window-wide `pointermove` listener remembers the pointer
position; at most once per screen refresh (requestAnimationFrame) we measure
where the face is and shift both eyes up to EYE_REACH px toward the pointer
(less when the pointer is close). Nothing moves when the user's system asks
for reduced motion. Listeners are added in a useEffect and removed in its
cleanup, so nothing leaks when the face unmounts.
"""

import from "react" { useEffect, useRef }

glob EYE_REACH: float = 3.0,          # max eye shift, px
     NEAR_PX: float = 160.0;          # closer than this, the eyes move less

def:pub MorrowFace(size: str = "md") -> JsxElement {
    has look_x: float = 0.0,
        look_y: float = 0.0;
    face: any = useRef(None);          # the circle's DOM element
    pointer: any = useRef(None);       # latest [x, y] of the mouse
    frame: any = useRef(0);            # pending animation frame (0 = none)

    def aim {
        frame.current = 0;
        el: any = face.current;
        if not el or not pointer.current {
            return;
        }
        r: any = el.getBoundingClientRect();
        dx = pointer.current[0] - (r.left + r.width / 2);
        dy = pointer.current[1] - (r.top + r.height / 2);
        dist: float = Math.hypot(dx, dy) or 1;  # jac:ignore[E1001]
        reach = EYE_REACH * min(1.0, dist / NEAR_PX);
        look_x = dx / dist * reach;
        look_y = dy / dist * reach;
    }

    def on_move(e: any) {
        pointer.current = [e.clientX, e.clientY];
        if not frame.current {
            frame.current = requestAnimationFrame(aim);  # jac:ignore[E1032]
        }
    }

    useEffect(lambda {
        win: any = window;                           # browser global, untyped
        if win.matchMedia("(prefers-reduced-motion: reduce)").matches {
            return;                # no cleanup (React wants undefined, not None/null)
        }
        window.addEventListener("pointermove", on_move);
        return lambda {
            window.removeEventListener("pointermove", on_move);
            cancelAnimationFrame(frame.current);  # jac:ignore[E1032]
        };
    }, []);

    eyes = {"transform": "translate(" + str(look_x) + "px, " + str(look_y) + "px)"};

    <span className={"morrow-face " + size} ref={face} aria-hidden="true">
        <span className="morrow-eye" style={eyes}></span>
        <span className="morrow-eye" style={eyes}></span>
    </span>
}

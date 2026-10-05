"""/assistant - chat with the AI planning assistant (full page).

The conversation itself is the AssistantChat component, shared with the
floating "Ask Morrow" panel, so both behave the same.
"""

import from ...components.PageHeader { PageHeader }
import from ...components.AssistantChat { AssistantChat }

def:pub AssistantPage() -> JsxPage {
    <div className="narrow">
        <PageHeader eyebrow="Ask Morrow" title="Planning assistant"
            subtitle="Plan, move and add things by asking. It lists everything it changes." />
        <AssistantChat />
    </div>
}

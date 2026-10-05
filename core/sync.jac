"""One "sync everything" endpoint over all calendar sources.

Lives in its own module because it needs both core.calendars (iCal URLs) and
core.gcal (Google), and core.gcal already imports core.calendars.
"""

# Server anchor: see the note in core/tasks.jac.
import os;
import from core.models { SyncResult }
import from core.calendars { _calendars, _sync_ics_text, _fetch_ics }
import from core.gcal { _sync_google_calendar }

"""Re-fetch every calendar with a live source (iCal URLs and Google).
Uploaded .ics files can't be re-fetched; import them again to update."""
def:protect sync_calendar -> list[SyncResult] {
    results: list[SyncResult] = [];
    for c in _calendars() {
        if c.source == "ics" and c.external_id.startswith("http") {
            results.append(_sync_ics_text(c, _fetch_ics(c.external_id)));
        } elif c.source == "google" {
            results.append(_sync_google_calendar(c));
        }
    }
    return results;
}

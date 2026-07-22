#!/usr/bin/env python3
"""Session-start gate check for the Project Kanban board.

Runs as a SessionStart hook. It does two jobs:

1. Surfaces every card with an INCOMPLETE GATE so the session starts by
   finishing what's half-done rather than piling on new work:
     - Done but not committed / pushed / tested
     - Done / In Progress / Review with no acceptance-criteria checklist
     - In Progress / Review (Feature or POC) with no plan or test approach
2. Writes a tiny cache of {card_id: {status, title}} to /tmp so
   task-pickup-guard can recognise tracker cards with zero API calls.

Setup:
  * Set TRACKER_DATABASE_ID to your board's database id (from the board URL).
  * Make the Notion integration token available: this reads NOTION_TOKEN if
    set, otherwise the macOS Keychain item `notion-api-key`. Change
    get_token() for your platform / secret store.

Zero-token and fail-open: any error prints nothing fatal and exits 0 so it
can never block a session from starting.
"""

import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error

# Your board's database id (32 hex chars, dashes optional). From the board URL.
DATABASE_ID = os.environ.get("TRACKER_DATABASE_ID", "").replace("-", "").strip()

CARD_CACHE_PATH = "/tmp/tracker-card-cache.json"

# Card types the exit/entry gates apply to (code work). Adjust to your board.
CODE_TYPES = ("Feature", "Fix", "Maintenance", "Infra", "POC")


def get_token():
    """Return the Notion integration token.

    Default order: NOTION_TOKEN env var, then macOS Keychain item
    `notion-api-key`. Swap this for your own secret store if needed.
    """
    env = os.environ.get("NOTION_TOKEN")
    if env:
        return env.strip()
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-s", "notion-api-key", "-w"],
            capture_output=True, text=True,
        )
        return result.stdout.strip()
    except Exception:
        return ""


def query_database(token):
    """Return all pages in the board, following next_cursor past 100 cards."""
    url = f"https://api.notion.com/v1/databases/{DATABASE_ID}/query"
    headers = {
        "Authorization": f"Bearer {token}",
        "Notion-Version": "2022-06-28",
        "Content-Type": "application/json",
    }
    results = []
    cursor = None
    while True:
        body = {"page_size": 100}
        if cursor:
            body["start_cursor"] = cursor
        payload = json.dumps(body).encode()
        req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read())
        except urllib.error.HTTPError as e:
            if e.code == 404:
                print("PROJECT KANBAN: cannot access the database. Check "
                      "TRACKER_DATABASE_ID and that the board is shared with your "
                      "Notion integration.")
                sys.exit(0)
            raise
        results.extend(data.get("results", []))
        cursor = data.get("next_cursor")
        if not data.get("has_more") or not cursor:
            break
    return results


def fetch_blocks(token, page_id):
    """Fetch child blocks of a card (to inspect its acceptance-criteria to-dos)."""
    url = f"https://api.notion.com/v1/blocks/{page_id}/children?page_size=100"
    headers = {"Authorization": f"Bearer {token}", "Notion-Version": "2022-06-28"}
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read()).get("results", [])
    except (urllib.error.HTTPError, urllib.error.URLError):
        return []


def count_acceptance_criteria(blocks):
    """Return (total_todos, unchecked_count) for to-do blocks in a card body."""
    total = 0
    unchecked = 0
    for b in blocks:
        if b.get("type") == "to_do":
            total += 1
            if not b["to_do"].get("checked", False):
                unchecked += 1
    return total, unchecked


def get_prop(page, name, prop_type):
    prop = page.get("properties", {}).get(name, {})
    if prop_type == "select":
        sel = prop.get("select")
        return sel.get("name", "") if sel else ""
    if prop_type == "checkbox":
        return prop.get("checkbox", False)
    if prop_type == "title":
        return "".join(t.get("plain_text", "") for t in prop.get("title", []))
    return None


def check_gates(pages, token):
    warnings = []
    for page in pages:
        title = get_prop(page, "Issue", "title") or get_prop(page, "Name", "title") or "Untitled"
        status = get_prop(page, "Status", "select")
        card_type = get_prop(page, "Type", "select")
        project = get_prop(page, "Project", "select")
        committed = get_prop(page, "Committed", "checkbox")
        pushed = get_prop(page, "Pushed", "checkbox")
        has_plan = get_prop(page, "Has Plan", "checkbox")
        test_approach = get_prop(page, "Test Approach", "checkbox")
        tested = get_prop(page, "Tested", "checkbox")

        prefix = f'  [{project}] "{title}"' if project else f'  "{title}"'

        if status == "Done" and card_type in CODE_TYPES:
            missing = []
            if not committed:
                missing.append("not committed")
            if not pushed:
                missing.append("not pushed")
            if not tested:
                missing.append("not tested")
            time.sleep(0.35)
            ac_total, ac_unchecked = count_acceptance_criteria(fetch_blocks(token, page["id"]))
            if ac_total == 0:
                missing.append("no acceptance criteria")
            elif ac_unchecked > 0:
                missing.append(f"{ac_unchecked}/{ac_total} acceptance criteria unchecked")
            if missing:
                warnings.append(f"{prefix}, Done but {', '.join(missing)}")

        elif status in ("In Progress", "Review"):
            missing = []
            if card_type in ("Feature", "POC"):
                if not has_plan:
                    missing.append("no plan")
                if not test_approach:
                    missing.append("no test approach")
            if card_type in CODE_TYPES:
                time.sleep(0.35)
                ac_total, _ = count_acceptance_criteria(fetch_blocks(token, page["id"]))
                if ac_total == 0:
                    missing.append("no acceptance criteria defined")
            if missing:
                warnings.append(f"{prefix}, {status} but {', '.join(missing)}")

    return warnings


def write_card_cache(pages):
    """Cache {card_id: {status, title}} so task-pickup-guard needs no API call."""
    cache = {}
    for page in pages:
        pid = page.get("id", "")
        if pid:
            cache[pid] = {
                "status": get_prop(page, "Status", "select"),
                "title": get_prop(page, "Issue", "title") or get_prop(page, "Name", "title") or "",
            }
    try:
        with open(CARD_CACHE_PATH, "w") as f:
            json.dump(cache, f)
    except OSError:
        pass


def main():
    if not DATABASE_ID:
        # Not configured yet, say so once, don't block the session.
        print("PROJECT KANBAN: set TRACKER_DATABASE_ID to enable the gate check.")
        sys.exit(0)

    token = get_token()
    if not token:
        print("PROJECT KANBAN: no Notion token (set NOTION_TOKEN or the "
              "`notion-api-key` Keychain item).")
        sys.exit(0)

    pages = query_database(token)
    write_card_cache(pages)
    warnings = check_gates(pages, token)

    if warnings:
        print("PROJECT KANBAN, INCOMPLETE GATES:")
        for w in warnings:
            print(w)
        print()
        print("Address these before starting new work.")
    else:
        print("Project Kanban gates clean.")

    print()
    print("REMINDER: check the board for your project before starting work. "
          "Create a card, then update it as you go.")


if __name__ == "__main__":
    # Fail-open: any error exits 0 so the gate check can never block a
    # session from starting. (sys.exit raises SystemExit, which is not an
    # Exception, so intentional exits pass through untouched.)
    try:
        main()
    except Exception:
        sys.exit(0)

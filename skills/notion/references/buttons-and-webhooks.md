# Notion Buttons and Webhooks

## When to reach for this

Notion buttons with webhook actions are the bridge between "something happens in Notion" and "something happens outside Notion." Recognise this pattern whenever the user wants:

- **On-demand sync**: "I want a button that pulls my calendar/email/CRM data into Notion"
- **Triggering external workflows**: "click a button to kick off a build, deploy, or pipeline"
- **Pushing data out**: "when I click this, send a Slack message / create a GitHub issue / update a spreadsheet"
- **Manual refresh**: "I want to re-run this integration whenever I want, not just on a schedule"
- **Human-in-the-loop automation**: scheduled sync handles the regular cadence, but the user also wants a "sync now" escape hatch

More broadly, any time the user says "I want to click something in Notion and have something happen elsewhere," that's a button webhook. It's Notion's only native mechanism for user-initiated outbound HTTP calls. Everything else (automations, API, integrations) is either event-driven or requires external tooling.

Buttons can also chain multiple actions (insert blocks, edit properties, create pages, AND send a webhook), so the webhook can be one step in a larger on-click sequence. For example: create a task card in a database AND notify an external service that a new task was created.

## How buttons work

### Button blocks and the API

Button blocks are **invisible to the Notion API**. The API returns them as `"type": "unsupported"` with `"block_type": "button"`. You cannot create, read, update, or delete button blocks via the API. All button configuration happens through the Notion UI.

To configure an existing button: hover over the button block until the settings icon appears (to the right of the drag handle), click it. This opens the button editor with "When" (trigger) and "Do" (actions) sections.

Browser automation cannot reliably interact with the button editor: the settings icon is hover-revealed and Notion's React event system doesn't respond to simulated JavaScript mouse events. If button configuration needs to change, the user does it manually.

### Button actions

- **Insert blocks**: adds pre-defined blocks below the button
- **Add page to**: creates a page in a database
- **Edit property**: changes a property on the current page
- **Edit pages in**: bulk-edit pages matching a filter
- **Show confirmation**: displays a confirmation dialog
- **Open page**: navigates to another page or URL
- **Send webhook**: POSTs to an external URL

Multiple actions can be chained on one button.

### Webhook action specifics

The "Send webhook" action sends an HTTP POST when the button is clicked. You configure:

- **URL**: the endpoint (HTTPS required)
- **Custom headers**: key/value pairs sent with the request

There is **no body configuration**. Notion constructs its own JSON body containing page metadata, user info, and workspace context. You cannot control what fields appear in the body.

## URL validation: what Notion blocks

Notion validates webhook URLs at configuration time (when you paste the URL), before any request is sent. Certain domains are blocked entirely:

**Blocked:**
- `script.google.com`: Google Apps Script exec URLs are rejected regardless of what the endpoint returns. This is a domain-level block, likely because GAS URLs are commonly used in phishing.

**Accepted:**
- `cloudfunctions.net` (Google Cloud Functions)
- `api.github.com`
- `httpbin.org`
- Standard webhook services (Pipedream, Make.com, etc.)

If you hit "invalid URL" errors, test with `https://httpbin.org/post` first to confirm the webhook feature itself works. If httpbin is accepted but your URL isn't, it's domain-specific blocking.

## The bridge pattern

### Why you almost always need one

Many APIs require a specific JSON body format. GitHub's repository_dispatch, for example, requires exactly `{"event_type": "string"}` and rejects unexpected fields. Slack's incoming webhooks expect `{"text": "message"}`. Since Notion sends its own body with page metadata that you can't control, these calls fail.

The bridge pattern solves this: a lightweight function sits between Notion and the target API, receives Notion's POST (ignoring the body), and makes a correctly-formatted request to the actual target.

Think of it as: Notion button = "the user wants this to happen now." Bridge function = "translate that intent into the right API call."

### Recommended bridge: Google Cloud Functions

`cloudfunctions.net` URLs pass Notion's validator. The free tier is more than sufficient (2M invocations/month). A bridge function is typically ~15 lines.

Example (triggering a GitHub Actions workflow):

```python
import urllib.request
import json

def sync(request):
    req = urllib.request.Request(
        "https://api.github.com/repos/OWNER/REPO/dispatches",
        data=json.dumps({"event_type": "my-event"}).encode(),
        headers={
            "Authorization": "Bearer TOKEN",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    urllib.request.urlopen(req)
    return "ok"
```

Deploy:
```bash
gcloud functions deploy FUNCTION_NAME \
  --runtime python311 \
  --trigger-http \
  --allow-unauthenticated \
  --entry-point sync \
  --region REGION \
  --project PROJECT_ID \
  --source ./function-dir \
  --no-gen2
```

The `--no-gen2` flag uses Cloud Functions v1, which has simpler IAM. If you see a warning about IAM policy after deploying:
```bash
gcloud functions add-iam-policy-binding FUNCTION_NAME \
  --region=REGION \
  --member=allUsers \
  --role=roles/cloudfunctions.invoker
```

### Why not Google Apps Script?

GAS is the natural choice for Google-ecosystem bridges: the code is simpler and lives in Google Drive. But Notion blocks `script.google.com` URLs at the webhook validator level, even if the GAS Web App returns 200 on GET and POST. Cloud Functions on `cloudfunctions.net` is the workaround: same Google infrastructure, different domain.

## Design considerations

### Architecture: scheduled sync + manual button

The most robust pattern for keeping Notion in sync with external data is both:

1. **Scheduled sync** (GitHub Actions cron, Cloud Scheduler, etc.): handles the regular cadence, runs unattended
2. **Manual sync button** (Notion webhook → bridge → same workflow): gives the user an "update now" option

Both paths trigger the same underlying sync script/workflow. The button uses `repository_dispatch` (or equivalent) to invoke the same workflow the scheduler runs. One sync script, two trigger paths.

### Security: where to put secrets

Put API tokens and credentials **inside the bridge function** (server-side), not in Notion's webhook header configuration. The bridge function's code is visible only in GCP/AWS console. Notion's webhook headers are visible to anyone who can edit the button in the workspace.

### Feedback: "ran successfully" doesn't mean it worked

After clicking a webhook button, Notion shows "Button automation ran successfully" if the HTTP request was sent, regardless of whether the target endpoint actually did anything useful. Always verify the downstream effect independently: check workflow logs, database state, or whatever the webhook was supposed to trigger.

## Common mistakes

- **Calling strict APIs directly from Notion webhooks.** Notion's body payload causes validation errors on APIs that reject unexpected fields. Always use a bridge.
- **Trying GAS URLs and wasting time debugging 302s and auth flows.** The URL is blocked at the validator, full stop. Go straight to Cloud Functions.
- **Attempting button configuration via browser automation.** The hover-revealed settings icon doesn't respond to programmatic events. Users configure buttons manually.
- **Building the bridge before testing URL acceptance.** Always paste the URL into Notion's webhook field first. If it's rejected, no amount of server-side fixes will help.

# Banked reset feasibility

Verified on 2026-09-28 against local authenticated accounts. Both Codex and
Claude expose unused reset information through their existing usage API
surfaces. The app displays a banked-reset row per account, expandable into
remaining grants sorted by expiry. Missing details are distinguished from an
empty bank. Expiry dates include the local date, time, and time zone.

## Codex

The existing authenticated `GET https://chatgpt.com/backend-api/wham/usage`
response includes:

```text
rate_limit_reset_credits
  available_count: integer
  applicable_available_count: integer
```

One local Codex account returned a positive available count with zero
applicable resets. Preserve these as separate concepts: a banked reset is not
necessarily usable now. The response did not supply individual grants or
expiration timestamps. Do not infer expiry from the ordinary quota reset time.

The count requires no additional network request or authentication flow.
Individual grants come from a second authenticated read:

```text
GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits
available_count: integer
credits: array of
  id: string
  reset_type: string
  is_supported_by_plan: boolean
  status: string
  granted_at: ISO8601 string
  expires_at: ISO8601 string
  title: string
  description: string
```

This route was found in the installed Codex app and verified with the same
account credentials as the usage endpoint. Available grants include explicit
expiry with fractional seconds. The UI excludes spent grants and preserves
plan restrictions. A failed or malformed details response preserves the
successful quota snapshot and summary count, with details marked unavailable.
The app does not infer individual usability from plan support alone.

[OpenAI's pricing documentation](https://learn.chatgpt.com/docs/pricing)
describes banked resets, including a dated referral promotion with 30-day
expiry. That promotion's duration is not a substitute for account-specific
expiry data.

## Claude

The ordinary authenticated organization usage response omitted reset grants
on all three connected accounts inspected. Claude's deployed usage-page
JavaScript requests:

```text
GET /api/organizations/{organization_id}/usage?cedar_ember=1&skip_spend=1
```

The response includes a `cedar_ember` object with this observed structure:

```text
eligible: boolean
ineligible_reason: null in inspected accounts
at_limit: boolean
exhausted: array of strings
grants: array of
  id: string
  label: string
  resets_total: integer
  resets_left: integer
  starts_at: ISO8601 string
  ends_at: ISO8601 string
  clears: array of strings
  paused: boolean
  usable_now: boolean
  use_requires_limit: boolean
  percent_used: object keyed by limit name
  blocking: array, empty in inspected accounts
  arm: null in inspected accounts
next_grant_id: string or null
weekly_resets_at: ISO8601 string
cooldown_until: null in inspected accounts
event_props: analytics metadata, unnecessary for display
```

The live samples included both unused and exhausted grants, with explicit
expiry and usability. Observed `clears` values included `five_hour`,
`seven_day`, and `seven_day_overage_included`. Other grant types and non-null
cooldown, ineligibility, and blocking states remain unqualified.

A further read using only `?cedar_ember=1` returned grants alongside the
existing `five_hour`, `seven_day`, `limits`, and `spend` data. The smallest
integration adds this query parameter to `ClaudeWebUsageClient`
without adding a second request. Do not copy `skip_spend=1` into the existing
request: the app also needs the spending data.

Discovery used the deployed usage-page asset `c71860c77-73C74UkB.js` and its
shared data hooks in `shared-0-br0YfG5U.js`. These are private web implementation
details, not a stable documented API contract. The OAuth usage endpoint was
not qualified for this feature.

[Claude's reset documentation](https://support.claude.com/en/articles/17007452-what-is-a-limit-reset)
explains that grants can reset session or weekly limits, may expire, and do
not alter the usage credit balance.

## Display and validation

- Show a separate banked-reset count, with current usability when reported.
  Keep resets distinct from monetary credits and scheduled quota resets.
- Preserve Claude's per-grant expiry and scope so session-only and broader
  resets can be distinguished. Do not assume every grant clears every limit.
- Treat an absent or malformed optional reset object as unknown, not zero;
  preserve otherwise valid quota and credit information.
- Validate nonnegative integral counts and handle provider eligibility,
  paused grants, expiration, and cooldown before calling a reset usable.
- Keep this implementation read-only. Redemption is a separate action
  and was neither exercised nor qualified by this investigation.

Automated tests exercise request authentication, provider decoding, failed
detail requests, malformed optional metadata, expiry ordering, expired and
spent grants, paused and cooldown states, and snapshot persistence. The sample
app includes multiple expiries, exhausted resets, and unavailable details.

Live production-decoder checks confirmed one available grant with expiry for
each provider. Native rendering was inspected at 360- and 411-point widths;
a hosting-view regression test checks expansion through the widget's scrolling
layout and a large-to-small resize. Expansion state is shared by the menu and
widget for the lifetime of the app, so switching layout candidates does not
collapse an open list.

The full implementation test run passed 447 of 448 tests. The failure was
`evictedOpenCodeProfileCanBeRemovedAndRecreatedWithoutCookies`, an existing
WebKit cookie-removal test. A clean isolated checkout of pre-implementation
commit `f55f08b` reproduced the same failure in its full suite; the test passed
in isolation. This feature does not change the profile-removal implementation,
and the full suite is not qualified as green.

Only authenticated GET requests were made during qualification. Credentials, account identifiers,
raw account responses, and live balances are not retained in this document.
No reset was redeemed, and no account settings were changed.

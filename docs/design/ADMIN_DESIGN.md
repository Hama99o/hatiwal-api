# Admin design

The admin's look comes from references, not taste. This file records what was
looked at and what was taken, so every choice is traceable. The one stylesheet
is `app/assets/stylesheets/admin.css`. Views use its classes and never use
inline `style=` attributes.

## Brand

Lapis `#12224F` and gold `#E8B23A`, the app icon and web logo. These are not
reinvented here.

- **Lapis** is the sidebar, primary buttons, the "Total" metric, and the
  new-users chart.
- **Gold** marks the active page in the nav, the Support count badge, the
  new-listings chart, and "held" in charts.
- **Status colours mean one thing everywhere:** lapis = live, gold = reserved
  or held, green = sold, grey = draft, red = broken, amber = needs review.

## References (Mobbin, 2026-10-01)

| Pattern | Looked at | Taken |
|---|---|---|
| Several numbers in one card | [Neon project dashboard](https://mobbin.com/screens/57e883a3-2c9f-42aa-b776-c873201a6cdc), [Pinterest analytics "Overall performance"](https://mobbin.com/screens/22864846-19a6-4f9d-af14-fb6322a75cd9) | `.ad-metrics`: one card, a small uppercase label above a big number, dividers between metrics. It replaces 11 separate same-weight boxes that read as a wall. |
| A chart with its headline number | [Mixpanel main dashboard](https://mobbin.com/screens/b2e7f096-7f25-4cdb-a80e-645ed595f5a1), [Whop stats](https://mobbin.com/screens/0b39694c-dee7-4300-9f2e-ebe25b14c75e), [Ferndesk overview](https://mobbin.com/screens/a41b87bc-6104-4cc3-8cb6-cfd4620701b1) | `.ad-card` with title, headline total and caption, then the chart. The number is read before the shape. |
| Period switch | [Mintlify analytics](https://mobbin.com/screens/205aefea-2dfc-4668-9af7-bc4921da1762), [Obvious usage](https://mobbin.com/screens/f8d79792-2e5d-4eac-aa5d-6050dce3aebb) | A segmented control at the right of the section head (`.ad-segmented`), not loose pills. |
| Problems first | [Cloudflare performance](https://mobbin.com/screens/165cf311-941b-4581-8d5c-2832d577b0ca) (banner above content), [Vapi issues](https://mobbin.com/screens/9afecd03-c74c-41b9-b1f3-a4eee7089c21), [DoorDash Merchant](https://mobbin.com/screens/632bea0a-a4ed-4621-be98-b7a6b677b45f) (status pill) | `.ad-alerts` at the top of the dashboard. Each line appears only when true and links to where it is fixed. The Android push failure was a red card halfway down the page; now it is the second thing seen. |
| Phone | [Shopee analytics](https://mobbin.com/screens/29d03d9e-d3a1-4c4e-8a1a-7fd955a43934) (2-column tiles), [Revolut Business](https://mobbin.com/screens/5c7dc9dc-0dbc-4b23-a895-fb625071742a) (stacked chart cards) | Below 860px the metrics become a 2-column tile grid and chart cards stack. The sidebar becomes a top bar that scrolls sideways on its own; the page itself never scrolls sideways. |

## What was wrong (dashboard, before)

- **Phone:** the page was 690px wider than a 390px screen. Administrate sets
  `.main-content { min-width: 800px }`, and the viewport meta lacked
  `width=device-width`.
- **No hierarchy:** 11 identical boxes, so "1 pending report" weighed the same
  as "66 categories".
- **The worst news sat mid-page:** Android users can't get pushes.
- **Three styles on one page:** an inline `<style>`, inline `style=` attributes,
  and the `_theme` partial, each with its own colours. Indigo `#6366f1` was the
  accent, which is not the brand.
- **Charts:** Chart.js default fonts and translucent fills, and the pie used
  default colours (active listings were red). The categories chart had no title.

## Order of the dashboard

1. **Needs attention:** only what is true now.
2. **Users**, then **Listings & moderation:** the daily numbers.
3. **Growth:** weekly, monthly or yearly, on Kabul time.
4. **Composition.**
5. **App versions** and **push reach:** read before a release, not every
   morning, so they come last. Their failure still surfaces at the top via (1).

## Detail, list and compose pages (second pass)

- **Detail pages** (user, listing, report): Administrate's own header keeps
  the name and its Edit/Destroy buttons. Status badges sit beside the name
  (`:header_middle`). One panel per job goes between the header and the
  fields (`:before_main`). Each panel has a coloured top edge for its tone:
  lapis for messaging and triage, gold for warnings, red for anything that
  bans or takes down. The destructive panel spans the full width and comes
  last, so it is never the first thing tapped. The same pattern as the
  dashboard's metric strips: one card per job, not one per number.
- **Field list:** a label column and a value column, which stack on a phone.
  Values use `unicode-bidi: plaintext`, so Pashto, Dari and Urdu names and
  titles lay out right-to-left inside the English chrome.
- **List tables:** dates, ids and column labels never wrap. The table scrolls
  inside its card with the first column pinned. Administrate's legacy
  `word-break: break-word` let a title column shrink to one letter per line;
  it is overridden.
- **Support thread:** chat bubbles, Support on the right in lapis and the
  user on the left, as in the apps' own chat. The inbox marks unread threads
  with a gold edge and count.
- **Compose (Messages, Bulk email):** channels are selectable rows that
  highlight when ticked and grey out when unavailable (from the `disabled`
  attribute, not a second flag). Bulk email is numbered steps. Sending is a
  red confirm box where you type the count.
- **Sign-in:** a white card on lapis with a soft gold glow, the same
  brand as the app icon.
- **Motion:** content settles in on arrival (0.32s rise, staggered by 30ms);
  buttons press in (scale 0.98); cards lift on hover. Nothing loops. It is
  off on pages that reload themselves (the Support inbox and thread, bulk
  progress), and off for anyone whose OS asks for reduced motion.

### Kept on purpose

- **Inline styles stay where they must:** mailer views (email clients drop
  stylesheets), the public unsubscribe pages (no admin assets for users), and
  bulk email's "(fallback)" badge, whose `display` is state that its script
  toggles.
- **Every id and class that specs or scripts read is unchanged:** `bulk-row`,
  `label.channel`, `#support-thread > div`, `#nav-messages`, `.nav-badge`, and
  the others.

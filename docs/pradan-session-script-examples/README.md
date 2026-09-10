# PRADAN session-script examples

These are unmodified examples of the download scripts that ISRO's PRADAN portal
generates for you after you log in and add products to your cart. They are kept
here purely as reference for the URL scheme and the session mechanics.

The `JSESSIONID` values have been redacted — a session cookie is short-lived and
tied to one login, so these scripts cannot be run as-is. Generate a fresh one for
yourself (see [../../DATA.md](../../DATA.md)), or let
[`../../scripts/download_data.sh`](../../scripts/download_data.sh) build the
requests for you.

Key things these examples document:

- Base URL: `https://pradan.issdc.gov.in`
- Product path: `/ch2/protected/downloadData/POST_OD/isda_archive/ch2_bundle/cho_bundle/nop/<instrument>_collection/data/<raw|calibrated|derived>/<YYYYMMDD>/<product>.zip?<instrument>`
- Auth: a single `Cookie: JSESSIONID=...` header from a browser login
- A background keep-alive request to `/ch2/protected/payload.xhtml` every 10 minutes
  stops the session from timing out mid-download
- Session download limits, request rate limits and session timeouts are enforced
  server-side; exceeding them can get you blocked

# Label printing (Brother QL-810W) — pilot test guide

The KDS prints one **adhesive label per drink** (a 2× Latte line → 2 labels; a
3-product order → 3+ labels). Each label has:

- **Heading** — Suite name (e.g. *Corporate Suite 05*)
- **Product** + its variants (size, milk, sugar, extras) and any note
- **"How was our Service?"** + a **QR code** (FDBK, coded by suite)

> The QR is a **placeholder** for now (`lib/printing/fdbk_config.dart`). When
> FDBK provides the real per-suite payload/URL, change `qrDataForSuite()` — the
> label already renders whatever it returns.

## Hardware / connection

Pilot printer: **Brother QL-810W** (WiFi + USB; *no Bluetooth*). It speaks
Brother's raster language, so we render each label to an image and send it via
the official Brother SDK (the `another_brother` Flutter plugin).

Two ways to connect:

| Mode | How | Printer IP | Note |
|---|---|---|---|
| **Wireless Direct** (pilot/test) | The printer makes its **own WiFi AP**; join the tablet to it in Android WiFi settings | **`192.168.118.1`** (default) | Tablet is then **off the venue LAN**, so live KDS orders won't load — use **Test print** + the preview, which need no network. |
| **Infrastructure** (real use) | Printer joins the venue WiFi | the IP the venue assigns it | Tablet keeps proxy **and** printer on the same LAN — needed for printing real incoming orders. |

Media: **62 mm continuous (DK-22205)** is the default. Different tape →
change `QL700.W62` in `lib/printing/brother_service.dart` and `kPrintWidthDots`
in `lib/printing/label_card.dart`.

## Configure the printer (in the app)

Setup screen (first run, or ⋮ → **Change station / operator**):

1. Section **3 · Label printer** → turn **Print labels** on.
2. **Printer IP** — `192.168.118.1` for Wireless Direct, else the venue IP.
3. **Test print a sample label** — opens the preview on a sample order; tap
   **Print** to fire a real label.

## Test steps

1. Power on the QL-810W; load 62 mm tape; confirm WiFi is on.
2. **Wireless Direct:** press the printer's WiFi button until it advertises its
   AP, then join that network from the tablet's Android WiFi settings.
3. In the app: enable printing, set IP `192.168.118.1`, **Test print** → **Print**.
   - A label should print matching the on-screen preview.
4. For a real order (infrastructure mode only): open a ticket → **🖨 Print
   labels** (top-right of the detail modal) → **Print N labels**.

## Notes / next

- The **preview always works with no printer** — validate the label layout
  before any hardware is connected.
- Printing is currently **manual** (from the ticket modal / test button).
  Auto-print on order arrival is a planned follow-up (needs off-screen
  rendering); the `services/ticket_printer.dart` hook is the seam for it.
- First Android build pulls the Brother SDK via `another_brother` — do a clean
  `flutter run` if Gradle caches act up.
- `INTERNET` permission was added to the main manifest (required for network
  printing **and** for the proxy to work in release builds).

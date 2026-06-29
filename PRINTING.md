# Label printing (Star TSP654IISK) — pilot test guide

The KDS prints one **adhesive label per drink** (a 2× Latte line → 2 labels; a
3-product order → 3+ labels). Each label has:

- **Heading** — Suite name (e.g. *Corporate Suite 05*)
- **Product** + its variants (size, milk, sugar, extras) and any note
- **"How was our Service?"** + a **QR code** (FDBK, coded by suite)

> The QR is a **placeholder** for now (`lib/printing/fdbk_config.dart`). When
> FDBK provides the real per-suite payload/URL, change `qrDataForSuite()` — the
> label already renders whatever it returns.

## Hardware / connection

Pilot printer: **Star TSP654IISK** — an 80 mm thermal printer using **linerless
sticky (adhesive) paper**, **network (Ethernet)** connected. We render each
label to an image and stream it as an **ESC/POS raster job over raw TCP 9100**
(pure Dart — no native printer plugin), and the printer cuts after each label.

> ⚠️ **The printer must be in ESC/POS emulation mode.** Star printers ship in
> *Star Line Mode* by default, which won't render ESC/POS bytes. Switch it once
> using Star's **Star Quick Setup / Configuration utility** (or the printer's
> WebPRNT config page / memory-switch) to **ESC/POS** emulation. The maintained
> Flutter Star-native plugin is currently broken on modern Flutter, so ESC/POS
> over 9100 is the reliable path.

- Connect the printer by **Ethernet to the same LAN** as the tablet (tablet on
  WiFi, printer wired, **same subnet**).
- It needs an **IP address** — set a static IP, or read the one it got from a
  printer **self-test** print.
- Paper width: **80 mm** = **576 printable dots** (`kPrintWidthDots` in
  `lib/printing/label_card.dart`; `printWidthDots` in
  `lib/printing/star_service.dart`).

## Configure the printer (in the app)

Setup screen (first run, or ⋮ → **Change station / operator**):

1. Section **3 · Label printer** → turn **Print labels** on.
2. Enter the printer's **IP address**.
3. **Test print** — opens the preview on a sample order; tap **Print** to fire a
   real label.

## Test steps

1. Power on the TSP654IISK, load the 80 mm sticky roll, connect Ethernet.
2. Set the printer to **ESC/POS emulation** (Star setup utility) — one time.
3. Confirm the tablet and printer are on the **same subnet** (e.g. both
   `192.168.1.x`); note the printer's IP from a self-test print.
4. In the app: enable printing → enter IP → **Test print** → **Print**. A label
   should print matching the on-screen preview.
5. For a real order: open a ticket → **🖨 Print labels** (top-right of the detail
   modal) → **Print N labels**.

## Notes / next

- The **preview always works with no printer** — validate the label layout
  before any hardware is connected.
- Printing is currently **manual** (from the ticket modal / test button).
  Auto-print on order arrival is a planned follow-up (needs off-screen
  rendering); the `services/ticket_printer.dart` hook is the seam for it.
- Permissions: `INTERNET` (network printing + proxy in release builds) and
  `ACCESS_NETWORK_STATE` are declared in the main manifest. The print path is
  pure Dart (a raw socket + `esc_pos_utils_plus`), so there's no native printer
  plugin to fail the build.
- Only `StarService` (`lib/printing/star_service.dart`) is printer-specific — if
  the printer/transport changes again, that's the one file to swap.

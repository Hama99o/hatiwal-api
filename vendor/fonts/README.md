# Fonts for server-rendered images (IDEA-8 share / QR cards)

Only what `ShareCard` draws with Pango (ruby-vips `Vips::Image.text(fontfile:)`): the production image
installs no fonts, so the files travel with the app (owner/supervisor 2026-10-30: two files, not a font package).

| File | Family | Source | Licence |
|---|---|---|---|
| `NotoSansArabic-Bold.ttf` | Noto Sans Arabic Bold — Pashto / Dari (ټ ښ ږ ګ ځ) | The Noto Project Authors (github.com/notofonts/arabic), same file as hatiwal-web `src/app/fonts/NotoSansArabic_700Bold.ttf` | SIL OFL 1.1 (`OFL.txt`) |
| `Rubik-Bold.ttf` | Rubik Bold — Latin, the brand's Latin face | The Rubik Project Authors (github.com/googlefonts/rubik), same file as hatiwal-web `src/app/fonts/Rubik_700Bold.ttf` | SIL OFL 1.1 (`OFL.txt`) |

The OFL allows bundling and redistribution with software; the fonts are not sold on their own and keep their names.

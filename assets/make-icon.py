#!/usr/bin/env python3
"""Generates the LensLink logo, app icons, and README banner.

The mark is a camera lens (big ring + aperture dot) with a smaller link
ring layered onto its lower-right edge, in the design system's palette
(docs/UI_DESIGN.md: accent #3D7BFF on dark #0E0F13).

The iOS app icon ships in Apple's three appearance variants (iOS 18+):
default (light), dark, and tinted. Only the default one carries our own
background — for dark and tinted, iOS draws the backdrop itself and
composites the artwork over it, so those two are transparent PNGs. In
tinted mode iOS throws the hue away and maps luminance through the
colour the user picked, so that variant is authored in greys.

Outputs (run from the repo root):
  assets/icon-1024.png          app icon master (opaque — iOS forbids alpha)
  assets/icon-1024-dark.png     dark-appearance master (transparent)
  assets/icon-1024-tinted.png   tinted-appearance master (transparent, greys)
  assets/logo.png        icon on transparent, 512x512
  assets/banner.png      icon + wordmark on transparent (README)
  assets/social-preview.png  1280x640 GitHub social preview (opaque)
  ios-app/Sources/Assets.xcassets/AppIcon.appiconset/icon-1024{,-dark,-tinted}.png
"""

import collections
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFont

S = 4  # supersample factor for clean anti-aliased edges
SIZE = 1024

ACCENT = (0x3D, 0x7B, 0xFF)        # big lens ring
ACCENT_LIGHT = (0x8F, 0xB4, 0xFF)  # link ring
APERTURE_HI = (0x6F, 0xA0, 0xFF)   # aperture dot, highlight side
APERTURE_LO = (0x2E, 0x5F, 0xD6)   # aperture dot, shadow side
BG_TOP = (0x17, 0x1A, 0x22)
BG_BOTTOM = (0x0D, 0x0E, 0x12)

# The four inks of the mark, so it can be re-coloured per icon appearance.
Palette = collections.namedtuple("Palette", "ring link aperture_hi aperture_lo")

BRAND = Palette(ACCENT, ACCENT_LIGHT, APERTURE_HI, APERTURE_LO)


def shade(colour, factor):
    return tuple(min(255, int(round(c * factor))) for c in colour)


def grey(v):
    return (v, v, v)


# Dark appearance: the artwork sits on iOS's own dark backdrop with no
# gradient of ours to sit against, and a dark home screen makes saturated
# blues glare. Same hues, dialled back.
DARK = Palette(*(shade(c, 0.86) for c in BRAND))

# Tinted appearance: greys only — iOS remaps luminance into the user's
# tint, brightest where this image is whitest. The ordering matters more
# than the absolute values: link ring brightest, then the lens ring, with
# the aperture dot keeping enough range to still read as a sphere.
TINTED = Palette(grey(0xCC), grey(0xFF), grey(0xC2), grey(0x73))

# Geometry (1024-space). The small ring straddles the big ring's band so
# the two interlock like chain links.
BIG_C = (468, 448)
BIG_R_OUT, BIG_R_IN = 318, 224
DOT_R = 128
SMALL_C = (718, 698)
SMALL_R_OUT, SMALL_R_IN = 172, 106


def ring_mask(size, center, r_out, r_in):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    cx, cy = center[0] * S, center[1] * S
    d.ellipse([cx - r_out * S, cy - r_out * S, cx + r_out * S, cy + r_out * S], fill=255)
    d.ellipse([cx - r_in * S, cy - r_in * S, cx + r_in * S, cy + r_in * S], fill=0)
    return m


def circle_mask(size, center, r):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    cx, cy = center[0] * S, center[1] * S
    d.ellipse([cx - r * S, cy - r * S, cx + r * S, cy + r * S], fill=255)
    return m



def vertical_gradient(size, top, bottom):
    # Drawn as a 1px column and stretched sideways. (Painting the column
    # into a full-width image and then "resizing" it to its own size — a
    # no-op — leaves every other column black; that is why the icon
    # shipped on a flat black background instead of this gradient.)
    col = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        col.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return col.resize((size, size))


def make_mark(size, palette=BRAND):
    """The lens+link mark with a transparent background, at size*S px."""
    px = size * S
    mark = Image.new("RGBA", (px, px), (0, 0, 0, 0))

    solid = lambda c: Image.new("RGBA", (px, px), c + (255,))

    # Aperture dot: diagonal gradient, light toward the upper-left.
    dot = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    grad = Image.new("RGB", (px, px))
    for y in range(0, px, S):
        t = y / (px - 1)
        row = tuple(int(palette.aperture_hi[i]
                        + (palette.aperture_lo[i] - palette.aperture_hi[i]) * t)
                    for i in range(3))
        for yy in range(y, min(y + S, px)):
            grad.paste(row, (0, yy, px, yy + 1))
    dot.paste(grad, (0, 0), circle_mask(px, BIG_C, DOT_R))
    mark.alpha_composite(dot)

    big = ring_mask(px, BIG_C, BIG_R_OUT, BIG_R_IN)
    small = ring_mask(px, SMALL_C, SMALL_R_OUT, SMALL_R_IN)

    mark.paste(solid(palette.ring), (0, 0), big)

    # The two bands cross at a shallow angle, so their overlap is one
    # connected crescent — a chain-style over/under weave can't render
    # cleanly at these proportions. Instead the link ring sits on top,
    # separated by a keyline gap: the lens ring is erased across the link
    # ring's whole footprint (plus a margin), so the link's interior stays
    # clean instead of showing a sliver of the lens band through the hole.
    keyline = circle_mask(px, SMALL_C, SMALL_R_OUT + 22)
    keyline = ImageChops.multiply(keyline, big)
    mark.paste(Image.new("RGBA", (px, px), (0, 0, 0, 0)), (0, 0), keyline)

    mark.paste(solid(palette.link), (0, 0), small)

    return mark


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    assets = os.path.join(root, "assets")
    appiconset = os.path.join(root, "ios-app", "Sources", "Assets.xcassets",
                              "AppIcon.appiconset")
    os.makedirs(assets, exist_ok=True)
    os.makedirs(appiconset, exist_ok=True)

    mark_big = make_mark(SIZE)

    # --- App icon, default (light) appearance: opaque RGB ---------------
    # The only variant with a background of ours; iOS forbids alpha here.
    icon = vertical_gradient(SIZE * S, BG_TOP, BG_BOTTOM).convert("RGBA")
    icon.alpha_composite(mark_big)
    icon = icon.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")
    icon.save(os.path.join(assets, "icon-1024.png"))
    icon.save(os.path.join(appiconset, "icon-1024.png"))

    # --- App icon, dark + tinted appearances: transparent RGBA ----------
    # iOS draws its own backdrop under these two (a dark gradient, or the
    # user's tint), so shipping our gradient would double it up and box
    # the mark in. Keep them transparent; the keyline gap around the link
    # ring then reveals that backdrop instead of our background, which is
    # the same read.
    for name, palette in (("dark", DARK), ("tinted", TINTED)):
        variant = make_mark(SIZE, palette).resize((SIZE, SIZE), Image.LANCZOS)
        variant.save(os.path.join(assets, "icon-1024-%s.png" % name))
        variant.save(os.path.join(appiconset, "icon-1024-%s.png" % name))

    # --- Standalone logo: transparent, 512 ------------------------------
    logo = mark_big.resize((512, 512), Image.LANCZOS)
    logo.save(os.path.join(assets, "logo.png"))

    # --- README banners: mark + wordmark, transparent -------------------
    # Two variants because the "Lens" half of the wordmark must contrast
    # with GitHub's page background (white text vanishes in light mode);
    # the README picks one via <picture prefers-color-scheme>.
    def banner(lens_fill, path):
        bw, bh = 1400, 420
        img = Image.new("RGBA", (bw * S, bh * S), (0, 0, 0, 0))
        mark_px = 380 * S
        img.alpha_composite(mark_big.resize((mark_px, mark_px), Image.LANCZOS),
                            (10 * S, (bh * S - mark_px) // 2))
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
            190 * S)
        d = ImageDraw.Draw(img)
        x, y = 420 * S, (bh * S) // 2
        d.text((x, y), "Lens", font=font, fill=lens_fill, anchor="lm")
        lens_w = d.textlength("Lens", font=font)
        d.text((x + lens_w, y), "Link", font=font, fill=ACCENT + (255,),
               anchor="lm")
        img.resize((bw, bh), Image.LANCZOS).save(path)

    banner((255, 255, 255, 255), os.path.join(assets, "banner-dark.png"))
    banner((0x16, 0x18, 0x1D, 255), os.path.join(assets, "banner-light.png"))

    # --- GitHub social preview: 1280x640, opaque ------------------------
    # Rendered when the repo is linked on chat/social sites. Same dark
    # gradient as the app icon; mark + wordmark centred as a group, one
    # tagline underneath in textSecondary (white @ 60%).
    def social_preview(path):
        pw, ph = 1280, 640
        img = Image.new("RGB", (pw * S, ph * S))
        grad = vertical_gradient(ph * S, BG_TOP, BG_BOTTOM)
        img.paste(grad.resize((pw * S, ph * S)), (0, 0))
        img = img.convert("RGBA")

        bold = ImageFont.truetype(
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
            150 * S)
        tag_font = ImageFont.truetype(
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            46 * S)
        d = ImageDraw.Draw(img)

        mark_px = 300 * S
        gap = 28 * S
        text_w = d.textlength("LensLink", font=bold)
        group_w = mark_px + gap + text_w
        gx = (pw * S - group_w) // 2
        gy = 268 * S  # group's vertical centre, slightly above middle

        img.alpha_composite(mark_big.resize((mark_px, mark_px), Image.LANCZOS),
                            (int(gx), int(gy - mark_px // 2)))
        tx = gx + mark_px + gap
        d.text((tx, gy), "Lens", font=bold,
               fill=(255, 255, 255, 255), anchor="lm")
        d.text((tx + d.textlength("Lens", font=bold), gy), "Link",
               font=bold, fill=ACCENT + (255,), anchor="lm")

        d.text((pw * S // 2, 500 * S),
               "iPhone & iPad camera for OBS Studio  —  Wi-Fi or USB",
               font=tag_font, fill=(255, 255, 255, 153), anchor="mm")

        img.convert("RGB").resize((pw, ph), Image.LANCZOS).save(path)

    social_preview(os.path.join(assets, "social-preview.png"))

    print("wrote assets/icon-1024{,-dark,-tinted}.png, assets/logo.png,")
    print("assets/banner-*.png, assets/social-preview.png,")
    print("and the same three icons in",
          os.path.relpath(appiconset, root))


if __name__ == "__main__":
    main()

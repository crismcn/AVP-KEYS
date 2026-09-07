#!/usr/bin/env python3
"""Regenerate the Android launcher icons from logo.png.

Run from the repo root:  python3 tools/gen_icons.py

logo.png is the design master: square, artwork bled to the edges, no rounded
corner drawn into it (the launcher mask supplies that). Everything below is
derived from it, so re-run this after every logo change instead of hand-editing
the PNGs.

  mipmap-*/ic_launcher_foreground.png  the whole artwork mapped 1:1 onto the
      108dp adaptive-icon canvas, black turned into transparency.
  mipmap-*/ic_launcher_monochrome.png  a crisp silhouette of the mark alone, for
      Android 13+ themed icons.
  mipmap-*/ic_launcher.png             the whole square, opaque, for pre-O.
  design/logo-mark.png                 the artwork on transparency, full size.
  design/play-store-icon-512.png       Play Console listing icon (no alpha).

Two things worth knowing before editing this:

Black is not painted, it is transparency. The `<background>` layer is
`@color/surface_dark` (#FF000000), and the source is the artwork composited over
black, so alpha = the pixel's brightest channel and RGB = the pixel normalised to
that brightness reproduces the master exactly once the layers are stacked. That
also means no rounded corner is ever drawn twice: the outside of the squircle is
pure black, i.e. fully transparent.

The monochrome layer cannot reuse the foreground. Themed icons tint by alpha
alone, and the foreground's alpha includes the decorative rings (they reach
brightness 115 out of 255), which would come back as a muddy halo. The mark's
body is above MONO_HI and nothing else is, so a separate high threshold gives a
clean silhouette that still lines up, because it is cut from the same 1:1 canvas.
"""

import pathlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "logo.png"
RES = ROOT / "android/app/src/main/res"
DESIGN = ROOT / "design"

FG_CANVAS_DP = 108
SAFE_RADIUS_DP = 36.0  # every launcher mask keeps at least the centre 72dp circle
# When the mark overshoots the safe radius, the adaptive-icon layers are scaled
# down (centred, transparent-padded) so the mark lands here -- just inside the
# safe zone with a hair of margin. The legacy icon stays full-bleed.
SAFE_TARGET_DP = 35.7
LEGACY_DP = 48
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

MONO_CORE = 80
SPECK_THRESHOLD = 200
SPECK_CONTEXT = 25


def max_channel(rgb):
    r, g, b = rgb.split()
    return ImageChops.lighter(ImageChops.lighter(r, g), b)


def despeckle(rgb):
    """Repair isolated hot pixels. The generated artwork carries a handful of
    stray near-#00FF00 dots out in the black; they average away when the whole
    square is downscaled but they survive at full size, and one sits far enough
    out that it would land outside the safe zone.

    "Isolated" has to be part of the test, not just "bright". The mark's rim
    highlights are every bit as bright and only a few pixels wide, so a plain
    morphological opening flags thousands of them and smears the crispest part of
    the design. Blurring the brightness first gives the surroundings: a real
    highlight has a lit neighbourhood, a stray dot does not."""
    bright = max_channel(rgb)
    context = bright.filter(ImageFilter.BoxBlur(7))
    hot = bright.point(lambda v: 255 if v >= SPECK_THRESHOLD else 0)
    dark_around = context.point(lambda v: 255 if v < SPECK_CONTEXT else 0)
    specks = ImageChops.darker(hot, dark_around)
    if not specks.getbbox():
        return rgb, 0
    count = sum(1 for v in specks.getdata() if v)
    specks = specks.filter(ImageFilter.MaxFilter(5))
    return Image.composite(rgb.filter(ImageFilter.MedianFilter(5)), rgb, specks), count


def unpremultiplied(rgb):
    """The artwork with black as transparency: alpha is the brightest channel,
    RGB is the pixel scaled up so that channel hits 255. Composited over black
    this is bit-for-bit the master again."""
    alpha = max_channel(rgb)
    lut = [[min(255, round(c * 255 / a)) if a else 0 for c in range(256)] for a in range(256)]
    alpha_data = list(alpha.getdata())
    bands = []
    for band in rgb.split():
        out = Image.new("L", rgb.size)
        out.putdata([lut[a][c] for c, a in zip(band.getdata(), alpha_data)])
        bands.append(out)
    return Image.merge("RGBA", (*bands, alpha))


def fill_holes(mask):
    """Close off any pocket of black that the threshold left inside the mark.
    Morphology cannot be trusted with this -- a closing wide enough to swallow the
    last pinhole also visibly rounds the mark's corners -- so this floods the
    outside from a corner instead and promotes whatever the flood never reached."""
    outside = ImageChops.invert(mask)
    ImageDraw.floodfill(outside, (0, 0), 0)
    return ImageChops.lighter(mask, outside)


def monochrome(rgb):
    """White, with the mark as a flat silhouette and everything else cut away.

    A brightness threshold alone will not do it. The mark's darkest facet bottoms
    out around 86 while the decorative rings have thin arcs that reach past 100,
    so the two ranges overlap. What separates them is thickness, not brightness:
    the mark is hundreds of pixels across and the arcs are one or two. Hence the
    opening, which erases anything thinner than five pixels, followed by a flood
    fill to close the pinholes the threshold leaves inside the darkest facet.

    The result is deliberately binary. Themed icons tint by alpha, so carrying the
    artwork's own brightness through would reproduce the dark facet as a
    translucent blotch instead of one solid mark; the antialiasing comes from
    downscaling this mask to each density.
    """
    core = max_channel(rgb).point(lambda v: 255 if v >= MONO_CORE else 0)
    core = core.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))
    core = fill_holes(core)
    out = Image.new("RGBA", rgb.size, (255, 255, 255, 255))
    out.putalpha(core)
    return out


def mark_radius_dp(mono):
    """How far the mark reaches from the canvas centre, in dp on the 108dp
    canvas. Measured along the real outline rather than the bounding box, whose
    half-diagonal badly overstates the reach of a shape with rounded corners."""
    w, h = mono.size
    cx, cy = (w - 1) / 2, (h - 1) / 2
    best = 0.0
    for i, a in enumerate(mono.getchannel("A").getdata()):
        if a >= 8:
            best = max(best, ((i % w - cx) ** 2 + (i // w - cy) ** 2) ** 0.5)
    return best / (w / 2) * (FG_CANVAS_DP / 2)


def inset(image, scale):
    """Scale an RGBA layer down by `scale` and re-centre it on a same-size,
    fully transparent canvas. Used to pull the mark back inside the safe zone
    without touching the master; the transparent padding composites as black
    (the background layer), so the icon looks identical minus a little margin."""
    w, h = image.size
    small = image.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    canvas.paste(small, ((w - small.size[0]) // 2, (h - small.size[1]) // 2))
    return canvas


def emit(image, density, name, dp):
    size = int(round(dp * DENSITIES[density]))
    path = RES / f"mipmap-{density}/{name}.png"
    image.resize((size, size), Image.LANCZOS).save(path)
    return path, size


def main():
    rgb = Image.open(SRC).convert("RGB")
    if rgb.size[0] != rgb.size[1]:
        raise SystemExit(f"{SRC.name} must be square, got {rgb.size}")
    clean, specks = despeckle(rgb)
    print(f"source {rgb.size[0]}px, repaired {specks} stray pixel(s)")

    foreground = unpremultiplied(clean)
    mono = monochrome(clean)
    reach = mark_radius_dp(mono)
    if reach > SAFE_RADIUS_DP:
        scale = SAFE_TARGET_DP / reach
        print(f"mark reaches {reach:.1f}dp > {SAFE_RADIUS_DP:.0f}dp safe radius "
              f"-> insetting adaptive layers to {scale * 100:.1f}%")
        foreground = inset(foreground, scale)
        mono = inset(mono, scale)
        reach = mark_radius_dp(mono)
    verdict = "INSIDE" if reach <= SAFE_RADIUS_DP else "CLIPPED BY SOME MASKS"
    print(f"mark reaches {reach:.1f}dp of the {SAFE_RADIUS_DP:.0f}dp safe radius -> {verdict}")

    DESIGN.mkdir(exist_ok=True)
    foreground.save(DESIGN / "logo-mark.png")
    clean.resize((512, 512), Image.LANCZOS).save(DESIGN / "play-store-icon-512.png")

    for density in DENSITIES:
        for image, name, dp in (
            (foreground, "ic_launcher_foreground", FG_CANVAS_DP),
            (mono, "ic_launcher_monochrome", FG_CANVAS_DP),
            (clean, "ic_launcher", LEGACY_DP),
        ):
            path, size = emit(image, density, name, dp)
            print(f"  {path.relative_to(ROOT)} {size}px")

    if reach > SAFE_RADIUS_DP:
        raise SystemExit("mark leaves the safe zone -- shrink it in logo.png and re-run")


if __name__ == "__main__":
    main()

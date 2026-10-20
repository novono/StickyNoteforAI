"""Generate renamed, lighter OFL derivatives for sticky-note handwriting.

Requires fonttools and skia-pathops; originals and their licenses stay bundled.
"""

import concurrent.futures
from pathlib import Path

import pathops
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

RESOURCES = Path(__file__).resolve().parent.parent / "Resources"
FONTS = [
    ("ZhiMangXing-Regular.ttf", "PaperXing", 10),
    ("LiuJianMaoCao-Regular.ttf", "PaperCao", 5),
    ("LXGWWenKai-Regular.ttf", "PaperKai", 4),
    ("Caveat[wght].ttf", "PaperLatinXing", 3),
    ("Kalam-Regular.ttf", "PaperLatinKai", 4),
    ("Allura-Regular.ttf", "PaperLatinCao", 1.5),
]


def build(item):
    source, family, inset = item
    font = TTFont(RESOURCES / source)
    if "fvar" in font:
        font = instantiateVariableFont(font, {"wght": 400}, inplace=True)

    glyphs = font.getGlyphSet()
    changed = {}
    fallback = 0
    for name in font.getGlyphOrder():
        original = pathops.Path()
        glyphs[name].draw(original.getPen(glyphs))
        if not original.area:
            continue
        original = pathops.simplify(original)
        radius = inset
        result = original
        # Reduce inset for small glyphs rather than erasing narrow strokes.
        for _ in range(4):
            edge = pathops.Path(original)
            edge.stroke(
                radius * 2, pathops.LineCap.ROUND_CAP, pathops.LineJoin.ROUND_JOIN, 2
            )
            edge.convertConicsToQuads(0.25)
            candidate = pathops.op(original, edge, pathops.PathOp.DIFFERENCE)
            if candidate.area >= original.area * 0.68:
                result = candidate
                break
            radius *= 0.6
        if result is original:
            fallback += 1
        result.convertConicsToQuads(0.25)
        pen = TTGlyphPen(None)
        result.draw(Cu2QuPen(pen, max_err=0.6, reverse_direction=True))
        changed[name] = pen.glyph()

    for name, glyph in changed.items():
        font["glyf"][name] = glyph
        glyph.recalcBounds(font["glyf"])
        width, _ = font["hmtx"][name]
        font["hmtx"][name] = (width, getattr(glyph, "xMin", 0))
    for tag in ["fpgm", "prep", "cvt ", "hdmx", "VDMX", "LTSH", "DSIG"]:
        if tag in font:
            del font[tag]

    # Keep copyright and OFL records while giving derivatives distinct names.
    names = font["name"]
    names.names = [
        record for record in names.names if record.nameID not in (1, 2, 3, 4, 6, 16, 17)
    ]
    values = {
        1: family,
        2: "Light",
        3: family + " Light 1.0",
        4: family + " Light",
        6: family + "-Light",
        16: family,
        17: "Light",
    }
    for key, value in values.items():
        names.setName(value, key, 3, 1, 0x409)
        names.setName(value, key, 1, 0, 0)
    font["OS/2"].usWeightClass = 300
    font["OS/2"].fsSelection = 0x40
    font["head"].macStyle = 0
    output = RESOURCES / (family + "-Light.ttf")
    font.save(output)
    print(
        output.name,
        len(changed),
        "glyphs; unchanged small glyphs:",
        fallback,
        flush=True,
    )
    return output


if __name__ == "__main__":
    with concurrent.futures.ProcessPoolExecutor(max_workers=3) as pool:
        list(pool.map(build, FONTS))

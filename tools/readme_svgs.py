#!/usr/bin/env python3
"""Generates the animated SVGs used by README.md (GitHub strips JS/CSS from READMEs,
but animations inside SVG images still run).

    python3 tools/readme_svgs.py        -> writes docs/readme/*.svg
"""
from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(__file__).resolve().parent.parent / "docs" / "readme"

PINK, VIOLET, CYAN, AMBER, YELLOW = "#ff87ff", "#af87ff", "#5fffff", "#ffaf00", "#ffff00"
TERM_BG, TERM_EDGE, BAR_BG = "#0b0b12", "#2c2c3e", "#1b1b28"
MONO = "Cascadia Mono, Consolas, 'DejaVu Sans Mono', Menlo, monospace"

# 5 pixel high font, same style as the installer's small title letters
FONT = {
    "A": [".##.", "#..#", "####", "#..#", "#..#"], "B": ["###.", "#..#", "###.", "#..#", "###."],
    "C": [".###", "#...", "#...", "#...", ".###"], "D": ["###.", "#..#", "#..#", "#..#", "###."],
    "E": ["####", "#...", "###.", "#...", "####"], "F": ["####", "#...", "###.", "#...", "#..."],
    "G": [".###", "#...", "#.##", "#..#", ".###"], "H": ["#..#", "#..#", "####", "#..#", "#..#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"],      "J": ["...#", "...#", "...#", "#..#", ".##."],
    "K": ["#..#", "#.#.", "##..", "#.#.", "#..#"], "L": ["#...", "#...", "#...", "#...", "####"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"], "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
    "O": [".##.", "#..#", "#..#", "#..#", ".##."], "P": ["###.", "#..#", "###.", "#...", "#..."],
    "Q": [".##.", "#..#", "#..#", "#.#.", ".#.#"], "R": ["###.", "#..#", "###.", "#.#.", "#..#"],
    "S": [".###", "#...", ".##.", "...#", "###."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#..#", "#..#", "#..#", "#..#", ".##."], "V": ["#...#", "#...#", ".#.#.", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"], "X": ["#..#", "#..#", ".##.", "#..#", "#..#"],
    "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],      "Z": ["####", "...#", ".##.", "#...", "####"],
    "0": [".##.", "#.##", "#..#", "##.#", ".##."], "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###.", "...#", ".##.", "#...", "####"], "3": ["###.", "...#", ".##.", "...#", "###."],
    "!": ["#", "#", "#", ".", "#"], "?": ["###.", "...#", ".##.", "....", ".#.."], ".": [".", ".", ".", ".", "#"],
    "'": ["#", "#", ".", ".", "."], "-": ["...", "...", "###", "...", "..."],
}

# 4 pixel high marquee font, copied from the installer
TINY = {
    "A": [".#.", "#.#", "###", "#.#"], "B": ["##.", "###", "#.#", "###"], "D": ["##.", "#.#", "#.#", "##."],
    "E": ["###", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#.."], "I": ["###", ".#.", ".#.", "###"],
    "L": ["#..", "#..", "#..", "###"], "M": ["#...#", "##.##", "#.#.#", "#...#"], "N": ["#..#", "##.#", "#.##", "#..#"],
    "O": ["###", "#.#", "#.#", "###"], "R": ["##.", "#.#", "##.", "#.#"], "S": [".##", "#..", "..#", "##."],
    "T": ["###", ".#.", ".#.", ".#."], "U": ["#.#", "#.#", "#.#", "###"], "X": ["#.#", ".#.", ".#.", "#.#"],
    "Y": ["#.#", "#.#", ".#.", ".#."], "W": ["#...#", "#...#", "#.#.#", ".#.#."], "v": ["...", "#.#", "#.#", ".#."],
    ".": [".", ".", ".", "#"], "0": [".#.", "#.#", "#.#", ".#."], "1": [".#", "##", ".#", ".#"],
    "K": ["#.#", "##.", "#.#", "#.#"], "H": ["#.#", "###", "#.#", "#.#"], "C": [".##", "#..", "#..", ".##"],
    "G": [".##", "#..", "#.#", ".##"], "P": ["##.", "#.#", "##.", "#.."], "J": ["..#", "..#", "#.#", ".#."],
}


def pixel_letters(text, font, px, gap=1, space=3):
    """Returns ([(x_offset, width, [rects])...], total_width) with rects in pixel units."""
    out, x = [], 0
    for ch in text:
        if ch == " ":
            x += space
            continue
        g = font[ch]
        rects = [(x + c, r) for r, row in enumerate(g) for c, v in enumerate(row) if v == "#"]
        out.append((x, len(g[0]), rects))
        x += len(g[0]) + gap
    return out, (x - gap) * px


def header(name, first, second):
    """A neon sign: pixel letters that wave, a pulsing glow and a shine that sweeps across."""
    px, pad = 6, 22
    words = [(first, PINK), (second, CYAN)]
    letters, x = [], 0
    for wi, (word, color) in enumerate(words):
        if wi:
            x += 4
        ls, _ = pixel_letters(word, FONT, px)
        for (lx, lw, rects) in ls:
            letters.append((x + lx, lw, [(x + rx, ry) for (rx, ry) in rects], color))
        x += pixel_letters(word, FONT, px)[1] // px
    w, h = x * px + 2 * pad, 5 * px + 2 * pad
    body = []
    for i, (lx, lw, rects, color) in enumerate(letters):
        rs = "".join(f'<rect x="{(rx) * px}" y="{ry * px}" width="{px}" height="{px}"/>' for (rx, ry) in rects)
        body.append(f'<g class="l" fill="{color}" style="animation-delay:{-i * 0.12:.2f}s">{rs}</g>')
    letters_svg = "".join(body)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h + 8}" viewBox="0 -8 {w} {h + 8}" role="img" aria-label="{escape(first + ' ' + second)}">
<style>
  .l {{ animation: wave 2.4s ease-in-out infinite; }}
  @keyframes wave {{ 0%, 100% {{ transform: translateY(0); }} 50% {{ transform: translateY(-5px); }} }}
  .glow {{ animation: pulse 2.2s ease-in-out infinite; }}
  @keyframes pulse {{ 0%, 100% {{ opacity: .55; }} 50% {{ opacity: 1; }} }}
  .shine {{ animation: sweep 3.8s linear infinite; }}
  @keyframes sweep {{ 0% {{ transform: translateX(-160px); }} 60%, 100% {{ transform: translateX({w + 160}px); }} }}
</style>
<defs>
  <filter id="g{name}" x="-20%" y="-60%" width="140%" height="220%"><feGaussianBlur stdDeviation="5"/></filter>
  <linearGradient id="s{name}" x1="0" x2="1"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff" stop-opacity=".85"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
  <g id="t{name}">{letters_svg}</g>
  <clipPath id="c{name}"><use href="#t{name}"/></clipPath>
</defs>
<rect x="0" y="-8" width="{w}" height="{h + 8}" rx="12" fill="{TERM_BG}" stroke="{TERM_EDGE}"/>
<g transform="translate({pad},{pad})">
  <use href="#t{name}" class="glow" filter="url(#g{name})"/>
  <use href="#t{name}"/>
  <g clip-path="url(#c{name})"><rect class="shine" x="0" y="-12" width="120" height="{5 * px + 24}" fill="url(#s{name})"/></g>
</g>
</svg>'''


def download_button():
    px = 5
    letters, tw = pixel_letters("DOWNLOAD", FONT, px)
    w, h = 560, 120
    tx = (w - tw) // 2
    rects = "".join(f'<rect x="{tx + rx * px}" y="{30 + ry * px}" width="{px}" height="{px}"/>' for (_, _, rs) in letters for (rx, ry) in rs)
    sparkle_cols = ["#ff0000", "#ffaf00", "#ffff00", "#00ff00", "#5fffff", "#ff00ff", "#ffffff", "#af87ff"]
    pts = [(28, 22), (530, 26), (60, 98), (500, 96), (300, 10), (180, 108), (420, 14), (14, 64), (546, 70), (250, 112)]
    sparks = "".join(
        f'<rect class="sp" x="{x}" y="{y}" width="5" height="5" fill="{sparkle_cols[i % len(sparkle_cols)]}" style="animation-delay:{i * 0.27:.2f}s"/>'
        for i, (x, y) in enumerate(pts))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="Download Sentinel-Greenhorn.bat">
<style>
  .halo {{ animation: pulse 2.2s ease-in-out infinite; }}
  @keyframes pulse {{ 0%, 100% {{ opacity: .45; }} 50% {{ opacity: .95; }} }}
  .sp {{ opacity: 0; animation: twinkle 2.7s ease-in-out infinite; }}
  @keyframes twinkle {{ 0%, 100% {{ opacity: 0; }} 15% {{ opacity: 1; }} 35% {{ opacity: 0; }} }}
  .shine {{ animation: sweep 3.2s linear infinite; }}
  @keyframes sweep {{ 0% {{ transform: translateX(-200px); }} 55%, 100% {{ transform: translateX({w + 200}px); }} }}
</style>
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9ffcff"/><stop offset=".45" stop-color="{CYAN}"/><stop offset="1" stop-color="#00afd7"/></linearGradient>
  <linearGradient id="sh" x1="0" x2="1"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff" stop-opacity=".6"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
  <filter id="blur" x="-30%" y="-60%" width="160%" height="220%"><feGaussianBlur stdDeviation="10"/></filter>
  <clipPath id="btn"><rect x="40" y="18" width="{w - 80}" height="{h - 36}" rx="12"/></clipPath>
</defs>
<rect class="halo" x="40" y="18" width="{w - 80}" height="{h - 36}" rx="12" fill="{CYAN}" filter="url(#blur)"/>
<rect x="40" y="18" width="{w - 80}" height="{h - 36}" rx="12" fill="url(#bg)"/>
<g clip-path="url(#btn)"><rect class="shine" x="0" y="0" width="140" height="{h}" fill="url(#sh)"/></g>
<g fill="#06131a">{rects}</g>
<text x="{w // 2}" y="{h - 26}" text-anchor="middle" font-family="{MONO}" font-size="14" fill="#06313a">Sentinel-Greenhorn.bat &#183; one file, no installs</text>
{sparks}
</svg>'''


def terminal(name, title, lines, cps=0.012, hold=4.0, width=958):
    """A Windows Terminal window whose lines are typed out one by one, in a loop.
    lines: [(text, colour, glow)]; an empty text is a blank line."""
    fs, lh, cw = 16, 24, 9.6
    top, left = 58, 22
    h = top + lh * len(lines) + 26
    t, items = 0.6, []
    for i, (text, color, glow) in enumerate(lines):
        y = top + lh * i
        if not text:
            t += 0.15
            continue
        n = len(text)
        full = n * cw
        instant = set(text) <= {"="}
        dur = 0.05 if instant else max(0.05, n * cps)
        steps = 1 if instant else min(n, 40)
        values = ";".join(f"{full * k / steps:.1f}" for k in range(steps + 1))
        cid = f"{name}c{i}"
        flt = f' filter="url(#{name}glow)"' if glow else ""
        items.append(f'''<clipPath id="{cid}"><rect x="{left}" y="{y - fs}" width="0" height="{lh}">
  <set attributeName="width" to="0" begin="{name}loop.begin"/>
  <animate attributeName="width" values="{values}" calcMode="discrete" dur="{dur:.2f}s" begin="{name}loop.begin+{t:.2f}s" fill="freeze"/>
</rect></clipPath>
<text x="{left}" y="{y}" textLength="{full:.1f}" lengthAdjust="spacingAndGlyphs" fill="{color}" clip-path="url(#{cid})"{flt}>{escape(text)}</text>''')
        t += dur + (0.05 if instant else 0.12)
    cycle = t + hold
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{h}" viewBox="0 0 {width} {h}" role="img" aria-label="{escape(title)}" font-family="{MONO}" font-size="{fs}" xml:space="preserve">
<defs>
  <filter id="{name}glow" x="-5%" y="-50%" width="110%" height="200%"><feGaussianBlur stdDeviation="2.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  <pattern id="{name}scan" width="4" height="3" patternUnits="userSpaceOnUse"><rect width="4" height="1" fill="#ffffff" opacity=".035"/></pattern>
</defs>
<rect width="{width}" height="{h}" rx="10" fill="{TERM_BG}" stroke="{TERM_EDGE}"/>
<path d="M10 0 H{width - 10} A10 10 0 0 1 {width} 10 V34 H0 V10 A10 10 0 0 1 10 0 Z" fill="{BAR_BG}"/>
<rect x="12" y="6" width="330" height="28" rx="6" fill="{TERM_BG}"/>
<rect x="24" y="14" width="13" height="13" rx="3" fill="{CYAN}"/>
<text x="46" y="25" font-family="Segoe UI, system-ui, sans-serif" font-size="13" fill="#c9c9da">{escape(title)}</text>
<text x="{width - 110}" y="25" font-family="Segoe UI, system-ui, sans-serif" font-size="14" fill="#9a9ab0">&#8212;   &#9744;   &#10005;</text>
<rect width="0" height="0"><animate id="{name}loop" attributeName="x" from="0" to="0" dur="{cycle:.2f}s" begin="0s;{name}loop.end"/></rect>
{"".join(items)}
<rect y="34" width="{width}" height="{h - 34}" fill="url(#{name}scan)"/>
</svg>'''


def marquee(text, width=958):
    px = 5
    cols = []
    for ch in text:
        if ch == " ":
            cols += [None] * 3
            continue
        g = TINY[ch]
        for c in range(len(g[0])):
            cols.append([r for r in range(4) if g[r][c] == "#"])
        cols.append(None)
    cols += [None] * 30
    period = len(cols) * px
    rects = []
    for rep in (0, 1):
        for i, c in enumerate(cols):
            for r in c or []:
                rects.append(f'<rect x="{rep * period + i * px}" y="{r * px}" width="{px}" height="{px}"/>')
    h = 4 * px + 28
    dur = period / 70
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{h}" viewBox="0 0 {width} {h}" role="img" aria-label="{escape(text)}">
<style>
  .run {{ animation: run {dur:.2f}s linear infinite; }}
  @keyframes run {{ from {{ transform: translateX(0); }} to {{ transform: translateX(-{period}px); }} }}
</style>
<defs>
  <linearGradient id="fade" x1="0" x2="1"><stop offset="0" stop-color="#000"/><stop offset=".06" stop-color="#fff"/><stop offset=".94" stop-color="#fff"/><stop offset="1" stop-color="#000"/></linearGradient>
  <mask id="m"><rect width="{width}" height="{h}" fill="url(#fade)"/></mask>
  <filter id="mg" x="-5%" y="-50%" width="110%" height="200%"><feGaussianBlur stdDeviation="2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
</defs>
<rect width="{width}" height="{h}" rx="10" fill="{TERM_BG}" stroke="{TERM_EDGE}"/>
<g mask="url(#m)"><g transform="translate(0,14)"><g class="run" fill="{AMBER}" filter="url(#mg)">{"".join(rects)}</g></g></g>
</svg>'''


STEPS = [
    ("Saying hello to your PC", "Yay! You did it!"),
    ("The WSL engine", "Hooray! Give yourself a pat on the back, Mr. Greenhorn!"),
    ("Picking a Linux", "Brilliant, Mr. Greenhorn! Bang on target!"),
    ("Fixed IP address", "Good job! You get a gold star in your book today!"),
    ("Speed and memory (.wslconfig)", "Woohoo! That went like clockwork!"),
    ("Setting up the fixed IP", "High five! That was easier than assembling IKEA furniture, right?"),
    ("Spring cleaning the disk", "Look at you go! You'll be fixing other people's computers next!"),
    ("Does Linux work? (the big test)", "Yippee! Somebody get this man a cape!"),
    ("Next stop: Tortugarr on GitHub!", "Thumbs up! You're a natural, Mr. Greenhorn!"),
    ("Done! Hooray!", "Boom! Not bad at all for a greenhorn!"),
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    heads = {
        "how": ("HOW TO", "USE IT"), "steps": ("WHAT HAPPENS", "STEP BY STEP"), "oops": ("WHEN IT", "GOES WRONG"),
        "flags": ("FOR THE", "CURIOUS"), "changes": ("WHAT IT", "CHANGES"), "hood": ("UNDER THE", "HOOD"),
    }
    for key, (a, b) in heads.items():
        (OUT / f"h-{key}.svg").write_text(header(key, a, b), encoding="utf-8")
    (OUT / "download.svg").write_text(download_button(), encoding="utf-8")

    lines = []
    for i, (title, cheer) in enumerate(STEPS):
        lines += [("=" * 64, "#00afff", False), (f"  STEP {i + 1}/10  -  {title}", "#00ffff", False), (f"  *** {cheer} ***", YELLOW, True)]
    lines += [("", "", False), ("  Safety net taken down again. All tidied up - the PC is just like before, only better!", "#00ff5f", False)]
    (OUT / "steps.svg").write_text(terminal("st", "Sentinel Greenhorn - Help is here!", lines), encoding="utf-8")

    oops = [
        ("  [DRY-RUN] Back up the old .wslconfig", "#ffaf00", False),
        ("", "", False),
        ("  Yikes, an error! But only a teeny tiny one.", "#ff5f5f", False),
        ("     (What happened: Back up the old .wslconfig went belly up)", "#808080", False),
        ('  Relax! Even the best of us hear "no" now and then. Sentinel has got your back!', "#ffafff", False),
        ("  Do this and we're back on track: take a screenshot (Win+Shift+S) and send it to Sentinel.", "#ffffaf", False),
        ("", "", False),
        ("  *** Look at you go! You'll be fixing other people's computers next! ***", YELLOW, True),
    ]
    (OUT / "oops.svg").write_text(terminal("oo", "Sentinel Greenhorn - when it goes wrong", oops, cps=0.02, hold=5.0), encoding="utf-8")
    (OUT / "marquee.svg").write_text(marquee("WINDOWS SUBSYSTEMS FOR LINUX INSTALLER FOR DUMMIES v.0.1"), encoding="utf-8")
    print("wrote", ", ".join(sorted(p.name for p in OUT.glob("*.svg"))))


if __name__ == "__main__":
    main()

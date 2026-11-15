"""Собирает SVG из адаптивной иконки Android (фон + передний план, VectorDrawable).
Запуск: python3 scripts/android-icon-to-svg.py <res/drawable> <out.svg>"""
import sys
import xml.etree.ElementTree as ET

A = '{http://schemas.android.com/apk/res/android}'
AAPT = '{http://schemas.android.com/aapt}'
grad_id = 0


def color(c):
    # Android: #AARRGGBB -> SVG: #RRGGBB + opacity
    c = c.lstrip('#')
    if len(c) == 8:
        return '#' + c[2:], int(c[:2], 16) / 255
    return '#' + c, 1.0


def path(el, defs):
    global grad_id
    d = el.get(A + 'pathData')
    fill = el.get(A + 'fillColor')
    if fill:
        rgb, op = color(fill)
        return f'<path d="{d}" fill="{rgb}" fill-opacity="{op:.3f}"/>'
    attr = el.find(AAPT + 'attr')
    g = attr.find('gradient')
    grad_id += 1
    stops = ''.join(
        f'<stop offset="{i.get(A + "offset")}" stop-color="{color(i.get(A + "color"))[0]}"/>' for i in g.findall('item'))
    defs.append(f'<linearGradient id="g{grad_id}" gradientUnits="userSpaceOnUse" x1="{g.get(A + "startX")}" '
                f'y1="{g.get(A + "startY")}" x2="{g.get(A + "endX")}" y2="{g.get(A + "endY")}">{stops}</linearGradient>')
    return f'<path d="{d}" fill="url(#g{grad_id})"/>'


def layer(file, defs):
    out = []
    for el in ET.parse(file).getroot():
        if el.tag == 'path':
            out.append(path(el, defs))
        elif el.tag == 'group':
            sx, sy = el.get(A + 'scaleX', '1'), el.get(A + 'scaleY', '1')
            tx, ty = el.get(A + 'translateX', '0'), el.get(A + 'translateY', '0')
            inner = ''.join(path(p, defs) for p in el if p.tag == 'path')
            out.append(f'<g transform="translate({tx} {ty}) scale({sx} {sy})">{inner}</g>')
    return ''.join(out)


src, dst = sys.argv[1], sys.argv[2]
defs = []
body = layer(f'{src}/ic_launcher_background.xml', defs) + layer(f'{src}/ic_launcher_foreground.xml', defs)
with open(dst, 'w') as f:
    f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">'
            f'<defs>{"".join(defs)}</defs>{body}</svg>\n')

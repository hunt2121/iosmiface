# Слот на місці батареї (виконується з make.py, у його просторі імен).
# Порядок віджетів: погода, батарея, відстань, мін/макс сьогодні, дощ, вітер. Перший — типовий.
# Значення — білі жирні цифри з рожево-блакитним зсувом; одиниці — менші, по нижньому краю цифр;
# значки — контур із тим самим зсувом, на 1 px вищі й нижчі за цифри.
import sys
sys.path.insert(0, HERE)
import weather_icons as WI

SLOT_Y = 102                     # середина цифр значення на екрані
WH = 44                          # висота віджета
WX, WY = 0, SLOT_Y - WH // 2     # лівий верхній кут віджета на екрані
HV = 40                          # висота картинок цифр, одиниць і значків; середина цифр — HV/2
FV = ImageFont.truetype(FD + "Inter-Bold.otf", 28 * K)
FU = ImageFont.truetype(FD + "Inter-Bold.otf", 18 * K)
_b = FV.getbbox("30"); CAP = (_b[3] - _b[1]) / K; DIG_C = (_b[1] + _b[3]) / 2   # висота цифр, середина

def glitch_paint(im, mask, off=1.5):
    for col, dx in ((PNK, -off), (CYN, off), (WHT, 0)):
        m = Image.new("L", im.size, 0); m.paste(mask, (int(dx * K), 0))
        im.paste(Image.new("RGBA", im.size, col + (255,)), (0, 0), m)

def text_mask(s, font, w, align="center", bottom=False):
    """маска рядка: цифри посередині висоти HV; bottom=True — низ знаків по низу цифр (для одиниць)"""
    m = Image.new("L", (int(w * K), HV * K), 0); d = ImageDraw.Draw(m)
    tw = d.textlength(s, font=font, features=["tnum"])
    x = {"center": (w * K - tw) / 2, "left": 0, "right": w * K - tw}[align]
    if bottom:
        bb = d.textbbox((0, 0), s, font=font); y = HV * K / 2 + CAP * K / 2 - bb[3]
    else:
        y = HV * K / 2 - DIG_C
    d.text((x, y), s, font=font, fill=255, features=["tnum"])
    return m

# цифри значень: 0–9, «-» (10), «.» (11) — однакові клітинки
CWV = math.ceil(max(FV.getlength(str(i), features=["tnum"]) for i in range(10)) / K) + 4
def vglyph(s, w=CWV):
    im = Image.new("RGBA", (w * K, HV * K), (0, 0, 0, 0)); glitch_paint(im, text_mask(s, FV, w)); return down(im)
array("dig_val", [vglyph(str(i)) for i in range(10)] + [vglyph("-"), vglyph(".")])
SPV = -7                         # клітинки з запасом на зсув — впритул (цифри tnum широкі)

def icon_mask(draw, extra=2):
    """маска значка заввишки як цифри + 1 px зверху й знизу"""
    Q = 16; m = Image.new("L", (60 * Q, 60 * Q), 0); d = ImageDraw.Draw(m); draw(d, lambda v: v * Q)
    m = m.crop(m.getbbox()); t = (CAP + extra) * K
    return m.resize((max(1, int(m.width * t / m.height)), int(t)), Image.LANCZOS)
LW = lambda q: int(2.6 * q(1))
def wl(d, q, pts): d.line([(q(x), q(y)) for x, y in pts], fill=255, width=LW(q), joint="curve")
def i_umbrella(d, q):
    d.arc([q(4), q(4), q(44), q(44)], 180, 360, fill=255, width=LW(q)); wl(d, q, [(4, 24), (44, 24)])
    wl(d, q, [(24, 24), (24, 44), (19, 44)])
def i_route(d, q):
    wl(d, q, [(4, 40), (14, 26), (24, 32), (36, 14)]); d.ellipse([q(32), q(2), q(44), q(14)], outline=255, width=LW(q))
def i_wind(d, q):
    wl(d, q, [(4, 16), (30, 16)]); d.arc([q(26), q(6), q(38), q(18)], -90, 160, fill=255, width=LW(q))
    wl(d, q, [(4, 26), (38, 26)]); d.arc([q(34), q(26), q(44), q(36)], 180, 450, fill=255, width=LW(q)); wl(d, q, [(4, 36), (22, 36)])
def i_minmax(d, q):
    wl(d, q, [(12, 40), (12, 8)]); wl(d, q, [(5, 15), (12, 8), (19, 15)]); wl(d, q, [(30, 8), (30, 40)]); wl(d, q, [(23, 33), (30, 40), (37, 33)])

def unit_img(name, text=None, icon=None, gap_icon=8):
    """одиниця (менша, по низу цифр) і/або значок праворуч — одна картинка unitIcon числа"""
    tw = math.ceil(FU.getlength(text) / K) + 4 if text else 0
    im_icon = icon_mask(icon) if icon else None
    iw = im_icon.width // K + 3 if im_icon else 0
    w = 1 + tw + (gap_icon if icon else 0) + iw
    im = Image.new("RGBA", (w * K, HV * K), (0, 0, 0, 0))
    if text: glitch_paint(im, text_mask(text, FU, tw + 1, "left", bottom=True))
    if im_icon:
        x = (1 + tw + gap_icon) * K; y = int(HV * K / 2 - im_icon.height / 2)
        for col, dx in ((PNK, -1.3), (CYN, 1.3)):
            im.paste(Image.new("RGBA", im_icon.size, col + (255,)), (x + int(dx * K), y), im_icon)
    return image(name, down(im))

def deg_img(name, extra=None):
    """«°» шрифтом значень (вгорі, як у цифрах); extra — значок праворуч"""
    tw = math.ceil(FV.getlength("°") / K) + 4
    im_icon = icon_mask(extra) if extra else None
    iw = im_icon.width // K + 3 if im_icon else 0
    w = tw + (8 + iw if extra else 0)
    im = Image.new("RGBA", (w * K, HV * K), (0, 0, 0, 0)); glitch_paint(im, text_mask("°", FV, tw, "left"))
    if im_icon:
        x = (tw + 8) * K; y = int(HV * K / 2 - im_icon.height / 2)
        for col, dx in ((PNK, -1.3), (CYN, 1.3)):
            im.paste(Image.new("RGBA", im_icon.size, col + (255,)), (x + int(dx * K), y), im_icon)
    return image(name, down(im))

widgets = []
def widget(name, title, items):
    res.append('<Widget name="%s" widgetName="%s" groupType="general" w="%d" h="%d">' % (name, title, W, WH))
    for ref, x, y in items: res.append('    <Item ref="@%s" x="%d" y="%d"/>' % (ref, round(x - WX), round(y - WY)))
    res.append('</Widget>'); widgets.append(name)

YV = SLOT_Y - HV / 2             # верх картинок значень на екрані

# 1. Погода: «14°» — правий край «°» сталий, значок погоди одразу праворуч (число росте ліворуч)
deg = deg_img("u_deg")
ICS = [WI.centered_icon(p) for _, p in WI.ICONS]
array("wx_icons", ICS); values("wx", "weatherCurrentWeather", "wx_icons", range(len(ICS)))
number("wx_t", "weatherCurrentTemperature", "dig_val", 3, "right", False, SPV, "u_deg")
tw14 = 2 * CWV + SPV + deg.width; IVIS = 29; GAP = 6
XR = round(106 - (tw14 + GAP + IVIS) / 2 + tw14) - 2          # правий край «°» (блок на 2 px ліворуч)
widget("w_weather", "Погода", [("wx_t", XR, YV), ("v_wx", XR + GAP + IVIS // 2 - WI.S // 2, SLOT_Y - 1 - WI.S // 2)])

# 2. Батарея — як була
widget("w_battery", "Батарея", BATT_ITEMS)

# 3. Відстань: «5.43 км» + маршрут
unit_img("u_km", "км", i_route)
number("dist", "healthStepKiloMeter", "dig_val", 5, "center", False, SPV, "u_km", dec=2, doff=-(CWV + SPV - 8))
widget("w_distance", "Відстань", [("dist", 106, YV)])

# 4. Мін / макс сьогодні: «9°/16°» + стрілки
slash = Image.new("RGBA", (12 * K, HV * K), (0, 0, 0, 0)); glitch_paint(slash, text_mask("/", FV, 12)); image("u_slash", down(slash))
deg_img("u_deg_mm", i_minmax)
number("tmin", "weatherTodayTemperatureMin", "dig_val", 3, "right", False, SPV, "u_deg")
number("tmax", "weatherTodayTemperatureMax", "dig_val", 3, "left", False, SPV, "u_deg_mm")
mm_w = (CWV + deg.width) + 12 + (2 * CWV + SPV + deg.width + 8 + 30)   # «9°/16°↑↓»
SX = round(106 - mm_w / 2 + CWV + deg.width)                     # лівий край «/»
widget("w_minmax", "Мін / макс", [("tmin", SX, YV), ("u_slash", SX, YV), ("tmax", SX + 12, YV)])

# 5. Ймовірність дощу: «30%» + парасолька
unit_img("u_rain", "%", i_umbrella)
number("rain", "weatherCurrentChanceOfRain", "dig_val", 3, "center", False, SPV, "u_rain")
widget("w_rain", "Дощ", [("rain", 106, YV)])

# 6. Вітер: «5 м/с» + вітер
unit_img("u_wind", "м/с", i_wind)
number("wind", "weatherCurrentWindSpeed", "dig_val", 3, "center", False, SPV, "u_wind")
widget("w_wind", "Вітер", [("wind", 106, YV)])

res.append('<Slot name="slot_top" type="widget">')
for w in widgets: res.append('    <Item ref="@%s"/>' % w)
res.append('</Slot>')
lay("n", "slot_top", WX, WY)

# Блютуз «немає зв'язку» — поверх слота: чорна плашка, більша за будь-який віджет слота на 1 px з кожного боку
# (межі виміряно на крайніх значеннях: −12°, 12.34 км, 100% …), значок — рівно по центру. Є зв'язок — порожньо.
BX0, BY0, BX1, BY1 = 5, 84, 207, 120
def bt_cover(cols, slash):
    w, h = BX1 - BX0, BY1 - BY0
    im = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    ic = bt_frame(cols, slash)
    im.alpha_composite(ic, (round(106 - BX0 - ic.width / 2), round(SLOT_Y - BY0 - ic.height / 2) + 1))   # значок на 1 px нижче, плашка на місці
    return im
array("bt_cover", [bt_cover(((PNK, -1.5), (CYN, 1.5)), PNK), Image.new("RGBA", (BX1 - BX0, BY1 - BY0), (0, 0, 0, 0))])
values("bt_cover", "systemStatusBluetooth", "bt_cover", [0, 1])
lay("n", "v_bt_cover", BX0, BY0)

# Слот на місці батареї (виконується з make.py, у його просторі імен).
# Порядок віджетів: батарея, погода, відстань. Перший — типовий.
# Значення — білі жирні цифри з рожево-блакитним зсувом; одиниці — менші, по нижньому краю цифр;
# значки — контур із тим самим зсувом, на 1 px вищі й нижчі за цифри.
import sys
sys.path.insert(0, HERE)
import weather_icons as WI

SLOT_Y = 102                     # середина цифр значення на екрані
WH = 96                          # висота віджета (рамка вибору) — більша за смугу між датою й годинами, щоб легше влучати; усі елементи мають бути всередині, інакше браслет їх обрізає
WX, WY = 0, SLOT_Y - WH // 2     # лівий верхній кут віджета на екрані (рамка — симетрично довкола значення)
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
    return image(name, pad_left(down(im)))

def pad_left(im, p=None):
    """браслет малює одиницю там, де стала б наступна цифра (з від'ємним space) — додаємо цей зсув зліва"""
    p = -SPV if p is None else p
    out = Image.new("RGBA", (im.width + p, im.height), (0, 0, 0, 0)); out.paste(im, (p, 0)); return out

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
    return image(name, pad_left(down(im)))

widgets = []
def widget(name, key, items):
    """віджет слота; key — службова назва, як в офіційних циферблатах (Weather, Battery, Distance):
    за нею браслет показує назву в меню й, схоже, вирішує, які дані віджету потрібні"""
    res.append('<Widget name="%s" widgetName="%s" groupType="general" w="%d" h="%d">' % (name, key, W, WH))
    for ref, x, y in items:
        assert 0 <= round(y - WY) and 0 <= round(x - WX) or ref == "bat_n", (name, ref, x - WX, y - WY)   # не за межами віджета
        res.append('    <Item ref="@%s" x="%d" y="%d"/>' % (ref, round(x - WX), round(y - WY)))
    res.append('</Widget>'); widgets.append(name)

def row(name, refs, gap=0):
    """рядок по центру: браслет сам ставить елементи один за одним і центрує їх (flex, як в офіційних циферблатах),
    тож число з будь-якою кількістю цифр і значок завжди разом і по центру"""
    res.append('<Widget name="%s" widgetName="number" groupType="general" w="%d" h="%d" flex_direction="row" justify_content="center" align_content="center" align_items="center" gap="%d">' % (name, W, HV, gap))
    for r in refs: res.append('    <Item ref="@%s" x="0" y="0"/>' % r)
    res.append('</Widget>')
    return (name, WX, YV)

def plain_img(name, text=None, icon=None, gap_text=2, gap_icon=8, font=None):
    """одиниця й/або значок як окрема картинка рядка (без від'ємного space — нічого не налазить)"""
    font = font or FU
    tw = math.ceil(font.getlength(text) / K) + 2 if text else 0
    im_icon = icon_mask(icon) if icon else None
    iw = im_icon.width // K + 3 if im_icon else 0
    w = (gap_text if text else 0) + tw + (gap_icon if icon else 0) + iw
    im = Image.new("RGBA", (w * K, HV * K), (0, 0, 0, 0))
    if text:
        m = text_mask(text, font, tw, "left", bottom=(font is FU)); mm = Image.new("L", im.size, 0); mm.paste(m, (gap_text * K, 0)); glitch_paint(im, mm)
    if im_icon:
        x = ((gap_text if text else 0) + tw + gap_icon) * K; y = int(HV * K / 2 - im_icon.height / 2)
        for col, dx in ((PNK, -1.3), (CYN, 1.3)):
            im.paste(Image.new("RGBA", im_icon.size, col + (255,)), (x + int(dx * K), y), im_icon)
    return image(name, down(im))

YV = SLOT_Y - HV / 2             # верх рядка значень на екрані
WNAME = {"ua": ("Батарея", "Погода", "Відстань", "Нічого"), "ru": ("Заряд", "Погода", "Расстояние", "Ничего")}.get(LANGV, ("Battery", "Weather", "Distance", "None"))   # назви в меню вибору (як в офіційних)

# 1. Погода: «14°» + значок погоди
deg = deg_img("u_deg")            # для AOD (там число з unitIcon)
plain_img("f_deg", "°", font=FV, gap_text=0)
ICS = [WI.centered_icon(p) for _, p in WI.ICONS]
padI = lambda im: (lambda o: (o.paste(im, (2, 0)), o)[1])(Image.new("RGBA", (im.width + 2, im.height), (0, 0, 0, 0)))
array("wx_icons", [padI(i) for i in ICS]); values("wx", "weatherCurrentWeather", "wx_icons", range(len(ICS)))
number("wx_t", "weatherCurrentTemperature", "dig_val", 3, "left", False, SPV)
widget("w_weather", WNAME[1], [row("r_weather", ["wx_t", "f_deg", "v_wx"])])

# 2. Батарея — як була
widget("w_battery", WNAME[0], BATT_ITEMS)

# 3. Відстань: «5.43 км» + маршрут
plain_img("f_km", TXT[LANGV]["km"], i_route)
number("dist", "healthStepKiloMeter", "dig_val", 5, "left", False, SPV, dec=2, doff=-(CWV + SPV - 8))
widget("w_distance", WNAME[2], [row("r_distance", ["dist", "f_km"])])

# для AOD: правий край «°» (як було)
tw14 = 2 * CWV + SPV + deg.width; IVIS = 29; GAP = 6
XR = round(106 - (tw14 + GAP + IVIS) / 2 + tw14) - 2

# Один стиль: усе вибирається лише слотом (батарея — перша, типова). AOD показує батарею сірим.
theme.update({"a_slot": [], "a_bt": []})
# «Нічого» — порожній віджет (одна прозора крапка, бо віджет без елементів може не прийнятися)
image("f_none", Image.new("RGBA", (1, 1), (0, 0, 0, 0)))
widget("w_none", WNAME[3], [("f_none", WX + 106, WY + WH // 2)])
res.append('<Slot name="slot_top" type="widget">')
for w in ["w_battery", "w_weather", "w_distance", "w_none"]: res.append('    <Item ref="@%s"/>' % w)
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

# AOD: погода (перший віджет слота) сірим, без гліча; «немає зв'язку» — та сама плашка, сіра
def gglyph(s, col, w=CWV):
    im = Image.new("RGBA", (w * K, HV * K), (0, 0, 0, 0)); im.paste(Image.new("RGBA", im.size, col + (255,)), (0, 0), text_mask(s, FV, w)); return down(im)
array("dig_val_a", [gglyph(str(i), G2) for i in range(10)] + [gglyph("-", G2), gglyph(".", G2)])
tw_ = math.ceil(FV.getlength("°") / K) + 4
dg = Image.new("RGBA", (tw_ * K, HV * K), (0, 0, 0, 0)); dg.paste(Image.new("RGBA", dg.size, G2 + (255,)), (0, 0), text_mask("°", FV, tw_, "left")); image("u_deg_a", pad_left(down(dg)))
array("wx_icons_a", [padI(WI.centered_icon(p, ((G2, 0),))) for _, p in WI.ICONS]); values("wx_a", "weatherCurrentWeather", "wx_icons_a", range(len(WI.ICONS)))
tw2 = math.ceil(FV.getlength("°") / K) + 2
dga = Image.new("RGBA", (tw2 * K, HV * K), (0, 0, 0, 0)); dga.paste(Image.new("RGBA", dga.size, G2 + (255,)), (0, 0), text_mask("°", FV, tw2, "left")); image("f_deg_a", down(dga))
number("wx_t_a", "weatherCurrentTemperature", "dig_val_a", 3, "left", False, SPV)
r = row("r_weather_a", ["wx_t_a", "f_deg_a", "v_wx_a"])        # той самий рядок, що й на звичайному екрані — значок і текст на тих самих місцях
R_WX_A = r
array("bt_cover_a", [bt_cover(((G2, 0),), G2), Image.new("RGBA", (BX1 - BX0, BY1 - BY0), (0, 0, 0, 0))])
values("bt_cover_a", "systemStatusBluetooth", "bt_cover_a", [0, 1])
lay("a_bt", "v_bt_cover_a", BX0, BY0)

# AOD «Батарея»: та сама батарея, сіра (елементи batt_a / bat_a з make.py), на тому ж місці, що у віджеті
BATT_ITEMS_A = [(ref[:-1] + "a", x, y) for ref, x, y in BATT_ITEMS]

# AOD «Відстань»: «5.43 км» + маршрут, сірим, той самий рядок, що й на звичайному екрані
def plain_img_gray(name, text=None, icon=None, gap_text=2, gap_icon=8, font=None):
    font = font or FU
    tw = math.ceil(font.getlength(text) / K) + 2 if text else 0
    im_icon = icon_mask(icon) if icon else None
    iw = im_icon.width // K + 3 if im_icon else 0
    w = (gap_text if text else 0) + tw + (gap_icon if icon else 0) + iw
    im = Image.new("RGBA", (w * K, HV * K), (0, 0, 0, 0))
    if text:
        m = text_mask(text, font, tw, "left", bottom=(font is FU)); mm = Image.new("L", im.size, 0); mm.paste(m, (gap_text * K, 0))
        im.paste(Image.new("RGBA", im.size, G2 + (255,)), (0, 0), mm)
    if im_icon:
        x = ((gap_text if text else 0) + tw + gap_icon) * K; y = int(HV * K / 2 - im_icon.height / 2)
        im.paste(Image.new("RGBA", im_icon.size, G2 + (255,)), (x, y), im_icon)
    return image(name, down(im))
plain_img_gray("f_km_a", TXT[LANGV]["km"], i_route)
number("dist_a", "healthStepKiloMeter", "dig_val_a", 5, "left", False, SPV, dec=2, doff=-(CWV + SPV - 8))
r = row("r_distance_a", ["dist_a", "f_km_a"])
# AOD: без віджета (Band 10 не дає вибирати віджет для AOD) — на цьому місці порожньо, лише значок блютуз при обриві

# Генератор циферблата «Глітч» для Xiaomi Smart Band 10 (212×520): картинки + manifest.xml.
# Запуск: python3 make.py  → files/*.png і manifest.xml поруч. Збирає .bin застосунок BandFace (--build-face=).
from PIL import Image, ImageDraw, ImageFont
import os, random, math, shutil
HERE=os.path.dirname(os.path.abspath(__file__)); OUT=os.path.join(HERE,"files")
FD="/usr/share/fonts/opentype/inter/"
K=4                                   # малюємо в 4 рази більше, потім зменшуємо
W,H=212,520
CYN=(0,240,255); PNK=(255,0,90); WHT=(255,255,255)
G1=(200,200,200); G2=(130,130,130); GL=(120,120,120); GR=(180,180,180)
def font(name,size): return ImageFont.truetype(FD+name+".otf",round(size*K))
BLACK=lambda s: font("InterDisplay-Black",s); BOLD=lambda s: font("InterDisplay-Bold",s); SEMI=lambda s: font("Inter-SemiBold",s)
if os.path.isdir(OUT): shutil.rmtree(OUT)
os.makedirs(OUT)
res=[]; theme={"n":[],"a":[]}
def down(img):                        # 4× → 1× з правильною прозорістю
    return img.convert("RGBa").resize((img.width//K,img.height//K),Image.LANCZOS).convert("RGBA")
def save(img,path):
    p=os.path.join(OUT,path); os.makedirs(os.path.dirname(p),exist_ok=True); img.save(p); return path
def image(name,img): res.append('<Image name="%s" src="%s" compressMethod="RLEReversed" format="RGBA32" recolorEnable="false"/>'%(name,save(img,name+".png"))); return img
def array(name,imgs):
    res.append('<ImageArray name="%s" compressMethod="RLEReversed" format="RGBA32" recolorEnable="false">'%name)
    for i,im in enumerate(imgs): res.append('    <Image src="%s"/>'%save(im,"%s/%d.png"%(name,i)))
    res.append('</ImageArray>')
def number(name,src,arr,digits,align="left",lz=True,space=0,unit=None):
    res.append('<DataItemImageNumber name="%s" source="%s" ref="@%s" totalDigits="%d" decimalDigits="0" align="%s" leadingZero="%s" trailingZero="false" renderRule="alwaysShow" rotation="0" decimalOffsetX="0" space="%d"%s/>'
               %(name,src,arr,digits,align,"true" if lz else "false",space,' unitIcon="@%s"'%unit if unit else ""))
def values(name,src,arr,params):
    name="v_"+name
    res.append('<DataItemImageValues name="%s" source="%s" ref="@%s" renderRule="alwaysShow" rotation="0">'%(name,src,arr))
    for v in params: res.append('    <Param value="%d"/>'%v)
    res.append('</DataItemImageValues>')
def lay(t,name,x,y): theme[t].append('<Layout ref="@%s" x="%d" y="%d"/>'%(name,round(x),round(y)))

# ── дрібний текст: усі написи однакової висоти, середина великих літер/цифр — посередині картинки
def text_img(s,f,col,w=None,align="center",h=None):
    b=f.getbbox("0ЧТ"); capc=(b[1]+b[3])/2
    tw=f.getlength(s,features=["tnum"]); ww=w*K if w else math.ceil(tw)+2*K; hh=(h or 24)*K
    im=Image.new("RGBA",(int(ww),int(hh)),(0,0,0,0)); d=ImageDraw.Draw(im)
    x={"center":(ww-tw)/2,"left":0,"right":ww-tw}[align]
    d.text((x,hh/2-capc),s,font=f,fill=col,features=["tnum"])
    return down(im)
def digit_set(f,col,h=24):
    cw=max(f.getlength(str(i),features=["tnum"]) for i in range(10))/K
    cw=math.ceil(cw); return [text_img(str(i),f,col,w=cw,h=h) for i in range(10)],cw
SH=30   # висота дрібних написів
TS=15.5*1.3   # розмір дрібного тексту
Q=K*1.3       # значки на 30% більші
def small(col,tag):
    f=SEMI(TS); ds,cw=digit_set(f,col,SH); array("dig_"+tag,ds); return cw

# ── великі цифри з глічем
def big_set(tag,cy,strips,mode):
    f=BLACK(126)
    adv=max(f.getlength(str(i)) for i in range(10)); PAD=14*K
    cw=int(adv+2*PAD); b=f.getbbox("0123456789"); gh=b[3]-b[1]; CH=int(gh+2*12*K)
    top=cy*K-CH/2                     # верх клітинки в координатах екрана (×K)
    imgs=[]
    for i in range(10):
        s=str(i)
        def mask(dx):
            m=Image.new("L",(cw,CH),0); dd=ImageDraw.Draw(m)
            dd.text(((cw-f.getlength(s))/2+dx*K, CH/2-(b[1]+b[3])/2),s,font=f,fill=255); return m
        im=Image.new("RGBA",(cw,CH),(0,0,0,0))
        if mode=="normal":
            for col,dx in ((PNK,-4),(CYN,4),(WHT,0)): im.paste(Image.new("RGBA",im.size,col+(255,)),(0,0),mask(dx))
        else:   # AOD: сіра кайма зсуву + тонка обвідка цифри, без заливки
            from PIL import ImageChops, ImageFilter
            main=mask(0)
            for col,dx in ((GL,-4),(GR,4)): im.paste(Image.new("RGBA",im.size,col+(255,)),(0,0),ImageChops.subtract(mask(dx),main))
            edge=ImageChops.subtract(main,main.filter(ImageFilter.MinFilter(13)))
            im.paste(Image.new("RGBA",im.size,G1+(255,)),(0,0),edge)
        for (y,h,dx) in strips:           # ті самі «зламані» смуги, що й на мокапі (на весь рядок)
            yy=int(y*K-top); hh=h*K
            if yy+hh<=0 or yy>=CH: continue
            st=im.crop((0,max(0,yy),cw,min(CH,yy+hh))); im.paste(st,(dx*K,max(0,yy)))
        imgs.append(down(im))
    array("big_%s"%tag,imgs)
    return cw//K, CH//K, PAD//K
random.seed(3); strips={192:[],300:[]}
for _ in range(9):
    y=random.randint(110,360); h=random.randint(2,7); dx=random.randint(-14,14)
    k=126/112; c0,c1=(170,192) if y<235 else (300,300); y=round(c1+(y-c0)*k); h=max(2,round(h*k)); dx=round(dx*k)
    strips[c1].append((y,h,dx))

def place_big(t,src,arr,cy,cw,ch,pad):
    name="%s_%s"%(src,t); number(name,src,arr,2,"left",True,-2*pad)
    lay(t,name,106-cw+pad,cy-ch/2)

for t,mode in (("n","normal"),("a","aod")):
    for src,cy in (("timeHour",192),("timeMinute",300)):
        cw,ch,pad=big_set("%s_%s"%(t,src[4:].lower()),cy,strips[cy],mode)
        place_big(t,src,"big_%s_%s"%(t,src[4:].lower()),cy,cw,ch,pad)

# ── дата «// ЧТ_12.11»
WEEK=["НД","ПН","ВТ","СР","ЧТ","ПТ","СБ"]   # dateWeek: 0 — неділя
for t,col in (("n",CYN),("a",G2)):
    f=SEMI(TS); cw=small(col,"c"+t)
    ww=math.ceil(max(f.getlength("// %s_"%w) for w in WEEK)/K)+1
    array("week_"+t,[text_img("// %s_"%w,f,col,w=ww,align="right",h=SH) for w in WEEK])
    values("week_"+t,"dateWeek","week_"+t,range(7))
    dot=image("dot_"+t,text_img(".",f,col,h=SH)); dw=dot.width
    total=ww+2*cw+dw+2*cw; x=106-total/2-2; y=50-SH/2
    lay(t,"v_week_"+t,x,y); x+=ww
    number("day_"+t,"dateDay","dig_c"+t,2); lay(t,"day_"+t,x,y); x+=2*cw
    lay(t,"dot_"+t,x,y); x+=dw
    number("mon_"+t,"dateMonth","dig_c"+t,2); lay(t,"mon_"+t,x,y)

# ── батарея й блютуз (Y=101): батарея з «85%» — по центру, блютуз ліворуч на сталому місці
BW,BH=66,30          # корпус батареї (у ньому — відсоток)
def batt_frame(level,cols,fill):
    # цілі пікселі в масштабі K: проміжки між контуром і заливкою однакові з усіх боків
    Z=K; im=Image.new("RGBA",((BW+10)*Z,(BH+4)*Z),(0,0,0,0)); d=ImageDraw.Draw(im)
    top,bot=2*Z,(2+BH)*Z; ow=2*Z; g=2*Z
    for col,dx in cols:
        l=round((3+dx)*Z); r=l+BW*Z
        d.rounded_rectangle([l,top,r-1,bot-1],radius=6*Z,outline=col,width=ow)
        d.rounded_rectangle([r+Z,(2+BH/2-5)*Z,r+5*Z-1,(2+BH/2+5)*Z-1],radius=Z,fill=col)
    if level>0:
        l=3*Z+ow+g; full=BW*Z-2*ow-2*g
        d.rounded_rectangle([l,top+ow+g,l+max(3*Z,round(full*level))-1,bot-ow-g-1],radius=3*Z,fill=fill)
    return down(im)
def bt_frame(cols,slash):
    im=Image.new("RGBA",(int(30*Q),int(30*Q)),(0,0,0,0)); d=ImageDraw.Draw(im); x,y=15,15
    for col,dx in cols:
        p=[(x-6+dx,y-6),(x+6+dx,y+6),(x+dx,y+12),(x+dx,y-12),(x+6+dx,y-6),(x-6+dx,y+6)]
        d.line([(a*Q,b*Q) for a,b in p],fill=col,width=int(2.4*Q),joint="curve")
    d.line([((x-12)*Q,(y-12)*Q),((x+12)*Q,(y+12)*Q)],fill=slash,width=int(3*Q))
    return down(im)
# батарея по центру, відсоток — усередині корпусу (по центру, хоч 5%, хоч 100%); блютуз — ліворуч на сталому місці
for t,cols,fill,tc in (("n",((PNK,-1.5),(CYN,1.5)),(0,78,92),WHT),("a",((G2,0),),(45,45,45),G1)):
    array("batt_"+t,[batt_frame(l/10,cols,fill) for l in range(11)])
    values("batt_"+t,"systemStatusBattery","batt_"+t,[l*10 for l in range(11)])
    empty=Image.new("RGBA",(round(30*1.3),round(30*1.3)),(0,0,0,0))
    array("bt_"+t,[bt_frame(cols,PNK if t=="n" else G2),empty])     # 0 — зв'язку немає: значок; 1 — є: порожньо
    values("bt_"+t,"systemStatusBluetooth","bt_"+t,[0,1])
    f=SEMI(17); pct=image("pct_"+t,text_img("%",f,tc,h=SH))
    ds,cw=digit_set(f,tc,SH); array("dig_b"+t,ds)
    number("bat_"+t,"systemStatusBattery","dig_b"+t,3,"center",False,0,"pct_"+t)
    Y=101; bx=106-BW/2               # лівий край корпусу
    lay(t,"v_batt_"+t,bx-3,Y-BH/2-2); lay(t,"bat_"+t,106,Y-SH/2); lay(t,"v_bt_"+t,bx-26-15*1.3,Y-15*1.3)

# ── секунди (лише звичайний екран)
fs=BOLD(33*1.3); ds,cw=digit_set(fs,PNK,56); array("dig_sec",ds)
number("sec","timeSecond","dig_sec",2,"left",True); lay("n","sec",106-cw,390-28)

# ── кроки й пульс: число + значок праворуч (значок — частина числа, тож браслет центрує весь рядок)
def icon_steps(cols):
    im=Image.new("RGBA",(int(26*Q),SH*K),(0,0,0,0)); d=ImageDraw.Draw(im); cy=SH*K/Q/2
    for col,dx in cols:
        for fx,fy,s in ((12,cy+2.5,1),(19,cy-2.5,1)):   # два сліди: підошва + п'ята
            x=fx+dx
            d.ellipse([(x-3)*Q,(fy-6.5)*Q,(x+3)*Q,(fy+2.5)*Q],fill=col)
            d.ellipse([(x-2.3)*Q,(fy+3.5)*Q,(x+2.3)*Q,(fy+7)*Q],fill=col)
    return down(im)
def icon_heart(cols):
    im=Image.new("RGBA",(int(26*Q),SH*K),(0,0,0,0)); d=ImageDraw.Draw(im); cy=SH*K/Q/2
    for col,dx in cols:
        x=16+dx; r=4.2
        d.ellipse([(x-8.4)*Q,(cy-6.5)*Q,(x)*Q,(cy+1.9)*Q],fill=col); d.ellipse([(x)*Q,(cy-6.5)*Q,(x+8.4)*Q,(cy+1.9)*Q],fill=col)
        d.polygon([((x-8.1)*Q,(cy-1.2)*Q),((x+8.1)*Q,(cy-1.2)*Q),(x*Q,(cy+7.5)*Q)],fill=col)
    return down(im)
def centered(t,name,src,digits,col,cy,icon):
    image("ico_"+name,icon); small(col,"s"+name)
    number(name,src,"dig_s"+name,digits,"center",False,0,"ico_"+name)
    lay(t,name,106,cy-SH/2)            # для align=center x — середина рядка
GLC=((PNK,-1),(CYN,1)); GLP=((CYN,-1),(PNK,1))
centered("n","steps_n","healthStepCount",5,CYN,447,icon_steps(GLC))
centered("n","pulse_n","healthHeartRate",3,PNK,481,icon_heart(GLP))
centered("a","steps_a","healthStepCount",5,G2,433.3,icon_steps(((G2,0),)))

names=[l.split('name="')[1].split('"')[0] for l in res if ' name="' in l]
assert len(names)==len(set(names)), [n for n in names if names.count(n)>1]
xml=['<?xml version="1.0" encoding="UTF-8"?>','<Watchface id="318470552" name="Глітч">','    <Resources>']
xml+=["        "+r for r in res]+['    </Resources>','    <Theme type="normal" name="Глітч" bgColor="#000000">']
xml+=["        "+l for l in theme["n"]]+['    </Theme>','    <Theme type="AOD" name="AOD" bgColor="#000000">']
xml+=["        "+l for l in theme["a"]]+['    </Theme>','</Watchface>']
open(os.path.join(HERE,"manifest.xml"),"w",encoding="utf-8").write("\n".join(xml)+"\n")
print("ok", len(res), "resources")

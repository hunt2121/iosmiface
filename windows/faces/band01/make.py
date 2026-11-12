# «BAND·01» для Xiaomi Smart Band 10 (212×520): LCD-цифри Digital-7 з ледь помітною підкладкою «8»,
# піксельні іконки, анімований астронавт. AOD — ті самі картинки під чорним напівпрозорим шаром.
from PIL import Image, ImageDraw, ImageFont, ImageChops
import os, math, shutil, sys
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
import d7cyr as D7, pix
LANGV=os.environ.get("LANGV","ua")
DEST=os.environ.get("FACE_DEST") or os.path.join(os.path.dirname(HERE),"band01" if LANGV=="ua" else "band01-"+LANGV)
OUT=os.path.join(DEST,"files")
FACE_ID={"ua":"318470570","ru":"318470571","en":"318470572","en12":"318470573"}[LANGV]; FACE_NAME="BAND 01"
SA=os.environ.get("SA_FRAMES","/tmp/claude-0/-home-claude/db6005de-023b-57f2-8d4f-7e2b4fccd61e/scratchpad/sa_out2")
H12=LANGV=="en12"
W,H=212,520; K=4
WH=(255,255,255); DIM=(150,150,155); GHOST=(50,50,50)
FD="/usr/share/fonts/opentype/inter/"
F=lambda w,s,disp=True: ImageFont.truetype(FD+("InterDisplay-" if disp else "Inter-")+w+".otf",round(s*K))
TXT={"ua":("СТИКУВАННЯ · У НОРМІ","ЗВ'ЯЗОК ВТРАЧЕНО",["НД","ПН","ВТ","СР","ЧТ","ПТ","СБ"]),
     "ru":("СТЫКОВКА · В НОРМЕ","СВЯЗЬ ПОТЕРЯНА",["ВС","ПН","ВТ","СР","ЧТ","ПТ","СБ"]),
     "en":("DOCKING · NOMINAL","CONNECTION LOST",["SUN","MON","TUE","WED","THU","FRI","SAT"])}
TXT["en12"]=TXT["en"]
ST_OK,ST_LOST,WEEK=TXT[LANGV]    # dateWeek: 0 — неділя

if os.path.isdir(OUT): shutil.rmtree(OUT)
os.makedirs(OUT); res=[]; theme={"n":[],"a":[]}
def save(im,p):
    q=os.path.join(OUT,p); os.makedirs(os.path.dirname(q),exist_ok=True); im.save(q); return p
def image(n,im): res.append('<Image name="%s" src="%s" compressMethod="RLEReversed" format="RGBA32" recolorEnable="false"/>'%(n,save(im,n+".png"))); return im
def array(n,ims):
    res.append('<ImageArray name="%s" compressMethod="RLEReversed" format="RGBA32" recolorEnable="false">'%n)
    for i,im in enumerate(ims): res.append('    <Image src="%s"/>'%save(im,"%s/%d.png"%(n,i)))
    res.append('</ImageArray>')
def number(n,src,arr,digits,align,lz,space,unit=None):
    res.append('<DataItemImageNumber name="%s" source="%s" ref="@%s" totalDigits="%d" decimalDigits="0" align="%s" leadingZero="%s" trailingZero="false" renderRule="alwaysShow" rotation="0" decimalOffsetX="0" space="%d"%s/>'%(n,src,arr,digits,align,"true" if lz else "false",space,' unitIcon="@%s"'%unit if unit else ""))
def values(n,src,arr,ps):
    res.append('<DataItemImageValues name="%s" source="%s" ref="@%s" renderRule="alwaysShow" rotation="0">'%(n,src,arr))
    for p in ps: res.append('    <Param value="%d"/>'%p)
    res.append('</DataItemImageValues>')
def rnd(v): return math.floor(v+0.5-1e-9)   # пів пікселя — ліворуч / вгору (а не банківське округлення)
def lay(t,n,x,y): theme[t].append('<Layout ref="@%s" x="%d" y="%d"/>'%(n,rnd(x),rnd(y)))
def tint(L,col):
    im=Image.new("RGBA",L.size,col+(0,)); im.putalpha(L); return im

# ── LCD-клітинки Digital-7: однакова ширина, «1» притиснута праворуч (як на справжньому LCD)
from PIL import ImageFont as _IF
_f=_IF.truetype(D7.FONT,400); B8=D7.glyph('8',400).getbbox(); W8=B8[2]-B8[0]; H8=B8[3]-B8[1]; CW=_f.getlength('8'); CC=_f.getlength(':')
def metrics(h): wI=round(W8*h/H8); return wI, round(CW*h/H8)-wI          # ширина клітинки, проміжок між клітинками
def cell(ch,h,col=WH):
    """одна клітинка висотою h (видимі пікселі «8» = вся клітинка)"""
    wI,_=metrics(h); L=D7.cyr(ch,400); bb=L.getbbox(); dx=0
    if bb:
        if ch=='1': dx=B8[2]-bb[2]
        elif ch=='-': dx=(B8[0]+B8[2])/2-(bb[0]+bb[2])/2
        else: dx=B8[0]-bb[0]
    sh=Image.new('L',L.size,0); sh.paste(L,(int(round(dx)),0))
    c=sh.crop((B8[0],B8[1],B8[2],B8[3])).resize((wI,h),Image.LANCZOS)
    return tint(c,col)
def cells_w(n,h): wI,sp=metrics(h); return n*wI+(n-1)*sp
def ghost(n,h,extra=None):
    """підкладка: n клітинок «8» (extra — список позицій x, якщо клітинки нерівномірні)"""
    wI,sp=metrics(h); g=cell('8',h,GHOST); xs=extra or [i*(wI+sp) for i in range(n)]
    im=Image.new("RGBA",(xs[-1]+wI,h),(0,0,0,0))
    for x in xs: im.alpha_composite(g,(x,0))
    return im
def digits(n,h,minus=False):
    array(n,[cell(str(i),h) for i in range(10)]+([cell('-',h)] if minus else []))
def text_lcd(s,h,col=WH):
    wI,sp=metrics(h); im=Image.new("RGBA",(cells_w(len(s),h),h),(0,0,0,0))
    for i,c in enumerate(s): im.alpha_composite(cell(c,h,col),(i*(wI+sp),0))
    return im
def text_img(s,f,col):
    bb=f.getbbox(s); im=Image.new("RGBA",(bb[2]-bb[0]+2*K,bb[3]-bb[1]+2*K),(0,0,0,0))
    ImageDraw.Draw(im).text((K-bb[0],K-bb[1]),s,font=f,fill=col)
    im=im.convert("RGBa").resize((math.ceil(im.width/K),math.ceil(im.height/K)),Image.LANCZOS).convert("RGBA")
    return im.crop(im.getchannel("A").point(lambda v:255 if v>20 else 0).getbbox())
def picon(g,col=WH):
    S=8; im=pix.render(g,S,col); return im.convert("RGBa").resize((round(im.width/S),round(im.height/S)),Image.LANCZOS).convert("RGBA")
def floor_c(x): return math.floor(x)
def ink_x(im,box_w,box_x=0):
    """x для im, щоб ВИДИМІ пікселі (альфа ≥ 64, крайні стовпці — за їх прозорістю) стояли по центру box; пів пікселя — ліворуч"""
    a=im.getchannel("A"); cols=[max(a.getpixel((x,y)) for y in range(im.height)) for x in range(im.width)]
    idx=[i for i,v in enumerate(cols) if v>=64]; l=idx[0]+1-cols[idx[0]]/255; r=idx[-1]+cols[idx[-1]]/255
    want=box_x+box_w/2-(l+r)/2; f=math.floor(want)
    return f if want-f<=0.6 else f+1   # ≈пів пікселя (0,4–0,6) — теж ліворуч

# ── шапка: назва і рядок статусу (перемикається за Bluetooth)
tit=image("title",text_img("BAND·01",F("Black",22),WH)); TX=ink_x(tit,W); TY=round(42.5-tit.height/2)
fs=F("Bold",12,False)
ok=text_img(ST_OK,fs,DIM); lost=text_img(ST_LOST,fs,WH); rune=picon(pix.BT_RUNE)
SH=rune.height; STW=W
def st_frame(parts):
    tw=sum(p.width for p in parts)+6*(len(parts)-1); row=Image.new("RGBA",(tw,SH),(0,0,0,0)); x=0
    for p in parts: row.alpha_composite(p,(x,(SH-p.height)//2)); x+=p.width+6
    im=Image.new("RGBA",(STW,SH),(0,0,0,0)); im.alpha_composite(row,(ink_x(row,STW),0))
    return im
array("st",[st_frame([rune,lost]),st_frame([ok])]); values("v_st","systemStatusBluetooth","st",[0,1])
array("st_a",[st_frame([rune,lost]),Image.new("RGBA",(STW,SH),(0,0,0,0))]); values("v_st_a","systemStatusBluetooth","st_a",[0,1])   # кадри масиву — однакового розміру
STY=round(67.5-SH/2)
lay("n","title",TX,TY); lay("n","v_st",0,STY)

# ── заряд: блискавка · 6 · три клітинки · 5 · % — по центру
h=26; wI,sp=metrics(h); digits("d26",h,True)   # один набір цифр 26 px на все (з мінусом — для температури)
bolt=image("bolt",picon(pix.BOLT))
pc=D7.ring_pct(400); sc=(14/2.4)/pc.info['ring']; pc=pc.resize((round(pc.width*sc*K),round(pc.height*sc*K)),Image.LANCZOS); pc=pc.crop(pc.getbbox())
pc=tint(pc.resize((round(pc.width/K),round(pc.height/K)),Image.LANCZOS),WH)
image("pct",pc)   # «%» — окрема нерухома картинка, не одиниця числа: число вирівнюється рівно по клітинках
tot=bolt.width+6+cells_w(3,h)+5+pc.width; x0=floor_c((W-tot)/2); BY=91
lay("n","bolt",x0,round(BY+13-bolt.height/2))
image("g3",ghost(3,h)); lay("n","g3",x0+bolt.width+6,BY)
xb=x0+bolt.width+6+cells_w(3,h)   # правий край клітинок заряду
number("bat","systemStatusBattery","d26",3,"right",False,sp); lay("n","bat",xb,BY)
lay("n","pct",xb+5,BY+h-pc.height)

# ── годинник 54 px: години · двокрапка · хвилини
hc=54; wc,spc=metrics(hc); digits("d54",hc)
col_=D7.glyph(':',400); cb=col_.getbbox(); colw=round(CC*hc/H8)
cimg=col_.crop((cb[0],B8[1],cb[2],B8[3])); cimg=tint(cimg.resize((max(1,round((cb[2]-cb[0])*hc/H8)),hc),Image.LANCZOS),WH)
colon=image("colon",cimg)
CLW=2*wc+spc+spc+colw+2*wc+spc
Lc=floor_c((W-CLW)/2); Rc=Lc+CLW; YC=136
xh=Lc; hrR=Lc+2*wc+spc; xm=hrR+spc+colw; xcol=hrR+floor_c((xm-hrR-cimg.width)/2)   # однакові проміжки зліва й справа
image("g_clock",ghost(4,hc,[0,wc+spc,xm-Lc,xm-Lc+wc+spc])); lay("n","g_clock",Lc,YC)
hsrc="timeHour12H" if H12 else "timeHour"
number("hr",hsrc,"d54",2,"left",True,spc); number("mn","timeMinute","d54",2,"left",True,spc)
lay("n","hr",xh,YC); lay("n","colon",xcol,YC); lay("n","mn",xm,YC)

# ── сітка під годинником: ЧТ/дата · астронавт + права колонка · кроки — однакові відступи V
G=6
heart=image("heart",picon(pix.HEART))
w3=cells_w(3,h)
degL=D7.cyr('°',400); degL=degL.crop(degL.getbbox()); degL=degL.resize((round(degL.width*9/degL.height),9),Image.LANCZOS)
deg=image("deg",tint(degL,WH))   # «°» — окрема нерухома картинка
colL=Rc-w3
BODY=(31,26,170,224)     # обриси астронавта в кадрі 200×250 (обʼєднання всіх кадрів)
scA=(colL-10-Lc)/(BODY[2]-BODY[0]); bh=(BODY[3]-BODY[1])*scA
# піксельна погода: усі 24 типи одного розміру 14×9 клітинок
CL=pix.CLOUD
def canvas(): return [["."]*14 for _ in range(9)]
def put(c,g,ox,oy):
    for y,r in enumerate(g):
        for x,ch in enumerate(r):
            if ch=="1" and 0<=oy+y<9 and 0<=ox+x<14: c[oy+y][ox+x]="1"
def under(pat):   # хмара вгорі (рядки 0–5) + опади в рядках 6–8
    c=canvas(); put(c,CL,1,0)
    for (x,y) in pat: c[6+y][x]="1"
    return c
def fin(c): return ["".join(r) for r in c]
def sun_c(): c=canvas(); put(c,pix.SUN,2,0); return c
def partly(): return ["".join("1" if v else "." for v in row).ljust(14,".")[:14] for row in pix.PARTLY]
def cloud_c(): c=canvas(); put(c,CL,1,2); return c
def bolt_c(extra=()):
    c=canvas(); put(c,CL,1,0)
    for x,y in [(7,6),(6,7),(7,7),(6,8)]+list(extra): c[y][x]="1"
    return c
def fog():
    c=canvas()
    for y,(a,b) in zip((1,3,5,7),((1,11),(3,13),(0,10),(2,12))):
        for x in range(a,b): c[y][x]="1"
    return c
def tornado():
    c=canvas()
    for y,(a,b) in enumerate(((1,13),(2,12),(3,11),(4,10),(5,9),(5,8),(6,8),(6,7),(7,8))):
        for x in range(a,b):
            if (x+y)%3!=1 or b-a<4: c[y][x]="1"
    return c
def dust():
    c=canvas()
    for y,(a,b) in zip((1,3,5),((0,10),(3,13),(1,9))):
        for x in range(a,b): c[y][x]="1"
    for x,y in ((2,7),(6,8),(10,7),(13,8)): c[y][x]="1"
    return c
def unknown():
    c=canvas(); put(c,CL,1,0)
    for x,y in ((5,6),(6,6),(7,6),(7,7),(6,8)): c[y][x]="1"
    return c
WX=[fin(sun_c()),partly(),fin(cloud_c()),
    fin(under([(2,0),(5,1),(8,0),(11,1),(3,2),(9,2)])),           # злива
    fin(bolt_c()),fin(bolt_c([(10,7),(3,8)])),                     # гроза, з градом
    fin(under([(3,0),(3,1),(7,1),(10,0),(10,1)])),                 # дощ зі снігом
    fin(under([(6,0),(6,1)])),fin(under([(4,0),(4,1),(8,0),(8,1)])),fin(under([(2,0),(2,1),(6,1),(6,2),(10,0),(10,1)])),   # слабкий/помірний/сильний дощ
    fin(bolt_c([(2,7),(11,7),(3,8),(10,8)])),                      # шторм
    fin(under([(6,1)])),fin(under([(6,1)])),fin(under([(4,1),(8,1)])),fin(under([(2,0),(6,2),(10,0)])),   # сніг: короткий/слабкий/помірний/сильний
    fin(under([(1,0),(4,1),(7,2),(10,1),(13,0)])),                 # хуртовина
    fin(tornado()),fin(dust()),
    fin(under([(3,0),(3,1),(7,2),(10,0),(10,1)])),fin(under([(3,1),(7,0),(7,1),(11,1)])),fin(under([(4,1),(6,2),(9,1)])),   # крижаний дощ, сніг із дощем, мокрий сніг
    fin(fog()),fin(unknown()),fin(under([(3,1),(6,2),(9,1),(12,2)]))]
wxi=[picon(g) for g in WX]
def wx_norm(ims):
    # іконки стоять над числом: малюнок притиснутий до низу кадру (відступ до температури не залежить від погоди)
    # і по центру кадру по ширині; кадри масиву — однакового розміру
    W_=max(i.width for i in ims); H_=max(i.height for i in ims); out=[]
    for i in ims:
        bb=i.getchannel("A").point(lambda v:255 if v>=64 else 0).getbbox();   # без ледь видимого «ореолу» від згладжування (альфа 4 під хмарою)
        ink=i.crop(bb); c=Image.new("RGBA",(W_,H_),(0,0,0,0))
        c.alpha_composite(ink,(floor_c((W_-ink.width)/2),H_-ink.height)); out.append(c)
    return out
wxi=wx_norm(wxi); wh_=wxi[0].height
colH=heart.height+G+h+(0)+wh_+G+h
YB=470
V=(YB-(YC+hc)-h*2-bh)/3
colH=heart.height+G+h+V+wh_+G+h
if colH>bh: V=(YB-(YC+hc)-h*2-(heart.height+G+h+wh_+G+h))/4; colH=heart.height+G+h+V+wh_+G+h
Hm=max(bh,colH)
y1=YC+hc+V; y2=y1+h+V; y3=y2+Hm+V
# ряд 1: день тижня (ліворуч від краю годинника) і дата (праворуч)
nwk=max(len(w) for w in WEEK)
array("wk",[text_lcd(w,h) for w in WEEK]); values("v_wk","dateWeek","wk",range(7))
image("g_wk",ghost(nwk,h)); lay("n","g_wk",Lc,y1); lay("n","v_wk",Lc,y1)
DW=cells_w(5,h); xd=Rc-DW
image("g5",ghost(5,h)); lay("n","g5",xd,y1)   # та сама підкладка на 5 клітинок, що й під кроками
image("dash",cell('-',h))
first,second=("dateMonth","dateDay") if H12 else ("dateDay","dateMonth")   # місяць-день лише в EN 12h
number("dd1",first,"d26",2,"left",True,sp); number("dd2",second,"d26",2,"left",True,sp)
lay("n","dd1",xd,y1); lay("n","dash",xd+2*(wI+sp),y1); lay("n","dd2",xd+3*(wI+sp),y1)
# анімація: обриси астронавта від лівого краю годинника, по центру висоти блоку; далі — центр між краєм екрана й колонкою, +5 px
fw,fh=round(200*scA),round(250*scA)
fr=[]
for i in range(1,49):
    im=Image.open(os.path.join(SA,"%d.png"%i)).convert("RGBA")
    fr.append(im.convert("RGBa").resize((fw,fh),Image.LANCZOS).convert("RGBA"))
array("astro",fr)
res.append('<Sprite name="anim" ref="@astro" interval="83" repeatCount="0"/>')
bw=(BODY[2]-BODY[0])*scA
AX=floor_c((colL-bw)/2)+5-BODY[0]*scA; AY=y2+(Hm-bh)/2-BODY[1]*scA
lay("n","anim",AX,AY)
# права колонка: серце над пульсом, погода над температурою; цифри — по правому краю годинника, «°» виступає
yc=y2+(Hm-colH)/2
DOTX=1   # крапкові іконки: щілина праворуч робить їх на вигляд ~0,7 px лівіше — компенсуємо
lay("n","heart",Rc-w3/2-heart.width/2+DOTX,yc)
lay("n","g3",Rc-w3,yc+heart.height+G)   # та сама підкладка на 3 клітинки, що й під зарядом
number("hrt","healthHeartRate","d26",3,"right",False,sp); lay("n","hrt",Rc,yc+heart.height+G)
yt=yc+heart.height+G+h+V+wh_+G
wxp=[(i,im) for i,im in enumerate(wxi) if i==0 or im.tobytes()!=wxi[i-1].tobytes()]   # однакові сусідні значки — один кадр на кілька кодів погоди
array("wx",[im for _,im in wxp]); values("v_wx","weatherCurrentWeather","wx",[i for i,_ in wxp])
lay("n","v_wx",Rc-w3/2-wxi[0].width/2+DOTX,yt-G-wh_+1)   # +1: на браслеті погода виглядала на 1 px вище за серце
lay("n","g3",Rc-w3,yt)
number("tmp","weatherCurrentTemperature","d26",3,"right",False,sp); lay("n","tmp",Rc,yt)   # цифри закінчуються рівно на Rc, як пульс
lay("n","deg",Rc+3,yt+1)
# кроки: сліди · 6 · п'ять клітинок — по центру
soles=image("soles",picon(pix.SOLES)); w5=cells_w(5,h)
tot=soles.width+G+w5; x0=floor_c((W-tot)/2)
lay("n","soles",x0,round(y3+13-soles.height/2))
lay("n","g5",x0+soles.width+G,y3)
number("stp","healthStepCount","d26",5,"right",False,sp); lay("n","stp",x0+tot,y3)

# ── AOD: ті самі картинки без підкладки, поверх — чорний шар 128/255 (50 %, білий → 127); «звʼязок втрачено» — над шаром
for n,(x,y) in (("hr",(xh,YC)),("colon",(xcol,YC)),("mn",(xm,YC)),("v_wk",(Lc,y1)),("dd1",(xd,y1)),("dash",(xd+2*(wI+sp),y1)),("dd2",(xd+3*(wI+sp),y1)),
                ("soles",(x0,round(y3+13-soles.height/2))),("stp",(x0+tot,y3))):
    lay("a",n,x,y)
image("dimmer",Image.new("RGBA",(W,H),(0,0,0,128))); lay("a","dimmer",0,0)   # 50 %
lay("a","v_st_a",0,STY)

names=[r.split('name="')[1].split('"')[0] for r in res if ' name="' in r]
assert len(names)==len(set(names)), [n for n in names if names.count(n)>1]
T=lambda typ,key: ['    <Theme type="%s" name="%s" bgColor="#000000">'%(typ,FACE_NAME)]+["        "+l for l in theme[key]]+['    </Theme>']
xml=['<?xml version="1.0" encoding="UTF-8"?>','<Watchface id="%s" name="%s">'%(FACE_ID,FACE_NAME),'    <Resources>']+["        "+r for r in res]+['    </Resources>']+T("normal","n")+T("AOD","a")+['</Watchface>']
os.makedirs(DEST,exist_ok=True); open(os.path.join(DEST,"manifest.xml"),"w",encoding="utf-8").write("\n".join(xml)+"\n")
print("ok",LANGV,len(res),"V=%.1f Lc=%d Rc=%d sc=%.2f"%(V,Lc,Rc,scA))

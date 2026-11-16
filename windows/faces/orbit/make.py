# «ОРБІТА» для Xiaomi Smart Band 10 (212×520): стрілковий годинник угорі, дата посередині,
# кроки — число в центрі кола з 28 сегментів прогресу; знизу в розриві кола — значок слідів.
# AOD — білі елементи під чорним шаром 50 % (без кольору).
from PIL import Image, ImageDraw, ImageFont
import os, math, shutil
HERE=os.path.dirname(os.path.abspath(__file__))
LANGV=os.environ.get("LANGV","ua")
DEST=os.environ.get("FACE_DEST") or os.path.join(os.path.dirname(HERE),"orbit" if LANGV=="ua" else "orbit-"+LANGV)
OUT=os.path.join(DEST,"files")
FACE_ID={"ua":"318470580","ru":"318470581","en":"318470582"}[LANGV]; FACE_NAME="ORBIT"
W,H=212,520; K=4
WH=(255,255,255); LM=(198,244,50); GY=(110,110,115); DG=(40,40,42); RD=(255,69,58); MG=(160,160,166)
FD="/usr/share/fonts/opentype/inter/"
F=lambda w,s: ImageFont.truetype(FD+"Inter-"+w+".otf",round(s*K))
WEEK={"ua":["НЕДІЛЯ","ПОНЕДІЛОК","ВІВТОРОК","СЕРЕДА","ЧЕТВЕР","ПʼЯТНИЦЯ","СУБОТА"],
      "ru":["ВОСКРЕСЕНЬЕ","ПОНЕДЕЛЬНИК","ВТОРНИК","СРЕДА","ЧЕТВЕРГ","ПЯТНИЦА","СУББОТА"],
      "en":["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"]}   # dateWeek: 0 — неділя
MON={"ua":["СІЧЕНЬ","ЛЮТИЙ","БЕРЕЗЕНЬ","КВІТЕНЬ","ТРАВЕНЬ","ЧЕРВЕНЬ","ЛИПЕНЬ","СЕРПЕНЬ","ВЕРЕСЕНЬ","ЖОВТЕНЬ","ЛИСТОПАД","ГРУДЕНЬ"],
     "ru":["ЯНВАРЬ","ФЕВРАЛЬ","МАРТ","АПРЕЛЬ","МАЙ","ИЮНЬ","ИЮЛЬ","АВГУСТ","СЕНТЯБРЬ","ОКТЯБРЬ","НОЯБРЬ","ДЕКАБРЬ"],
     "en":["JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE","JULY","AUGUST","SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"]}
L=LANGV if LANGV in WEEK else "en"

if os.path.isdir(OUT): shutil.rmtree(OUT)
os.makedirs(OUT); res=[]; theme={"n":[],"a":[]}
def save(im,p):
    q=os.path.join(OUT,p); os.makedirs(os.path.dirname(q),exist_ok=True); im.save(q); return p
def image(n,im): res.append('<Image name="%s" src="%s" compressMethod="RLEReversed" format="RGBA32" recolorEnable="false"/>'%(n,save(im,n+".png"))); return im
def array(n,ims):
    assert len({i.size for i in ims})==1, n
    res.append('<ImageArray name="%s" compressMethod="RLEReversed" format="RGBA32" recolorEnable="false">'%n)
    for i,im in enumerate(ims): res.append('    <Image src="%s"/>'%save(im,"%s/%d.png"%(n,i)))
    res.append('</ImageArray>')
def number(n,src,arr,digits,align):
    res.append('<DataItemImageNumber name="%s" source="%s" ref="@%s" totalDigits="%d" decimalDigits="0" align="%s" leadingZero="false" trailingZero="false" renderRule="alwaysShow" rotation="0" decimalOffsetX="0" space="0"/>'%(n,src,arr,digits,align))
def values(n,src,arr,ps):
    res.append('<DataItemImageValues name="%s" source="%s" ref="@%s" renderRule="alwaysShow" rotation="0">'%(n,src,arr))
    for p in ps: res.append('    <Param value="%d"/>'%p)
    res.append('</DataItemImageValues>')
def pointer(n,src,img,px,py,vr,ar):
    res.append('<DataItemPointer name="%s" source="%s" ref="@%s" param="1000" renderRule="alwaysShow" valueStart="0" valueRange="%d" pivotX="%d" pivotY="%d" angleStart="0" angleRange="%d"/>'%(n,src,img,vr,px,py,ar))
def rnd(v): return math.floor(v+0.5-1e-9)   # пів пікселя — ліворуч / вгору
def lay(t,n,x,y): theme[t].append('<Layout ref="@%s" x="%d" y="%d"/>'%(n,rnd(x),rnd(y)))
def canvas(w,h): im=Image.new("RGBA",(w*K,h*K),(0,0,0,0)); return im,ImageDraw.Draw(im)
def down(im): return im.resize((im.width//K,im.height//K),Image.LANCZOS)
def ink(im,th=64):
    a=im.getchannel("A").point(lambda v:255 if v>=th else 0); return a.getbbox()

# ── годинник угорі
CX,CY,R=106,108,92
def seg(d,p,q,w,col,ox=0,oy=0):
    d.line([((p[0]-ox)*K,(p[1]-oy)*K),((q[0]-ox)*K,(q[1]-oy)*K)],fill=col,width=round(w*K))
    for x,y in (p,q): d.ellipse([(x-ox-w/2)*K,(y-oy-w/2)*K,(x-ox+w/2)*K,(y-oy+w/2)*K],fill=col)
def P(r,deg,cx=CX,cy=CY): a=math.radians(deg-90); return (cx+r*math.cos(a),cy+r*math.sin(a))
im,d=canvas(W,2*CY)
for m in range(60):
    if m%5: seg(d,P(92,m*6),P(86,m*6),1.6,GY)
for h in range(12):
    big=h%3==0; seg(d,P(92,h*30),P(74 if big else 80,h*30),5 if big else 3.2,WH)
image("dial",down(im)); lay("n","dial",0,0)
def hand(name,back,fwd,w,col):
    # стрілка вертикально вгору; вісь — у (px,py)
    ww=math.ceil(w)+4; hh=math.ceil(back+fwd+w)+4; px=ww/2; py=2+w/2+fwd
    im,d=canvas(ww,hh); seg(d,(px,py-fwd),(px,py+back),w,col); image(name,down(im)); return px,py
def place_hand(t,name,img,src,px,py,vr,ar):
    pointer(name,src,img,px,py,vr,ar); lay(t,name,CX-px,CY-py)
hp=hand("h_hour",8,48,9,WH); mp=hand("h_min",8,72,5,LM); sp=hand("h_sec",16,84,1.8,RD); mpa=hand("h_min_a",8,72,5,WH)
def cap(name,col):
    im,d=canvas(16,16); d.ellipse([1*K,1*K,15*K,15*K],fill=col); d.ellipse([5*K,5*K,11*K,11*K],fill=(0,0,0,255)); return image(name,down(im))
cap("cap",LM); cap("cap_a",WH)
# ── дата: число, день тижня, місяць
def cells(chars,font,col):
    # табличні цифри (tnum): однакова ширина, як у звичайному наборі, без зайвих проміжків
    adv=font.getlength("0",features=["tnum"]); cw=math.ceil(adv/K)
    asc,desc=font.getmetrics(); ch=math.ceil((asc+desc)/K)
    out=[]
    for c in chars:
        im,d=canvas(cw,ch); d.text(((cw*K-adv)/2,0),c,font=font,fill=col,anchor="la",features=["tnum"]); out.append(down(im))
    return out
def spaced(t,font,col,sp,w):
    asc,desc=font.getmetrics(); im,d=canvas(w,math.ceil((asc+desc)/K))
    tw=sum(d.textlength(c,font=font) for c in t)+sp*K*(len(t)-1); x=w*K/2-tw/2
    for c in t: d.text((x,0),c,font=font,fill=col); x+=d.textlength(c,font=font)+sp*K
    return down(im)
def word_array(words,font,col,sp,maxw=196):
    # розрядку зменшуємо, якщо найдовше слово не влазить
    tmp,dd=canvas(1,1)
    def width(t,s): return (sum(dd.textlength(c,font=font) for c in t)+s*K*(len(t)-1))/K
    while sp>0.2 and max(width(t,sp) for t in words)>maxw: sp-=0.2
    w=math.ceil(max(width(t,sp) for t in words))+4
    return [spaced(t,font,col,sp,w) for t in words],w,sp
fday=F("Bold",64); array("day",cells("0123456789",fday,WH)); number("v_day","dateDay","day",2,"center")
lay("n","v_day",CX,214); lay("a","v_day",CX,214)
fw=F("Bold",20); wk,wkw,_=word_array(WEEK[L],fw,LM,2.2); array("wk",wk); values("v_wk","dateWeek","wk",range(7)); lay("n","v_wk",CX-wkw/2,290)
wka,_,_=word_array(WEEK[L],fw,WH,2.2); array("wk_a",wka); values("v_wk_a","dateWeek","wk_a",range(7)); lay("a","v_wk_a",CX-wkw/2,290)
fm=F("Bold",18); mo,mow,_=word_array(MON[L],fm,MG,2.0); array("mon",mo); values("v_mon","dateMonth","mon",range(1,13)); lay("n","v_mon",CX-mow/2,317); lay("a","v_mon",CX-mow/2,317)
# ── кроки: коло з 28 сегментів (два нижні — місце для значка), число в центрі
BX,BY=106,428; N=30; GAP=(14,15); RR=72; RW=9
order=[i for i in range(N) if i not in GAP]
frames=[]
for k in range(len(order)+1):
    im,d=canvas(2*RR+2,2*RR+2); o=1
    for j,i in enumerate(order):
        a0=i*360/N+2.2; a1=(i+1)*360/N-2.2
        d.arc([o*K,o*K,(o+2*RR)*K,(o+2*RR)*K],a0-90,a1-90,fill=LM if j<k else DG,width=RW*K)
    frames.append(down(im))
array("ring",frames); values("v_ring","healthStepProgress","ring",[round(k*100/len(order)) for k in range(len(order)+1)])
lay("n","v_ring",BX-RR-1,BY-RR-1)
def feet(col,k=0.8):
    im,d=canvas(24,28); cx,cy=12,14
    def foot(fx,fy,m):
        e=lambda x,y,rx,ry: d.ellipse([(fx+(x*m-rx)*k)*K,(fy+(y-ry)*k)*K,(fx+(x*m+rx)*k)*K,(fy+(y+ry)*k)*K],fill=col)
        e(0,-3.2,4.2,6.2); e(0.6,6.8,3.0,3.2)
    foot(cx-6*k,cy+2.5*k,-1); foot(cx+6*k,cy-2.5*k,1)
    im=down(im); return im.crop(ink(im,1))
fe=image("feet",feet(LM)); fa=image("feet_a",feet(WH))
bb=ink(fe); fx=BX-(bb[2]-bb[0])/2-bb[0]; fy=(BY+RR-RW/2)-(bb[3]-bb[1])/2-bb[1]   # по центру лінії кола
lay("n","feet",fx,fy); lay("a","feet_a",fx,fy)
fs=F("Bold",38); dg=cells("0123456789",fs,WH); array("stp",dg); number("v_stp","healthStepCount","stp",5,"center")
# цифри: видима частина «0» по центру кола
b0=ink(dg[0]); sy=BY-(b0[1]+b0[3])/2
lay("n","v_stp",BX,sy); lay("a","v_stp",BX,sy)
# AM/PM на циферблаті — лише в 12-годинному режимі (miscIs24H = 1 — чорна плашка); під стрілками
AMPM_V=os.environ.get("AMPM_V","bottom")   # над 6
if AMPM_V:
    fa=F("Bold",int(os.environ.get("AMPM_PT","16"))); AW,AH=36,22
    def ampm_img(t):
        im,dd=canvas(AW,AH); dd.text((AW*K/2,AH*K/2),t,font=fa,fill=MG,anchor="mm"); im=down(im)
        b=ink(im); dx=math.floor((AW-1)/2-(b[0]+b[2]-1)/2); dy=math.floor((AH-1)/2-(b[1]+b[3]-1)/2)
        o=Image.new("RGBA",(AW,AH),(0,0,0,0)); o.alpha_composite(im.crop((max(0,-dx),max(0,-dy),AW,AH)),(max(0,dx),max(0,dy))); return o
    array("ampm",[ampm_img("AM"),ampm_img("PM")]); values("v_ampm","miscIsPM","ampm",[0,1])
    array("m24",[Image.new("RGBA",(AW,AH),(0,0,0,0)),Image.new("RGBA",(AW,AH),(0,0,0,255))]); values("v_m24","miscIs24H","m24",[0,1])
    acx,acy={"top":(CX,CY-42),"right":(CX+44,CY),"bottom":(CX,CY+42)}[AMPM_V]
    for n_ in ("v_ampm","v_m24"): lay("n",n_,acx-(AW-1)/2,acy-(AH-1)/2)
# стрілки — поверх усього у верхній частині
place_hand("n","v_hour","h_hour","timeHour",*hp,24,720)
place_hand("n","v_min","h_min","timeMinute",*mp,60,360)
place_hand("n","v_sec","h_sec","timeSecond",*sp,60,360)
lay("n","cap",CX-8,CY-8)
# ── AOD: циферблат і годинна — ті самі; хвилинна, ковпачок, день тижня, сліди — білі копії; без секундної й кола
lay("a","dial",0,0)
theme["a"].append('<Layout ref="@v_hour" x="%d" y="%d"/>'%(rnd(CX-hp[0]),rnd(CY-hp[1])))
pointer("v_min_a","timeMinute","h_min_a",*mpa,60,360); lay("a","v_min_a",CX-mpa[0],CY-mpa[1])
lay("a","cap_a",CX-8,CY-8)
image("dimmer",Image.new("RGBA",(W,H),(0,0,0,128))); lay("a","dimmer",0,0)   # 50 %

names=[r.split('name="')[1].split('"')[0] for r in res if ' name="' in r]
assert len(names)==len(set(names)), [n for n in names if names.count(n)>1]
T=lambda typ,key: ['    <Theme type="%s" name="%s" bgColor="#000000">'%(typ,FACE_NAME)]+["        "+l for l in theme[key]]+['    </Theme>']
xml=['<?xml version="1.0" encoding="UTF-8"?>','<Watchface id="%s" name="%s">'%(FACE_ID,FACE_NAME),'    <Resources>']+["        "+r for r in res]+['    </Resources>']+T("normal","n")+T("AOD","a")+['</Watchface>']
os.makedirs(DEST,exist_ok=True); open(os.path.join(DEST,"manifest.xml"),"w",encoding="utf-8").write("\n".join(xml)+"\n")
print("ok",LANGV,len(res),"wk",wkw,"mon",mow)

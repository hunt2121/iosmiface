# «Лінійка» для Xiaomi Smart Band 10 (212×520): справа шкала годин, помаранчева риска — поточний момент.
# Браслет не дає «хвилину доби», тож шкала зсувається щогодини (24 кадри), а риска рухається за хвилинами (60 кадрів).
from PIL import Image, ImageDraw, ImageFont
import os, math, shutil
HERE=os.path.dirname(os.path.abspath(__file__)); OUT=os.path.join(HERE,"files")
K=4; W,H=212,520; FD="/usr/share/fonts/opentype/inter/"
OR=(255,95,31); WH=(255,255,255); GY=(150,150,155); LG=(170,170,175); DT=(90,90,95)
F=lambda w,s,disp=True: ImageFont.truetype(FD+("InterDisplay-" if disp else "Inter-")+w+".otf",round(s*K))
if os.path.isdir(OUT): shutil.rmtree(OUT)
os.makedirs(OUT); res=[]; theme={"n":[],"a":[]}
def down(im): return im.convert("RGBa").resize((im.width//K,im.height//K),Image.LANCZOS).convert("RGBA")
def save(im,p):
    q=os.path.join(OUT,p); os.makedirs(os.path.dirname(q),exist_ok=True); im.save(q); return p
def image(n,im): res.append('<Image name="%s" src="%s" compressMethod="RLEReversed" format="RGBA32" recolorEnable="false"/>'%(n,save(im,n+".png"))); return im
def array(n,ims):
    res.append('<ImageArray name="%s" compressMethod="RLEReversed" format="RGBA32" recolorEnable="false">'%n)
    for i,im in enumerate(ims): res.append('    <Image src="%s"/>'%save(im,"%s/%d.png"%(n,i)))
    res.append('</ImageArray>')
def number(n,src,arr,digits,align="left",lz=True,space=0):
    arr="d_"+arr        # набори цифр — з префіксом d_, щоб назви не збігалися з числами
    res.append('<DataItemImageNumber name="%s" source="%s" ref="@%s" totalDigits="%d" decimalDigits="0" align="%s" leadingZero="%s" trailingZero="false" renderRule="alwaysShow" rotation="0" decimalOffsetX="0" space="%d"/>'%(n,src,arr,digits,align,"true" if lz else "false",space))
def values(n,src,arr,ps):
    res.append('<DataItemImageValues name="v_%s" source="%s" ref="@%s" renderRule="alwaysShow" rotation="0">'%(n,src,arr))
    for p in ps: res.append('    <Param value="%d"/>'%p)
    res.append('</DataItemImageValues>')
def lay(t,n,x,y): theme[t].append('<Layout ref="@%s" x="%d" y="%d"/>'%(n,round(x),round(y)))
def text_img(s,f,col,w=None,h=40,align="center"):
    b=f.getbbox("0ЧТ"); cc=(b[1]+b[3])/2; tw=f.getlength(s,features=["tnum"]); ww=(w*K) if w else math.ceil(tw)+2*K
    im=Image.new("RGBA",(int(ww),h*K),(0,0,0,0)); x={"center":(ww-tw)/2,"left":0,"right":ww-tw}[align]
    ImageDraw.Draw(im).text((x,h*K/2-cc),s,font=f,fill=col,features=["tnum"]); return down(im)
def digits(n,f,col,h):
    cw=math.ceil(max(f.getlength(str(i),features=["tnum"]) for i in range(10))/K)
    array("d_"+n,[text_img(str(i),f,col,w=cw,h=h) for i in range(10)]); return cw

MID=260; PXH=64; SX0=110      # центр шкали, пікселів на годину, лівий край смуги шкали
def strip(Hh,dim):
    im=Image.new("RGBA",((W-SX0)*K,H*K),(0,0,0,0)); d=ImageDraw.Draw(im); f=F("SemiBold",24)
    c=Hh                        # посередині кадру — H:00, навпроти риски
    for h10 in range(int((c-5)*6),int((c+5)*6)+2):
        h=h10/6; y=MID+(h-c)*PXH
        if not -10<y<H+10: continue
        big=h10%6==0; lc=(110,110,110) if dim else ((255,255,255) if big else DT)
        d.line([((160 if big else 176)-SX0)*K,y*K,(194-SX0)*K,y*K],fill=lc,width=(3 if big else 1)*K)
        if big: d.text(((136-SX0)*K,y*K),"%02d"%((h10//6)%24),font=f,fill=(90,90,90) if dim else LG,anchor="mm")
    return down(im)
PY0,PH=MID-40,80               # область кадрів риски
def pointer(m,dim):
    im=Image.new("RGBA",(W*K,PH*K),(0,0,0,0)); d=ImageDraw.Draw(im); y=40+(m/60-0.5)*PXH; c=(115,115,115) if dim else OR
    d.line([18*K,y*K,196*K,y*K],fill=c,width=2*K); d.polygon([(200*K,(y-8)*K),(188*K,y*K),(200*K,(y+8)*K)],fill=c)
    return down(im)
WEEK=["НД","ПН","ВТ","СР","ЧТ","ПТ","СБ"]
for t,dim in (("n",False),("a",True)):
    if t=="n":
        # шкала їде щохвилини (60 кадрів: поділки повторюються щогодини), риска стоїть посередині;
        # поточна година — біля риски (підписи на шкалі не можуть їхати разом із хвилинами — браслет не дає «хвилину доби»)
        # шкала з підписами годин їде під нерухомою рискою: щогодини зсувається на одну поділку (24 кадри),
        # поточна година — навпроти риски; хвилини показують великі цифри
        array("scale_n",[strip(h,False) for h in range(24)]); values("scale_n","timeHour","scale_n",range(24)); lay(t,"v_scale_n",SX0,0)
        # риска як була — довга, з розривом там, де стоїть підпис поточної години
        im=Image.new("RGBA",(W*K,24*K),(0,0,0,0)); d=ImageDraw.Draw(im)
        d.line([18*K,12*K,118*K,12*K],fill=OR,width=2*K); d.line([154*K,12*K,196*K,12*K],fill=OR,width=2*K)
        d.polygon([(200*K,4*K),(188*K,12*K),(200*K,20*K)],fill=OR)
        image("ptr_n",down(im)); lay(t,"ptr_n",0,MID-12)
    else:
        # AOD — та сама годинна шкала й риска, сіра (шкала змінюється лише раз на годину)
        array("scale_a",[strip(h,True) for h in range(24)]); values("scale_a","timeHour","scale_a",range(24)); lay(t,"v_scale_a",SX0,0)
        g=(115,115,115); im=Image.new("RGBA",(W*K,24*K),(0,0,0,0)); d=ImageDraw.Draw(im)
        d.line([18*K,12*K,118*K,12*K],fill=g,width=2*K); d.line([154*K,12*K,196*K,12*K],fill=g,width=2*K)
        d.polygon([(200*K,4*K),(188*K,12*K),(200*K,20*K)],fill=g)
        image("ptr_a",down(im)); lay(t,"ptr_a",0,MID-12)
    # хвилини, «ХВ», секунди
    fm=F("Bold",72); cw=digits("min_"+t,fm,(115,115,115) if dim else WH,80); number("min_"+t,"timeMinute","min_"+t,2); lay(t,"min_"+t,62-cw,MID-44-40)
    image("xv_"+t,text_img("ХВ",F("Bold",24,False),(115,115,115) if dim else OR,h=24)); lay(t,"xv_"+t,62-Image.open(os.path.join(OUT,"xv_%s.png"%t)).width/2,MID+16-12)
    if t=="n":
        fs=F("Medium",28); cs=digits("sec",fs,GY,36); number("sec","timeSecond","sec",2); lay("n","sec",62-cs,MID+48-18)
    # дата «ЧТ 12»
    fd=F("SemiBold",26,False); col=(115,115,115) if dim else WH
    ww=math.ceil(max(fd.getlength(w+" ") for w in WEEK)/K)+1
    array("wk_"+t,[text_img(w+" ",fd,col,w=ww,h=34,align="right") for w in WEEK]); values("wk_"+t,"dateWeek","wk_"+t,range(7))
    cd=digits("day_"+t,fd,col,34); number("day_"+t,"dateDay","day_"+t,2,"left",False)
    x0=58-(ww+2*cd)/2; lay(t,"v_wk_"+t,x0,90-17); lay(t,"day_"+t,x0+ww,90-17)
    # кроки
    cst=digits("st_"+t,fd,(115,115,115) if dim else OR,34); number("st_"+t,"healthStepCount","st_"+t,5,"center",False); lay(t,"st_"+t,60,440-17)
names=[r.split('name="')[1].split('"')[0] for r in res if ' name="' in r]
assert len(names)==len(set(names)), [n for n in names if names.count(n)>1]
xml=['<?xml version="1.0" encoding="UTF-8"?>','<Watchface id="318470560" name="Лінійка">','    <Resources>']+["        "+r for r in res]+['    </Resources>',
     '    <Theme type="normal" name="Лінійка" bgColor="#0E0E10">']+["        "+l for l in theme["n"]]+['    </Theme>','    <Theme type="AOD" name="AOD" bgColor="#000000">']+["        "+l for l in theme["a"]]+['    </Theme>','</Watchface>']
open(os.path.join(HERE,"manifest.xml"),"w",encoding="utf-8").write("\n".join(xml)+"\n"); print("ok",len(res))

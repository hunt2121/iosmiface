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
    array(n,[text_img(str(i),f,col,w=cw,h=h) for i in range(10)]); return cw

MID=260; PXH=64; SX0=110      # центр шкали, пікселів на годину, лівий край смуги шкали
def strip(Hh,dim):
    im=Image.new("RGBA",((W-SX0)*K,H*K),(0,0,0,0)); d=ImageDraw.Draw(im); f=F("SemiBold",24)
    c=Hh+0.5                    # посередині кадру — H:30
    for h10 in range(int((c-5)*6),int((c+5)*6)+2):
        h=h10/6; y=MID+(h-c)*PXH
        if not -10<y<H+10: continue
        big=h10%6==0; lc=(110,110,110) if dim else ((255,255,255) if big else DT)
        d.line([((160 if big else 176)-SX0)*K,y*K,(194-SX0)*K,y*K],fill=lc,width=(3 if big else 1)*K)
        if big: d.text(((136-SX0)*K,y*K),"%02d"%((h10//6)%24),font=f,fill=(90,90,90) if dim else LG,anchor="mm")
    return down(im)
PY0,PH=MID-40,80               # область кадрів риски
def pointer(m,dim):
    im=Image.new("RGBA",(W*K,PH*K),(0,0,0,0)); d=ImageDraw.Draw(im); y=40+(m/60-0.5)*PXH; c=(120,120,120) if dim else OR
    d.line([18*K,y*K,196*K,y*K],fill=c,width=2*K); d.polygon([(200*K,(y-8)*K),(188*K,y*K),(200*K,(y+8)*K)],fill=c)
    return down(im)
WEEK=["НД","ПН","ВТ","СР","ЧТ","ПТ","СБ"]
for t,dim in (("n",False),("a",True)):
    if t=="n":
        array("strip_"+t,[strip(h,dim) for h in range(24)]); values("strip_"+t,"timeHour","strip_"+t,range(24)); lay(t,"v_strip_"+t,SX0,0)
        array("ptr_"+t,[pointer(m,dim) for m in range(60)]); values("ptr_"+t,"timeMinute","ptr_"+t,range(60)); lay(t,"v_ptr_"+t,0,PY0)
    else:
        # AOD — без руху: нерухомий відрізок шкали з рискою посередині й поточна година біля неї
        im=Image.new("RGBA",(W*K,120*K),(0,0,0,0)); d=ImageDraw.Draw(im)
        for i in range(-6,7):
            y=60+i*PXH/6; big=i%6==0
            d.line([((160 if big else 176))*K,y*K,194*K,y*K],fill=(80,80,80),width=(3 if big else 1)*K)
        d.line([18*K,60*K,196*K,60*K],fill=(130,130,130),width=2*K); d.polygon([(200*K,52*K),(188*K,60*K),(200*K,68*K)],fill=(130,130,130))
        image("ruler_a",down(im)); lay("a","ruler_a",0,MID-60)
        ch=digits("hr_a",F("SemiBold",24),(120,120,120),30); number("hr_a","timeHour","hr_a",2); lay("a","hr_a",136-ch,MID-22-15)
    # хвилини, «ХВ», секунди
    fm=F("Bold",72); cw=digits("min_"+t,fm,(170,170,170) if dim else WH,80); number("min_"+t,"timeMinute","min_"+t,2); lay(t,"min_"+t,62-cw,MID-44-40)
    image("xv_"+t,text_img("ХВ",F("Bold",18,False),(120,120,120) if dim else OR,h=24)); lay(t,"xv_"+t,62-Image.open(os.path.join(OUT,"xv_%s.png"%t)).width/2,MID+13-12)
    if t=="n":
        fs=F("Medium",28); cs=digits("sec",fs,GY,36); number("sec","timeSecond","sec",2); lay("n","sec",62-cs,MID+48-18)
    # дата «ЧТ 12»
    fd=F("SemiBold",26,False); col=(150,150,150) if dim else WH
    ww=math.ceil(max(fd.getlength(w+" ") for w in WEEK)/K)+1
    array("wk_"+t,[text_img(w+" ",fd,col,w=ww,h=34,align="right") for w in WEEK]); values("wk_"+t,"dateWeek","wk_"+t,range(7))
    cd=digits("day_"+t,fd,col,34); number("day_"+t,"dateDay","day_"+t,2,"left",False)
    x0=58-(ww+2*cd)/2; lay(t,"v_wk_"+t,x0,90-17); lay(t,"day_"+t,x0+ww,90-17)
    # кроки
    cst=digits("st_"+t,fd,(120,120,120) if dim else OR,34); number("st_"+t,"healthStepCount","st_"+t,5,"center",False); lay(t,"st_"+t,60,440-17)
xml=['<?xml version="1.0" encoding="UTF-8"?>','<Watchface id="318470560" name="Лінійка">','    <Resources>']+["        "+r for r in res]+['    </Resources>',
     '    <Theme type="normal" name="Лінійка" bgColor="#0E0E10">']+["        "+l for l in theme["n"]]+['    </Theme>','    <Theme type="AOD" name="AOD" bgColor="#000000">']+["        "+l for l in theme["a"]]+['    </Theme>','</Watchface>']
open(os.path.join(HERE,"manifest.xml"),"w",encoding="utf-8").write("\n".join(xml)+"\n"); print("ok",len(res))

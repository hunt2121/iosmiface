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
def strip(Hh,dim,part="all"):   # part: all / ticks (без підписів) / labels (підписи на підкладці кольору фону)
    im=Image.new("RGBA",((W-SX0)*K,H*K),(0,0,0,0)); d=ImageDraw.Draw(im); f=F("SemiBold",24)
    c=Hh+0.5                    # посередині кадру — H:30; риска ходить між H:00 і H+1:00
    for h10 in range(int((c-5)*6),int((c+5)*6)+2):
        h=h10/6; y=MID+(h-c)*PXH
        if not -10<y<H+10: continue
        big=h10%6==0; lc=(110,110,110) if dim else ((255,255,255) if big else DT)
        if part!="labels": d.line([((160 if big else 176)-SX0)*K,y*K,(194-SX0)*K,y*K],fill=lc,width=(3 if big else 1)*K)
        if big and part=="labels": d.rectangle([(115-SX0)*K,(y-12)*K,(156-SX0)*K,(y+12)*K],fill=(0,0,0))
        if big and part!="ticks": d.text(((136-SX0)*K,y*K),"%02d"%((h10//6)%24),font=f,fill=(90,90,90) if dim else LG,anchor="mm")
    return down(im)
PY0,PH=MID-40,80               # область кадрів риски
def pointer(m,dim):
    im=Image.new("RGBA",(W*K,PH*K),(0,0,0,0)); d=ImageDraw.Draw(im); y=40+(m/60-0.5)*PXH; c=(115,115,115) if dim else OR
    d.line([18*K,y*K,196*K,y*K],fill=c,width=2*K); d.polygon([(200*K,(y-8)*K),(188*K,y*K),(200*K,(y+8)*K)],fill=c)
    return down(im)
WEEK=["НД","ПН","ВТ","СР","ЧТ","ПТ","СБ"]
for t,dim in (("n",False),("a",True)):
    # Шкала — край великого диска (барабана) на годинній стрілці. Стрілка на браслеті рухається плавно (година
    # з урахуванням хвилин), тож шкала з підписами пливе під нерухомою рискою. Повний оберт за добу (15° на годину).
    # AOD — те саме, сірим (стрілка теж рухається лише раз на хвилину — анімації немає).
    DEG=15; RL=float(os.environ.get("DIAL_R","250"))   # радіус підписів
    CX=136+RL; PV=round(RL+16); S=2*PV            # картинка диска S×S, вісь посередині; центр — праворуч за екраном
    cB,cS,cL,cP=((80,80,80),(80,80,80),(115,115,115),(115,115,115)) if dim else ((255,255,255),DT,LG,OR)
    im=Image.new("RGBA",(S*K,S*K),(0,0,0,0)); d=ImageDraw.Draw(im); fl=F("SemiBold",24)
    def at(psi,r): return (PV+r*math.sin(math.radians(psi)))*K,(PV-r*math.cos(math.radians(psi)))*K
    for j10 in range(24*6):
        psi=270-DEG*j10/6; big=j10%6==0            # годинний кут: 270° — ліворуч (до риски)
        r0,r1=(CX-194),(CX-160 if big else CX-176)
        if dim: r1=CX-176; big=False                # AOD — як раніше: лише дрібні поділки (і на місці годинних теж)
        d.line([at(psi,r0),at(psi,r1)],fill=cB if big else cS,width=(3 if big else 1)*K)
    for j in (range(24) if not dim else []):       # в AOD підписів на диску немає — година стоїть навпроти риски
        psi=270-DEG*j; beta=270-psi                # підпис повернуто так, щоб біля риски він стояв рівно
        tp=Image.new("RGBA",(60*K,40*K),(0,0,0,0)); ImageDraw.Draw(tp).text((30*K,20*K),"%02d"%j,font=fl,fill=cL,anchor="mm")
        tp=tp.rotate(beta,resample=Image.BICUBIC,expand=True); x,y=at(psi,RL)
        im.alpha_composite(tp,(round(x-tp.width/2),round(y-tp.height/2)))
    image("dial_"+t,down(im))
    res.append('<DataItemPointer name="v_dial_%s" source="timeHour" ref="@dial_%s" param="1000" renderRule="alwaysShow" valueStart="0" valueRange="24" pivotX="%d" pivotY="%d" angleStart="0" angleRange="%d"/>'%(t,t,PV,PV,24*DEG))
    lay(t,"v_dial_"+t,round(CX)-PV,MID-PV)        # y від'ємний: диск трохи більший за екран (у форматі координати знакові)
    # нерухома риска — коротка, праворуч від підписів, вістрям до поділок
    im=Image.new("RGBA",(W*K,24*K),(0,0,0,0)); d=ImageDraw.Draw(im)
    d.line([156*K,12*K,196*K,12*K],fill=cP,width=2*K); d.polygon([(200*K,4*K),(188*K,12*K),(200*K,20*K)],fill=cP)
    image("ptr_"+t,down(im)); lay(t,"ptr_"+t,0,MID-12)
    if dim:   # AOD — як раніше: видно лише шматок шкали довкола риски (±60 px), краї ледь пом'якшено
        WIN,FADE=60,6; mk=Image.new("RGBA",(W-SX0,H),(0,0,0,255)); px=mk.load()
        for y in range(H):
            dy=abs(y+0.5-MID); a=0 if dy<=WIN-FADE else (255 if dy>=WIN else round(255*(dy-WIN+FADE)/FADE))
            for x in range(W-SX0): px[x,y]=(0,0,0,a)
        image("mask_a",mk); lay(t,"mask_a",SX0,0)
        ch=digits("hr_a",F("SemiBold",24),cL,30); number("hr_a","timeHour","hr_a",2); lay(t,"hr_a",136-ch,MID-15)   # година — завжди навпроти риски
    # хвилини, «ХВ», секунди
    fm=F("Bold",72); cw=digits("min_"+t,fm,(115,115,115) if dim else WH,80); number("min_"+t,"timeMinute","min_"+t,2); lay(t,"min_"+t,62-cw,MID-44-40+2)
    image("xv_"+t,text_img("ХВ",F("Bold",21,False),(115,115,115) if dim else OR,h=24)); lay(t,"xv_"+t,62-Image.open(os.path.join(OUT,"xv_%s.png"%t)).width/2,MID+15-12+3)
    if t=="n":
        fs=F("Medium",28); cs=digits("sec",fs,GY,36); number("sec","timeSecond","sec",2); lay("n","sec",62-cs,MID+48-18+10)   # від «ХВ» до секунд — як від хвилин до «ХВ» (24 px); блок хвилини–ХВ–секунди по центру екрана
    # дата «ЧТ 12»
    fd=F("SemiBold",26,False); col=(115,115,115) if dim else WH
    ww=math.ceil(max(fd.getlength(w+" ") for w in WEEK)/K)+1
    array("wk_"+t,[text_img(w+" ",fd,col,w=ww,h=34,align="right") for w in WEEK]); values("wk_"+t,"dateWeek","wk_"+t,range(7))
    cd=digits("day_"+t,fd,col,34); number("day_"+t,"dateDay","day_"+t,2,"left",False)
    x0=58-(ww+2*cd)/2; lay(t,"v_wk_"+t,x0,90-17); lay(t,"day_"+t,x0+ww,90-17)
    # кроки
    cst=digits("st_"+t,fd,(115,115,115) if dim else OR,34); number("st_"+t,"healthStepCount","st_"+t,5,"center",False); lay(t,"st_"+t,60,440-17-10)   # кроки від низу екрана — як дата від верху (80 px)
names=[r.split('name="')[1].split('"')[0] for r in res if ' name="' in r]
assert len(names)==len(set(names)), [n for n in names if names.count(n)>1]
xml=['<?xml version="1.0" encoding="UTF-8"?>','<Watchface id="318470560" name="Лінійка">','    <Resources>']+["        "+r for r in res]+['    </Resources>',
     '    <Theme type="normal" name="Лінійка" bgColor="#000000">']+["        "+l for l in theme["n"]]+['    </Theme>','    <Theme type="AOD" name="AOD" bgColor="#000000">']+["        "+l for l in theme["a"]]+['    </Theme>','</Watchface>']
open(os.path.join(HERE,"manifest.xml"),"w",encoding="utf-8").write("\n".join(xml)+"\n"); print("ok",len(res))

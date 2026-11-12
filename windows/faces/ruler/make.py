# «Лінійка» для Xiaomi Smart Band 10 (212×520): справа шкала годин, помаранчева риска — поточний момент.
# Браслет не дає «хвилину доби», тож шкала зсувається щогодини (24 кадри), а риска рухається за хвилинами (60 кадрів).
from PIL import Image, ImageDraw, ImageFont
import os, math, shutil, sys
HERE=os.path.dirname(os.path.abspath(__file__))
DTOP_=45   # дата — по центру екрана, верх за 45 px від краю; кроки — по центру, низ за 45 px від краю
LANGV=os.environ.get("LANGV","ua")      # ua / ru / en / en12 (англійська, 12 год з AM/PM)
DEST=os.environ.get("FACE_DEST") or os.path.join(os.path.dirname(HERE),"ruler" if LANGV=="ua" else "ruler-"+LANGV)
OUT=os.path.join(DEST,"files")
FACE_ID={"ua":"318470560","ru":"318470561","en":"318470562","en12":"318470563"}[LANGV]; FACE_NAME="VISUAL"   # назва однакова, ідентифікатор у кожної мови свій
H12=LANGV=="en12"; AMPM_DX=0
MINW={"ua":"ХВ","ru":"МИН","en":"MIN","en12":"MIN"}[LANGV]
DTOP=DTOP_; DCX=105.5; DLGAP=7; DAYDX=0; STX=105; STDY=35; BDY=1   # BDY — блок хвилини/ХВ/секунди посередині між датою й кроками   # верх дати; проміжок між рядками дати; поправка числа по осі
K=4; W,H=212,520; FD="/usr/share/fonts/opentype/inter/"
OR=tuple(int(os.environ.get("ACCENT","FF5F1F")[i:i+2],16) for i in (0,2,4)); WH=(255,255,255); GY=(150,150,155); LG=(170,170,175); DT=(90,90,95)
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
def number(n,src,arr,digits,align="left",lz=True,space=0,unit=None):
    arr="d_"+arr        # набори цифр — з префіксом d_, щоб назви не збігалися з числами
    res.append('<DataItemImageNumber name="%s" source="%s" ref="@%s" totalDigits="%d" decimalDigits="0" align="%s" leadingZero="%s" trailingZero="false" renderRule="alwaysShow" rotation="0" decimalOffsetX="0" space="%d"%s/>'%(n,src,arr,digits,align,"true" if lz else "false",space,' unitIcon="@%s"'%unit if unit else ""))
def soles_icon(col,gap,boxh,top):
    """значок кроків — дві підошви з каблуком; рівно 22 px заввишки (на піксель вище й нижче цифр),
    у картинці висотою як цифри, зліва відступ gap (браслет ставить значок одразу після останньої цифри)"""
    k=16; im=Image.new("RGBA",(19*k,22*k),(0,0,0,0)); d=ImageDraw.Draw(im)
    E=lambda cx,cy,rx,ry: d.ellipse([(cx-rx)*k,(cy-ry)*k,(cx+rx)*k,(cy+ry)*k],fill=col)
    for cx,t0 in ((5,7.6),(13.8,0.4)): E(cx,t0+4.6,3.4,4.6); E(cx,t0+12.1,2.6,1.9)
    c=im.crop(im.getbbox()); w=round(c.width*22/c.height)
    ic=c.convert("RGBa").resize((w,22),Image.LANCZOS).convert("RGBA")
    out=Image.new("RGBA",(gap+w,boxh),(0,0,0,0)); out.alpha_composite(ic,(gap,top)); return out
def values(n,src,arr,ps,rr="alwaysShow"):
    res.append('<DataItemImageValues name="v_%s" source="%s" ref="@%s" renderRule="%s" rotation="0">'%(n,src,arr,rr))
    for p in ps: res.append('    <Param value="%d"/>'%p)
    res.append('</DataItemImageValues>')
def rnd(v): return math.floor(v+0.5-1e-9)   # пів пікселя — ліворуч / вгору (не банківське округлення)
def lay(t,n,x,y): theme[t].append('<Layout ref="@%s" x="%d" y="%d"/>'%(n,rnd(x),rnd(y)))
def text_img(s,f,col,w=None,h=40,align="center"):
    b=f.getbbox("0ЧТ"); cc=(b[1]+b[3])/2; tw=f.getlength(s,features=["tnum"]); ww=(w*K) if w else math.ceil(tw)+2*K
    im=Image.new("RGBA",(int(ww),h*K),(0,0,0,0)); x={"center":(ww-tw)/2,"left":0,"right":ww-tw}[align]
    ImageDraw.Draw(im).text((x,h*K/2-cc),s,font=f,fill=col,features=["tnum"]); return down(im)
def digits(n,f,col,h):
    cw=math.ceil(max(f.getlength(str(i),features=["tnum"]) for i in range(10))/K)
    array("d_"+n,[text_img(str(i),f,col,w=cw,h=h) for i in range(10)]); return cw

MID=270; PXH=64; SX0=110      # центр шкали, пікселів на годину, лівий край смуги шкали
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
WEEK={"ua":["НД","ПН","ВТ","СР","ЧТ","ПТ","СБ"],"ru":["ВС","ПН","ВТ","СР","ЧТ","ПТ","СБ"],"en":["SUN","MON","TUE","WED","THU","FRI","SAT"],"en12":["SUN","MON","TUE","WED","THU","FRI","SAT"]}[LANGV]   # dateWeek: 0 — неділя
for t,dim in (("n",False),("a",True)):
    if not dim:
        # Шкала — край великого диска (барабана) на годинній стрілці. Стрілка на браслеті рухається плавно (година
        # з урахуванням хвилин), тож шкала з підписами пливе під нерухомою рискою. Повний оберт за добу (15° на годину).
        DEG=15; RL=float(os.environ.get("DIAL_R","250"))   # радіус підписів
        CX=136+RL; PV=round(RL+16); S=2*PV            # картинка диска S×S, вісь посередині; центр — праворуч за екраном
        cB,cS,cL=(255,255,255),DT,LG
        im=Image.new("RGBA",(S*K,S*K),(0,0,0,0)); d=ImageDraw.Draw(im); fl=F("SemiBold",24)
        def at(psi,r): return (PV+r*math.sin(math.radians(psi)))*K,(PV-r*math.cos(math.radians(psi)))*K
        for j10 in range(24*6):
            psi=270-DEG*j10/6; big=j10%6==0            # годинний кут: 270° — ліворуч (до риски)
            r0,r1=(CX-194),(CX-160 if big else CX-176)
            d.line([at(psi,r0),at(psi,r1)],fill=cB if big else cS,width=(3 if big else 1)*K)
        for j in range(24):
            psi=270-DEG*j; beta=270-psi                # підпис повернуто так, щоб біля риски він стояв рівно
            tp=Image.new("RGBA",(60*K,40*K),(0,0,0,0)); ImageDraw.Draw(tp).text((30*K,20*K),("%d"%((j+11)%12+1)) if H12 else "%02d"%j,font=fl,fill=cL,anchor="mm")
            tp=tp.rotate(beta,resample=Image.BICUBIC,expand=True); x,y=at(psi,RL)
            im.alpha_composite(tp,(round(x-tp.width/2),round(y-tp.height/2)))
        image("dial_"+t,down(im))
        res.append('<DataItemPointer name="v_dial_%s" source="timeHour" ref="@dial_%s" param="1000" renderRule="alwaysShow" valueStart="0" valueRange="24" pivotX="%d" pivotY="%d" angleStart="0" angleRange="%d"/>'%(t,t,PV,PV,24*DEG))
        lay(t,"v_dial_"+t,round(CX)-PV,MID-PV)        # y від'ємний: диск трохи більший за екран (у форматі координати знакові)
    else:
        # AOD — шкала нерухома, просто декорація: шматок ±60 px лише з дрібними поділками; година навпроти риски
        HA=90; im=Image.new("RGBA",(W*K,2*HA*K),(0,0,0,0)); d=ImageDraw.Draw(im)
        cx=136+float(os.environ.get("DIAL_R","250"))      # центр того самого диска, що на звичайному екрані
        for i in range(-7,8):                            # дрібні поділки по дузі диска (2,5° = 10 хв), симетрично
            if i==0: continue                            # під рискою поділки немає
            a=math.radians(270+2.5*i); r0,r1=cx-194,cx-176
            p0=(cx+r0*math.sin(a),HA-r0*math.cos(a)); p1=(cx+r1*math.sin(a),HA-r1*math.cos(a))
            al=min(1.0,(8-abs(i))/3)                    # три крайні поділки з кожного боку плавно гаснуть
            d.line([(p0[0]*K,p0[1]*K),(p1[0]*K,p1[1]*K)],fill=(80,80,80,round(255*al)),width=K)
        image("ruler_a",down(im)); lay(t,"ruler_a",0,MID-HA)
        ch=digits("hr_a",F("SemiBold",24),(115,115,115),30)
        if H12: number("hr_a","timeHour12H","hr_a",2,"center",False); lay(t,"hr_a",136,MID-15)   # 12 год: без нуля попереду, по центру
        else: number("hr_a","timeHour","hr_a",2); lay(t,"hr_a",136-ch,MID-15)
    cP=(115,115,115) if dim else OR
    # нерухома риска — коротка, праворуч від підписів, вістрям до поділок
    im=Image.new("RGBA",(W*K,24*K),(0,0,0,0)); d=ImageDraw.Draw(im)
    d.line([156*K,12*K,196*K,12*K],fill=cP,width=2*K); d.polygon([(200*K,4*K),(188*K,12*K),(200*K,20*K)],fill=cP)
    image("ptr_"+t,down(im)); lay(t,"ptr_"+t,0,MID-12)
    # хвилини, «ХВ», секунди, дата й кроки — по одній вертикальній осі x=61 (за видимими пікселями; пів пікселя — ліворуч)
    fm=F("Bold",72); cw=digits("min_"+t,fm,(115,115,115) if dim else WH,80); number("min_"+t,"timeMinute","min_"+t,2); lay(t,"min_"+t,62-cw,MID-44-40+2+BDY)
    image("xv_"+t,text_img(MINW,F("Bold",21,False),(115,115,115) if dim else OR,h=24)); lay(t,"xv_"+t,62-Image.open(os.path.join(OUT,"xv_%s.png"%t)).width/2-(0.5 if LANGV=="ru" else 0),MID+15-12+3+BDY)
    if t=="n":
        fs=F("Medium",28)
        if H12:   # 12 год: замість секунд — AM/PM того самого розміру й на тому самому місці (лише на звичайному екрані)
            AW=60
            def vis_center(x):   # картинка AW×36, видима середина напису — рівно в пікселі 30 (на осі x=61)
                im=text_img(x,fs,GY,w=AW,h=36); a=im.getchannel("A").point(lambda v:255 if v>40 else 0); b=a.getbbox()
                dx=30-(b[0]+b[2]-1)/2; dx=math.floor(dx) if dx!=int(dx) else int(dx)   # пів пікселя — ліворуч
                out=Image.new("RGBA",im.size,(0,0,0,0)); out.alpha_composite(im,(int(dx),0)) if dx>=0 else out.alpha_composite(im.crop((-int(dx),0,im.width,im.height)),(0,0)); return out
            array("ampm",[vis_center(x) for x in ("AM","PM")]); values("ampm","miscIsPM","ampm",[0,1]); lay("n","v_ampm",61-30,MID+48-18+10+BDY)
        else: cs=digits("sec",fs,GY,36); number("sec","timeSecond","sec",2); lay("n","sec",62-cs-1,MID+48-18+10+BDY)   # від «ХВ» до секунд — як від хвилин до «ХВ» (24 px); блок хвилини–ХВ–секунди по центру екрана
    # Дата у два рядки: день тижня (менший) зверху, число під ним; кожен рядок рівно по осі x=61.
    # Верх дня тижня — 80 px від верху екрана (як кроки від низу).
    fd=F("SemiBold",26,False); col=(115,115,115) if dim else WH
    fw=F("SemiBold",20,False)
    def vc(img,cx):   # зсунути напис у картинці так, щоб видима середина була в пікселі cx (пів пікселя — ліворуч)
        a=img.getchannel("A").point(lambda v:255 if v>40 else 0); b=a.getbbox(); dx=cx-(b[0]+b[2]-1)/2; dx=math.floor(dx)
        out=Image.new("RGBA",img.size,(0,0,0,0)); out.alpha_composite(img.crop((max(0,-dx),0,img.width,img.height)),(max(0,dx),0)); return out
    WWK=70; wk=[vc(text_img(w,fw,col,w=WWK,h=26),WWK/2-0.5) for w in WEEK]
    array("wk_"+t,wk); values("wk_"+t,"dateWeek","wk_"+t,range(7))
    wb=wk[4].getchannel("A").point(lambda v:255 if v>40 else 0).getbbox()      # видимі рядки назви (верх/низ однакові для всіх)
    lay(t,"v_wk_"+t,DCX+0.5-WWK/2,DTOP-wb[1])
    cd=digits("day_"+t,fd,col,34); number("day_"+t,"dateDay","day_"+t,2,"center",False)
    db=Image.open(os.path.join(OUT,"d_day_%s"%t,"1.png")).getchannel("A").point(lambda v:255 if v>40 else 0).getbbox()
    lay(t,"day_"+t,DCX+DAYDX,DTOP+(wb[3]-wb[1])+DLGAP-db[1])
    if t=="n":   # стиль 2 (як раніше): дата на осі x=61, верх за 80 px від краю
        ST2={"v_wk_n":(26,80-wb[1]),"day_n":(61,80+(wb[3]-wb[1])+DLGAP-db[1])}
    # Значки стану над хвилинами (30 px): блискавка — заряд нижче 20 %, блютуз — немає зв'язку.
    # Блютуз — шаром поверх, під ним чорна підкладка (на 1 px більша за обидва значки), тож при обох показується він.
    if t=="n" or dim:
        cI=(115,115,115) if dim else OR; k=8
        def crop_(im): return im.crop(im.getchannel("A").point(lambda v:255 if v>40 else 0).getbbox())
        def bt_icon(h=30,lw=2.6):
            w=round(h*0.64); im=Image.new("RGBA",(w*k,h*k),(0,0,0,0)); d=ImageDraw.Draw(im); L=round(lw*k)
            tt,bb,cx=1.4*k,(h-1.4)*k,w/2*k; q=(bb-tt)/4; a=w*0.36*k
            d.line([(cx-a,tt+q),(cx+a*0.92,tt+3*q),(cx,bb),(cx,tt),(cx+a*0.92,tt+q),(cx-a,tt+3*q)],fill=cI,width=L,joint="curve")
            return crop_(im.convert("RGBa").resize((w,h),Image.LANCZOS).convert("RGBA"))
        def bolt_icon(h=30):
            w=round(h*0.62); im=Image.new("RGBA",(w*k,h*k),(0,0,0,0)); d=ImageDraw.Draw(im); s_=k*h/30
            P=[(11.5,0),(0.8,17),(8.4,17),(6.2,30),(17.8,11.6),(10,11.6),(13.6,0)]
            d.polygon([(x*s_+(w*k-18.6*s_)/2,y*s_) for x,y in P],fill=cI)
            return crop_(im.convert("RGBa").resize((w,h),Image.LANCZOS).convert("RGBA"))
        bi,li=bt_icon(),bolt_icon()
        IW=max(bi.width,li.width)+2; IW+=1-IW%2; IH=max(bi.height,li.height)+2   # рамка: непарна ширина — центр рівно в пікселі
        def framed(ic,plate):
            fr=Image.new("RGBA",(IW,IH),(0,0,0,255) if plate else (0,0,0,0))
            fr.alpha_composite(ic,((IW-ic.width)//2,(IH-ic.height)//2)); return fr
        empty=Image.new("RGBA",(IW,IH),(0,0,0,0))
        array("bat_"+t,[framed(li,False),empty]); values("bat_"+t,"systemStatusBattery","bat_"+t,[0,20])
        array("bt_"+t,[framed(bi,True),empty]); values("bt_"+t,"systemStatusBluetooth","bt_"+t,[0,1])
        def icon_pos(cy): return 61-(IW-1)//2, int(cy-(IH-1)/2)        # пів пікселя — вгору
        x2,y2=icon_pos(144.5)        # стиль 2: посередині між датою (низ 87) і хвилинами (верх 202)
        lay(t,"v_bat_"+t,x2,y2); lay(t,"v_bt_"+t,x2,y2)
        if t=="n":
            x1,y1=icon_pos(162)      # стиль 1: посередині між датою (низ 122) і хвилинами (верх 202)
            ST2["v_bat_n"]=(x1,y1); ST2["v_bt_n"]=(x1,y1)
    # кроки
    cst=digits("st_"+t,fd,(115,115,115) if dim else OR,34)
    SI=os.environ.get("STEPS_ICON","right")
    if SI=="right":
        image("stic_"+t,soles_icon((115,115,115) if dim else OR,5,34,6))   # підошви праворуч, 5 px від цифр
        number("st_"+t,"healthStepCount","st_"+t,5,"center",False,unit="stic_"+t); lay(t,"st_"+t,STX,440-17-10+STDY)
        if t=="n": ST2["st_n"]=(60,440-17-10)   # стиль 2: кроки на осі x=61, низ за 80 px від краю   # кроки з підошвами — разом по центру осі x=61
    else:
        ic=soles_icon((115,115,115) if dim else OR,0,22,0); image("stic_"+t,ic); GAPV=7
        # блок «значок + число» від низу екрана — 80 px, як дата від верху; значок над або під числом
        ybot=439                                         # нижній видимий рядок блоку
        if SI=="top": ny=ybot-19; iy=ny-GAPV-22
        else: iy=ybot-21; ny=iy-GAPV-20
        number("st_"+t,"healthStepCount","st_"+t,5,"center",False); lay(t,"st_"+t,61,ny-7)
        lay(t,"stic_"+t,math.floor(61.5-ic.width/2),iy)   # кроки від низу екрана — як дата від верху (80 px)
names=[r.split('name="')[1].split('"')[0] for r in res if ' name="' in r]
assert len(names)==len(set(names)), [n for n in names if names.count(n)>1]
# Два стилі: 1 (головний) — theme["n2"]: дата й кроки на лівій осі x=61, 80 px від країв;
# 2 — theme["n"]: по центру екрана, 45 px від країв. У кожного стилю свій AOD.
import re as _re
theme["n2"]=[]
for l in theme["n"]:
    r=_re.search(r'ref="@([^"]+)"',l).group(1)
    theme["n2"].append('<Layout ref="@%s" x="%d" y="%d"/>'%(r,round(ST2[r][0]),round(ST2[r][1])) if r in ST2 else l)
# AOD для кожного стилю: по центру — як намальовано (theme["a"]), ліва вісь — з тими самими позиціями, що й theme["n2"]
theme["a_c"]=list(theme["a"])
theme["a"]=[('<Layout ref="@%s" x="%d" y="%d"/>'%(r,round(ST2[r[:-1]+"n"][0]),round(ST2[r[:-1]+"n"][1])) if (r[:-1]+"n") in ST2 and r.endswith("_a") else l)
            for l in theme["a"] for r in [_re.search(r'ref="@([^"]+)"',l).group(1)]]
S1,S2={"ua":("Стиль 1","Стиль 2"),"ru":("Стиль 1","Стиль 2")}.get(LANGV,("Style 1","Style 2"))
T=lambda typ,name,key: ['    <Theme type="%s" name="%s" bgColor="#000000">'%(typ,name)]+["        "+l for l in theme[key]]+['    </Theme>']
xml=['<?xml version="1.0" encoding="UTF-8"?>','<Watchface id="%s" name="%s">'%(FACE_ID,FACE_NAME),'    <Resources>']+["        "+r for r in res]+['    </Resources>']\
    +T("normal",S1,"n2")+T("AOD",S1,"a")+T("normal",S2,"n")+T("AOD",S2,"a_c")+['</Watchface>']
os.makedirs(DEST,exist_ok=True); open(os.path.join(DEST,"manifest.xml"),"w",encoding="utf-8").write("\n".join(xml)+"\n"); print("ok",len(res))

# ── Перефарбування (вибір кольору на браслеті): стандартний, фламінго, лайм, білий.
# Генеруємо циферблат ще раз з кожним кольором акценту, і для кожної картинки/набору, що змінився,
# додаємо варіант з тим самим іменем і colorGroup (як в офіційних). AOD сірий — без варіантів.
ACCENTS=["FF5F1F","FC8EAC","B8F02A","F2F2F2"]
if not os.environ.get("NO_VARIANTS"):
    import subprocess,tempfile,filecmp
    man=open(os.path.join(DEST,"manifest.xml"),encoding="utf-8").read()
    extra=[]
    for ci,hx in enumerate(ACCENTS[1:],1):
        tmp=tempfile.mkdtemp()
        subprocess.run([sys.executable,os.path.abspath(__file__)],env=dict(os.environ,ACCENT=hx,FACE_DEST=tmp,NO_VARIANTS="1"),check=True,stdout=subprocess.DEVNULL)
        def changed(src): return not filecmp.cmp(os.path.join(OUT,src),os.path.join(tmp,"files",src),shallow=False)
        def copy(src):
            dst=os.path.join("c%d"%ci,src); os.makedirs(os.path.dirname(os.path.join(OUT,dst)),exist_ok=True)
            shutil.copy(os.path.join(tmp,"files",src),os.path.join(OUT,dst)); return dst
        for m in _re.finditer(r'<Image name="([^"]+)" src="([^"]+)"([^>]*)/>',man):
            if changed(m.group(2)): extra.append('<Image name="%s" src="%s"%s colorGroup="#%s"/>'%(m.group(1),copy(m.group(2)),m.group(3),hx))
        for m in _re.finditer(r'<ImageArray name="([^"]+)"([^>]*)>(.*?)</ImageArray>',man,_re.S):
            srcs=_re.findall(r'src="([^"]+)"',m.group(3))
            if any(changed(x) for x in srcs):
                extra.append('<ImageArray name="%s"%s colorGroup="#%s">'%(m.group(1),m.group(2),hx)+"".join('<Image src="%s"/>'%copy(x) for x in srcs)+'</ImageArray>')
        shutil.rmtree(tmp)
    CG=",".join("#"+h for h in ACCENTS)
    man=man.replace('<Watchface id="%s" name="%s">'%(FACE_ID,FACE_NAME),'<Watchface id="%s" name="%s" colorGroupTable="%s">'%(FACE_ID,FACE_NAME,CG))
    man=man.replace("    </Resources>","".join("        "+e+"\n" for e in extra)+"    </Resources>")
    man=_re.sub(r'(<Theme type="\w+" name="[^"]+" bgColor="#000000")>',r'\1 colorGroup="%s">'%CG,man)
    open(os.path.join(DEST,"manifest.xml"),"w",encoding="utf-8").write(man); print("variants",len(extra))

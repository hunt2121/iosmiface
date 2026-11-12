from PIL import Image, ImageDraw, ImageFont
import math
K=4; CYN=(0,240,255); PNK=(255,0,90); BLK=(0,0,0)
S=44   # розмір значка
def down(im): return im.convert("RGBa").resize((im.width//K,im.height//K),Image.LANCZOS).convert("RGBA")
def icon(parts, cols=None):
    im=Image.new("RGBA",(S*K,S*K),(0,0,0,0)); d=ImageDraw.Draw(im)
    for col,dx in (cols or ((PNK,-1.3),(CYN,1.3))):
        for p in parts: p(d,col,dx)
    return down(im)
W2=2
def ln(d,pts,col,w=W2): d.line([(x*K,y*K) for x,y in pts],fill=col,width=int(w*K),joint="curve")
def sun(cx,cy,r=7,rays=True):
    def f(d,col,dx):
        x=cx+dx; d.ellipse([(x-r)*K,(cy-r)*K,(x+r)*K,(cy+r)*K],fill=BLK,outline=col,width=W2*K)
        if rays:
            for a in range(0,360,45):
                t=math.radians(a); ln(d,[(x+(r+3)*math.cos(t),cy+(r+3)*math.sin(t)),(x+(r+6)*math.cos(t),cy+(r+6)*math.sin(t))],col)
    return f
def cloud(cx,cy,w=1.0):
    def f(d,col,dx):
        x=cx+dx
        d.rounded_rectangle([(x-13*w)*K,(cy-1)*K,(x+13*w)*K,(cy+9)*K],radius=5*K,fill=BLK,outline=col,width=W2*K)
        d.ellipse([(x-8*w)*K,(cy-9)*K,(x+5*w)*K,(cy+4)*K],fill=BLK,outline=col,width=W2*K)
        d.ellipse([(x+0*w)*K,(cy-5)*K,(x+10*w)*K,(cy+5)*K],fill=BLK,outline=col,width=W2*K)
        d.rectangle([(x-11*w)*K,(cy+1)*K,(x+11*w)*K,(cy+7)*K],fill=BLK)
    return f
def drops(xs,y,slant=2,l=5):
    def f(d,col,dx):
        for x in xs: ln(d,[(x+dx+slant,y),(x+dx,y+l)],col)
    return f
def flakes(pts,r=3.4):
    def f(d,col,dx):
        for x,y in pts:
            for a in (0,60,120): t=math.radians(a); ln(d,[(x+dx-r*math.cos(t),y-r*math.sin(t)),(x+dx+r*math.cos(t),y+r*math.sin(t))],col,1.4)
    return f
def dots(pts,r=1.5):
    def f(d,col,dx):
        for x,y in pts: d.ellipse([(x+dx-r)*K,(y-r)*K,(x+dx+r)*K,(y+r)*K],fill=col)
    return f
def bolt(x,y):
    return lambda d,col,dx: ln(d,[(x+dx+3,y),(x+dx-1,y+6),(x+dx+3,y+6),(x+dx-1,y+12)],col)
def windl(y0,n=3):
    def f(d,col,dx):
        for i in range(n):
            y=y0+i*7; L=(26,32,20)[i]; x0=8+dx
            ln(d,[(x0,y),(x0+L,y)],col); d.arc([(x0+L-4)*K,(y-8)*K,(x0+L+4)*K,(y)*K],-90,90,fill=col,width=W2*K) if i==0 else None
    return f
def tornado():
    def f(d,col,dx):
        for i,(w,y) in enumerate(((28,9),(22,15),(16,21),(11,27),(7,33))):
            ln(d,[(22+dx-w/2+i,y),(22+dx+w/2+i,y)],col)
    return f
def fog():
    def f(d,col,dx):
        for i,(a,b) in enumerate(((8,36),(12,32),(8,36),(14,30))): ln(d,[(a+dx,12+i*6),(b+dx,12+i*6)],col)
    return f
def qmark():
    def f(d,col,dx):
        d.text(((22+dx)*K,(24)*K),"?",font=ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-Bold.otf",13*K),fill=col,anchor="mm")
    return f
C=(22,20)
ICONS=[
 ("Ясно",[sun(22,22,8)]),
 ("Мінлива хмарність",[sun(27,15,6),cloud(19,25)]),
 ("Хмарно",[cloud(22,22)]),
 ("Злива",[cloud(22,17),drops([13,20,27,34],30,3,6)]),
 ("Гроза",[cloud(22,17),bolt(20,28)]),
 ("Гроза з градом",[cloud(22,17),bolt(17,28),dots([(28,32),(32,38)])]),
 ("Дощ зі снігом",[cloud(22,17),drops([15,27],30),flakes([(21,35)])]),
 ("Слабкий дощ",[cloud(22,17),drops([22],30)]),
 ("Помірний дощ",[cloud(22,17),drops([17,27],30)]),
 ("Сильний дощ",[cloud(22,17),drops([14,22,30],30)]),
 ("Шторм",[cloud(22,15),drops([12,18,32],28,3,7),bolt(23,27)]),
 ("Снігопад короткий",[cloud(22,17),flakes([(22,34)])]),
 ("Слабкий сніг",[cloud(22,17),flakes([(22,34)],3)]),
 ("Помірний сніг",[cloud(22,17),flakes([(16,33),(28,33)])]),
 ("Сильний сніг",[cloud(22,17),flakes([(14,32),(22,37),(30,32)])]),
 ("Хуртовина",[cloud(22,15),flakes([(13,31),(22,36),(31,31)]),drops([18,26],27,4,4)]),
 ("Смерч",[tornado()]),
 ("Пилова буря",[windl(12),dots([(10,34),(18,36),(26,34),(34,36)],1.3)]),
 ("Крижаний дощ",[cloud(22,17),drops([15,29],30),dots([(22,35)])]),
 ("Сніг із дощем",[cloud(22,17),flakes([(15,33),(29,33)]),drops([22],30)]),
 ("Мокрий сніг",[cloud(22,17),flakes([(22,34)]),dots([(14,33),(30,33)],1.2)]),
 ("Туман",[fog()]),
 ("Невідомо",[cloud(22,21),qmark()]),
 ("Мряка",[cloud(22,17),dots([(15,31),(22,35),(29,31)],1.1)]),
]
if __name__=="__main__":
    lf=ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-Medium.otf",20)
    Z=3; cw=S*Z+110; out=Image.new("RGB",(6*cw,4*(S*Z+60)),(0,0,0)); dd=ImageDraw.Draw(out)
    for k,(name,parts) in enumerate(ICONS):
        r,c=divmod(k,6); im=icon(parts).resize((S*Z,S*Z),Image.NEAREST)
        x=c*cw+55; y=r*(S*Z+60)+10; out.paste(im,(x,y),im); dd.text((x+S*Z//2,y+S*Z+22),"%d. %s"%(k,name),font=lf,fill=(200,200,205),anchor="mm")
    out.save("/tmp/claude-0/-home-claude/db6005de-023b-57f2-8d4f-7e2b4fccd61e/scratchpad/wicons.png")

def centered_icon(parts, cols=None):
    """значок, видима частина якого — точно посередині полотна S×S (усі значки центровані однаково)"""
    im=icon(parts, cols); bb=im.getchannel("A").point(lambda v:255 if v>30 else 0).getbbox()
    out=Image.new("RGBA",(S,S),(0,0,0,0)); cx=(bb[0]+bb[2])/2; cy=(bb[1]+bb[3])/2
    out.alpha_composite(im,(round(S/2-cx),round(S/2-cy))); return out

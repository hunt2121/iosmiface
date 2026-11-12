from PIL import Image, ImageDraw, ImageFont, ImageChops
import numpy as np
import os
# Digital-7 (Style-7) — лише для особистого користування; файл шрифту в репозиторій не кладемо, шлях — через D7_FONT
FONT=os.environ.get('D7_FONT','/tmp/claude-0/-home-claude/db6005de-023b-57f2-8d4f-7e2b4fccd61e/scratchpad/d7/digital-7.ttf')
def glyph(ch,size):
    f=ImageFont.truetype(FONT,size); L=Image.new('L',(size*2,size*2),0); ImageDraw.Draw(L).text((size//2,size//2),ch,font=f,fill=255)
    return L
def cut(L,ch,size,remove):
    # маски за геометрією гліфа '8' того ж розміру
    bb=glyph('8',size).getbbox(); x0,y0,x1,y1=bb; W=x1-x0; H=y1-y0; t=W*0.24; ym=(y0+y1)/2
    m=Image.new('L',L.size,0); d=ImageDraw.Draw(m)
    P={'a':[(x0-2,y0-2),(x1+2,y0-2),(x1-t,y0+t*0.95),(x0+t,y0+t*0.95)],
       'd':[(x0-2,y1+2),(x1+2,y1+2),(x1-t,y1-t*0.95),(x0+t,y1-t*0.95)],
       'f':[(x0-2,y0+t*0.5),(x0+t*1.05,y0+t*1.05),(x0+t*1.05,ym-t*0.3),(x0-2,ym-t*0.3)],
       'e':[(x0-2,ym+t*0.3),(x0+t*1.05,ym+t*0.3),(x0+t*1.05,y1-t*1.05),(x0-2,y1-t*0.5)],
       'g':[(x0+t*0.6,ym-t*0.55),(x1-t*0.6,ym-t*0.55),(x1-t*0.6,ym+t*0.55),(x0+t*0.6,ym+t*0.55)]}
    for k in remove: d.polygon(P[k],fill=255)
    R=np.array(ImageChops.subtract(L,m))
    import scipy.ndimage as nd
    lab,n=nd.label(R>60); sz=nd.sum(np.ones_like(R),lab,range(1,n+1))
    big=max(sz) if n else 0
    for j,z in enumerate(sz):
        if z<0.25*big: R[nd.binary_dilation(lab==j+1,iterations=2)]=0
    return Image.fromarray(R)
MAP={'П':('0','d'),'Н':('H',''),'В':('B',''),'Т':('T',''),'С':('C',''),'Р':('P',''),'Ч':('4',''),'Б':('6',''),'Д':('8','af')}
def square_ring(size):
    L=glyph('8',size); x0,y0,x1,y1=L.getbbox(); ym=(y0+y1)/2; t=(x1-x0)*0.24
    return L.crop((x0,y0,x1,int(ym+t*0.55)))
def square_pct(size):
    """Квадратний «%» у метриці «8»: дві квадратні петлі з сегментів шрифту і коса риска товщиною сегмента."""
    G=glyph('8',size); x0,y0,x1,y1=G.getbbox(); H=y1-y0; t=(x1-x0)*0.16
    R=square_ring(size); W8=H; rs=H*0.4; x1=x0+H
    r=R.resize((int(rs),int(rs*R.height/R.width)),Image.LANCZOS)
    K=4; big=Image.new('L',(size*2*K,size*2*K),0); d=ImageDraw.Draw(big)
    ox,oy=x0*K,y0*K; Wp=W8*K; Hh=H*K; tt=t*K*1.25
    xb=ox+Wp*0.06; xt=ox+Wp*0.94-tt
    d.polygon([(xb,oy+Hh),(xb+tt*1.15,oy+Hh),(xt+tt,oy),(xt-tt*0.15,oy)],fill=255)
    big=big.resize((size*2,size*2),Image.LANCZOS)
    o=Image.new('L',big.size,0); o.paste(r,(int(x0),int(y0))); big=ImageChops.lighter(big,o)
    o=Image.new('L',big.size,0); o.paste(r,(int(x1-r.width),int(y1-r.height))); big=ImageChops.lighter(big,o)
    return big
def ring_pct(size):
    """%: два кільця з «%» шрифту + сегмент «1», повернутий на 45°."""
    import scipy.ndimage as nd
    R=cyr('°',size); R=R.crop(R.getbbox())
    one=glyph('1',size); A=np.array(one); lab,n=nd.label(A>40,structure=np.ones((3,3)))
    sl=nd.find_objects(lab); tops=sorted(range(n),key=lambda j:sl[j][0].start)
    j=tops[0]+1; st=Image.fromarray(np.where(lab==j,A,0).astype(np.uint8)); st=st.crop(st.getbbox()); st=st.resize((st.width,int(st.height*2.3)),Image.LANCZOS)
    st=st.rotate(-45,resample=Image.BICUBIC,expand=True); st=st.crop(st.getbbox())
    Wd=max(st.width,int(R.width*2.4)); Hd=max(st.height,int(R.height*2.4))
    o=Image.new('L',(Wd,Hd),0)
    o.paste(st,((Wd-st.width)//2,(Hd-st.height)//2))
    o=ImageChops.lighter(o,_shift(R,0,o.size))
    rr=Image.new('L',o.size,0); rr.paste(R,(Wd-R.width,Hd-R.height)); o=ImageChops.lighter(o,rr)
    o.info['ring']=R.height
    return o
def cyr(ch,size):
    if ch=='%': return square_pct(size)
    if ch=='°':
        # градус = верхнє кільце зі знака «%» самого шрифту
        import scipy.ndimage as nd
        L=glyph('%',size); R=np.array(L); lab,n=nd.label(R>40,structure=np.ones((3,3)))
        sz=nd.sum(np.ones_like(R),lab,range(1,n+1)); com=nd.center_of_mass(np.ones_like(R),lab,range(1,n+1))
        bb=L.getbbox(); ym=(bb[1]+bb[3])/2; slash=int(np.argmax(sz))+1
        keep=np.zeros_like(R,bool)
        for j in range(1,n+1):
            if j!=slash and com[j-1][0]<ym: keep|=nd.binary_dilation(lab==j,iterations=1)
        return Image.fromarray(np.where(keep,R,0).astype(np.uint8))
    src,rm=MAP.get(ch,(ch,''))
    L=glyph(src,size)
    return cut(L,src,size,rm) if rm else L
def text(s,size,gap=None):
    # рендер із рідними відступами шрифту; кирилиця підставляється гліфами-донорами
    f=ImageFont.truetype(FONT,size)
    W=int(sum(f.getlength(MAP.get(c,(c,''))[0]) for c in s))+size*2
    out=Image.new('L',(W,size*2),0); x=size//2
    for c in s:
        src=MAP.get(c,(c,''))[0]
        L=cyr(c,size)
        out=ImageChops.lighter(out,_shift(L,x-size//2,out.size))
        x+=f.getlength(src)+(gap or 0)
    return out
def _shift(L,dx,size):
    o=Image.new('L',size,0); o.paste(L,(int(dx),0)); return o
def text_mono(s,size):
    """Моноширинні клітинки як у справжньому LCD: (символи, підкладка «8» під кожним)."""
    f=ImageFont.truetype(FONT,size)
    b8=glyph('8',size).getbbox(); cw=f.getlength('8'); cc=f.getlength(':')
    W=int(sum(cc if c==':' else cw for c in s))+size*2
    fg=Image.new('L',(W,size*2),0); gh=Image.new('L',(W,size*2),0); x=size//2
    for c in s:
        if c==' ': x+=cw; continue
        if c==':':
            L=glyph(':',size); fg=ImageChops.lighter(fg,_shift(L,x-size//2,fg.size)); gh=ImageChops.lighter(gh,_shift(L,x-size//2,fg.size)); x+=cc; continue
        G=glyph('8',size); gh=ImageChops.lighter(gh,_shift(G,x-size//2,fg.size))
        if c=='_': x+=cw; continue
        L=cyr(c,size); bb=L.getbbox(); dx=0
        if bb:
            if c=='1': dx=b8[2]-bb[2]
            elif c=='-': dx=(b8[0]+b8[2])/2-(bb[0]+bb[2])/2
            else: dx=b8[0]-bb[0]
        fg=ImageChops.lighter(fg,_shift(L,x-size//2+dx,fg.size)); x+=cw
    return fg,gh

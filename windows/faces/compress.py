# Стискання картинок циферблата (спільне для генераторів): RLE як у компіляторі + вибір indexed8 там, де вигідніше.
import numpy as np
def compress_len(src, E, minRun=5):
    # точний порт Rle.Compress — повертає довжину
    n=len(src); out=0; pos=0
    if n==0: return 0
    def eq(a,b):
        return src[a:a+E]==src[b:b+E] if a+E<=n and b+E<=n else (src[a:a+E]+b'\xff'*0==src[b:b+E] and False)
    while pos<n:
        if n<E: break
        run=0; off=0
        while True:
            if not eq(pos+off,pos): break
            run+=1
            if run==0x7F: break
            off+=E
            if off+pos>=n: break
        if run==0: break
        if run<minRun:
            r14=0;cnt=0;eqc=0;prev=pos
            while True:
                cur=pos+r14; eqc+=1
                if eq(cur,prev):
                    if eqc>minRun: break
                else:
                    cnt+=eqc; prev=cur; eqc=0
                    if cnt>=0x7F: cnt=0x7F; break
                r14+=E
                if r14+pos>=n:
                    cnt+=eqc
                    if cnt>=0x7F: cnt=0x7F
                    break
            out+=1+min(cnt*E,n-pos); pos+=cnt*E
        else:
            out+=1+min(E,n-pos); pos+=run*E
    return out+8
def enc(fmt,rgba):   # rgba: numpy HxWx4 uint8
    a=rgba.reshape(-1,4)
    if fmt=="RGBA32": return a[:,[2,1,0,3]].tobytes(),4
    if fmt=="RGB565A8":
        r=(a[:,0].astype(int)*31//255); g=(a[:,1].astype(int)*63//255); b=(a[:,2].astype(int)*31//255)
        v=(r<<11|g<<5|b).astype('<u2'); o=np.zeros((len(a),3),np.uint8); o[:,0]=v&0xFF; o[:,1]=v>>8; o[:,2]=a[:,3]; return o.tobytes(),3
    if fmt=="indexed8":
        u,inv=np.unique(a.view('<u4').ravel(),return_inverse=True)
        assert len(u)<=256
        pal=np.zeros((256,4),np.uint8); c=u.view(np.uint8).reshape(-1,4); pal[:len(u)]=c[:,[2,1,0,3]]
        return pal.tobytes()+inv.astype(np.uint8).tobytes(),1
import sys,os,re,shutil,numpy as np
from PIL import Image
def quant(a):
    q=Image.fromarray(a,"RGBA").quantize(256,method=Image.Quantize.FASTOCTREE).convert("RGBA"); return np.array(q)
def run(d):
    m=open(os.path.join(d,"manifest.xml"),encoding="utf-8").read(); stats=[0,0]
    def frames_for(tag_txt): return re.findall(r'src="([^"]+)"',tag_txt)
    def decide(srcs):
        out=[]; before=after=0
        for s in srcs:
            a=np.array(Image.open(os.path.join(d,"files",s)).convert("RGBA")); r32=compress_len(*enc("RGBA32",a))
            u=len(np.unique(a.reshape(-1,4).view('<u4'))); q=a if u<=256 else quant(a)
            qi=compress_len(enc("indexed8",q)[0],1); out.append((s,q)); before+=r32; after+=qi
        return out,before,after
    def sub(mm):
        txt=mm.group(0); srcs=frames_for(txt)
        if 'format="RGBA32"' not in txt or not srcs: return txt
        out,b,a=decide(srcs); stats[0]+=b
        if a<b:
            for s,q in out: Image.fromarray(q,"RGBA").save(os.path.join(d,"files",s))
            stats[1]+=a; return txt.replace('format="RGBA32"','format="indexed8"')
        stats[1]+=b; return txt
    m=re.sub(r'<ImageArray [^>]*>.*?</ImageArray>|<Image name="[^"]+"[^>]*/>',sub,m,flags=re.S)
    open(os.path.join(d,"manifest.xml"),"w",encoding="utf-8").write(m)
    return stats
if __name__=="__main__":
    b,a=run(sys.argv[1]); print("before",b,"after",a)

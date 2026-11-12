"""Generate a deterministic binary floor map, not a prescribed robot trace."""
from pathlib import Path
import hashlib,json
import numpy as np
from reportlab.pdfgen import canvas
from reportlab.lib.units import mm
import fitz

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'maps/coded_grid_v2'
def make_cells():
    for seed in range(20261112,20262112):
        rng=np.random.default_rng(seed);a=np.zeros((28,40),dtype=np.uint8);failed=False
        for r in range(28):
            for c in range(40):
                choices=[v for v in (0,1) if not(c>=5 and np.all(a[r,c-5:c]==v)) and not(r>=5 and np.all(a[r-5:r,c]==v))]
                if not choices:failed=True;break
                a[r,c]=rng.choice(choices)
            if failed:break
        if failed:continue
        seen=set();unique=True
        for r in range(24):
            for c in range(36):
                patch=a[r:r+5,c:c+5]
                for turn in range(4):
                    key=np.rot90(patch,turn).tobytes()
                    if key in seen:unique=False;break
                    seen.add(key)
                if not unique:break
            if not unique:break
        if unique:return a,seed
    raise RuntimeError('Could not find unique ideal 5x5 patches')

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    a,seed=make_cells()
    data=dict(version='coded-grid-v2',paper_mm=[420,297],cell_mm=10,grid_origin_paper_mm=[10,8.5],start_axle_paper_mm=[110,48.5],cells=a.tolist(),seed=seed,unique_patch_shape=[5,5],unique_patch_rotations_checked=[0,90,180,270],single_five_sensor_sample_unique=False,localization_status='experimental; requires calibration, geometry and known initial pose')
    raw=json.dumps(data,sort_keys=True,separators=(',',':')).encode()
    data['pattern_sha256']=hashlib.sha256(raw).hexdigest()
    (OUT/'map.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
    c=canvas.Canvas(str(OUT/'CodedGrid_A3_100percent.pdf'),pagesize=(420*mm,297*mm))
    c.setTitle('Coded black-white map V2 - A3 actual size')
    for r in range(28):
        for col in range(40):
            if a[r,col]:c.rect((10+col*10)*mm,(297-8.5-(r+1)*10)*mm,10*mm,10*mm,stroke=0,fill=1)
    c.showPage();c.save()
    source=fitz.open(OUT/'CodedGrid_A3_100percent.pdf');tiles=fitz.open()
    for n,(x0,y0,x1,y1) in enumerate([(0,0,220,158.5),(200,0,420,158.5),(0,138.5,220,297),(200,138.5,420,297)],1):
        p=tiles.new_page(width=297*mm,height=210*mm)
        dest=fitz.Rect(10*mm,30*mm,(10+x1-x0)*mm,(30+y1-y0)*mm)
        p.show_pdf_page(dest,source,0,clip=fitz.Rect(x0*mm,y0*mm,x1*mm,y1*mm))
        p.draw_rect(dest,color=(.7,.7,.7),width=.3)
        p.insert_text((10*mm,10*mm),f'TILE {n}/4 '+['TOP LEFT','TOP RIGHT','BOTTOM LEFT','BOTTOM RIGHT'][n-1],fontsize=10)
        p.insert_text((10*mm,18*mm),'ACTUAL SIZE / 100%. Align common pattern in the 20 mm overlap. Tape back only.',fontsize=8)
    tiles.save(OUT/'CodedGrid_A4_4tiles_100percent.pdf')
    c=canvas.Canvas(str(OUT/'Calibration_A4_100percent.pdf'),pagesize=(210*mm,297*mm))
    c.setTitle('Calibration targets - same printer and paper as coded grid')
    c.setFont('Helvetica',12);c.drawString(15*mm,275*mm,'WHITE / BLACK sensor calibration')
    c.setFont('Helvetica',9);c.drawString(15*mm,266*mm,'Print 100%. Use same paper, ink, height and lighting as the map.')
    c.setLineWidth(.4);c.rect(15*mm,140*mm,80*mm,80*mm,stroke=1,fill=0)
    c.rect(115*mm,140*mm,80*mm,80*mm,stroke=0,fill=1)
    c.drawString(15*mm,230*mm,'WHITE: centre inside frame');c.drawString(115*mm,230*mm,'BLACK: centre inside patch')
    c.line(30*mm,100*mm,130*mm,100*mm)
    for x in range(30,131,10):c.line(x*mm,98*mm,x*mm,102*mm)
    c.drawString(30*mm,90*mm,'Measure this scale: 100 mm')
    c.drawString(15*mm,70*mm,'Keep all five probes inside one target; normal ground clearance.')
    c.drawString(15*mm,62*mm,'Do not use lifted-wheel geometry for ground-operation calibration.')
    c.showPage();c.save()
    source[0].get_pixmap(matrix=fitz.Matrix(.8,.8),alpha=False).save(OUT/'print_preview.png')
    p=source[0];p.draw_circle(fitz.Point(110*mm,48.5*mm),5*mm,color=(.15,.65,.2),width=2)
    p.draw_line(fitz.Point(110*mm,48.5*mm),fitz.Point(130*mm,48.5*mm),color=(.15,.65,.2),width=2)
    p.get_pixmap(matrix=fitz.Matrix(.8,.8),alpha=False).save(OUT/'start_reference_NOT_for_print.png')
    print(json.dumps(dict(seed=seed,pattern_sha256=data['pattern_sha256'],black_cells=int(a.sum()),unique_oriented_5x5_patches=24*36*4)))

if __name__=='__main__':main()

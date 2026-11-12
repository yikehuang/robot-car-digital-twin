from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.units import mm
import fitz,json

out=Path(__file__).resolve().parents[1]/'maps/landmark_map_v1'
out.mkdir(parents=True,exist_ok=True)
pdf=out/'Square_Landmarks_A3_100percent.pdf'
c=canvas.Canvas(str(pdf),pagesize=(420*mm,297*mm))
c.setTitle('Square landmark map V1 - actual size')
def text(x,y,s,size=7):
    c.setFont('Helvetica',size);c.drawString(x*mm,(297-y)*mm,s)
def line(x,y,x2,y2):c.line(x*mm,(297-y)*mm,x2*mm,(297-y2)*mm)
markers=[]
for mid,n,(x,y),direction in [('M1',1,(210,48.5),'E'),('M2',2,(310,148.5),'S'),('M3',3,(210,248.5),'W'),('M4',4,(110,148.5),'N')]:
    span=n*8+(n-1)*8
    for i in range(n):
        off=-span/2+i*16
        bx,by,w,h=(x+off,y-40,8,80) if direction in 'EW' else (x-40,y+off,80,8)
        c.rect(bx*mm,(297-by-h)*mm,w*mm,h*mm,fill=1,stroke=0)
    markers.append(dict(id=mid,bars=n,paper_center_mm=[x,y],world_center_mm=[x-110,48.5-y],direction=direction))
for i,s in enumerate(['SQUARE LANDMARKS V1','A3: 420 x 297 mm','ACTUAL SIZE / 100%','Route: 4 x 200 mm']):text(12,20+i*7,s,8)
for i,s in enumerate(['M1: 1 bar / top','M2: 2 bars / right','M3: 3 bars / bottom','M4: 4 bars / left','Black width: 8 mm','White gap: 8 mm','Transverse width: 80 mm','No continuous guide line','Prototype: calibrate first']):text(12,70+i*7,s)
for i,s in enumerate(['SETUP: paper x,y mm','Start axle: (110,48.5)','Face east / right','Next corners:','(310,48.5)','(310,248.5)','(110,248.5)','Return to start','Known start required.','Sensor offset matters.']):text(12,160+i*6,s)
for i,s in enumerate(['CHECK PRINT SCALE','Do not fit / shrink.','Measure ruler below.']):text(363,24+i*7,s)
c.setLineWidth(.5);line(392,80,392,180)
for y in range(80,181,10):line(389,y,395,y)
text(363,192,'Ruler length: 100 mm')
text(363,240,'Not full 2D localization.')
text(363,247,'Validate raw sensor data.')
c.showPage();c.save()
src=fitz.open(pdf);tiles=fitz.open()
for n,(x0,y0,x1,y1) in enumerate([(0,0,220,158.5),(200,0,420,158.5),(0,138.5,220,297),(200,138.5,420,297)],1):
    p=tiles.new_page(width=297*mm,height=210*mm)
    clip=fitz.Rect(x0*mm,y0*mm,x1*mm,y1*mm)
    dest=fitz.Rect(10*mm,30*mm,(10+x1-x0)*mm,(30+y1-y0)*mm)
    p.show_pdf_page(dest,src,0,clip=clip)
    p.draw_rect(dest,color=(.7,.7,.7),width=.3)
    p.insert_text((10*mm,10*mm),f'TILE {n}/4 - '+['TOP LEFT','TOP RIGHT','BOTTOM LEFT','BOTTOM RIGHT'][n-1],fontsize=10)
    p.insert_text((10*mm,17*mm),'Print ACTUAL SIZE / 100%. Align shared marks in the 20 mm overlap.',fontsize=8)
    p.insert_text((10*mm,24*mm),'Remove page margins. Keep joins flat; put tape on the reverse side.',fontsize=8)
tiles.save(out/'Square_Landmarks_A4_4tiles_100percent.pdf')
route=[(110,48.5),(310,48.5),(310,248.5),(110,248.5),(110,48.5)]
src[0].get_pixmap(matrix=fitz.Matrix(.8,.8),alpha=False).save(out/'print_map_preview.png')
for a,b in zip(route,route[1:]):src[0].draw_line(fitz.Point(a[0]*mm,a[1]*mm),fitz.Point(b[0]*mm,b[1]*mm),color=(.3,.55,.85),width=1,dashes='[5 4]')
src[0].get_pixmap(matrix=fitz.Matrix(.8,.8),alpha=False).save(out/'setup_preview_NOT_for_print.png')
check=fitz.open(out/'Square_Landmarks_A4_4tiles_100percent.pdf')
check[0].get_pixmap(matrix=fitz.Matrix(.8,.8),alpha=False).save(out/'tile_preview.png')
assert len(check)==4 and abs(src[0].rect.width/mm-420)<.01
(out/'landmarks.json').write_text(json.dumps(dict(paper_mm=[420,297],route_paper_top_left_mm=route,markers=markers,bar_width_mm=8,white_gap_mm=8,prototype=True),indent=2),encoding='utf-8')
(out/'README_打印说明.md').write_text('''# 黑白地标地图 V1（实验原型）

A3 横向，420×297 mm，按实际大小/100%打印，关闭适应纸张。没有 A3 打印机时使用四页 A4 横向拼接版，按图案对齐20 mm重叠区，裁掉外页边，胶带贴背面，保持平整。打印后用尺量100 mm刻度确认比例。

正方形边长200 mm。纸面左上角为原点，x向右、y向下。起点轮轴中点(110,48.5)，朝右，依次经过(310,48.5)、(310,248.5)、(110,248.5)，回起点。PNG蓝线只作摆放参考，不在打印地图内。

四边中段分别为1、2、3、4条黑条。每条沿行进方向8 mm，白间隔8 mm，横向80 mm。先用中间底部反射探头验证白-黑-白变化，再扩展到五探头。

需要穿过完整标记组后，结合已知起点、行进方向、编码器距离和预期区域判断标记身份。单次黑或白读数不对应唯一坐标；条数编码本身也不提供方向。第一轮只记录读数与事件，不强制重置坐标。

当前 V3 固件还没有地图识别功能，需添加底部反射采样、标记识别和位置更新。建议先以本地100 Hz采样起步，并按实际速度验证是否充分；现有约50 ms的13列遥测没有反射读数。原个人实验高度为15 mm，运行时要核对实际高度并重新验证黑白阈值与噪声。

需测量探头相对车轴中点的偏移：探头越过标记不等于车轴已到标记位置。单次横条观测主要约束沿行进方向的位置，不能自动获得完整(x,y,朝向)。纸张、墨粉、光照、接缝和漏条均可能造成误差。

用于位置修正的同一标记不能同时当作完全独立的精度真值，仍需尺量或固定俯拍验证。

参考：Ben-Ari & Mondada, Elements of Robotics, Chapter 8 Localization, https://doi.org/10.1007/978-3-319-62533-1_8
''',encoding='utf-8')
print(json.dumps({'folder':str(out),'A3_pages':1,'A4_pages':4}))

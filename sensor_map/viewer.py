"""Live map observations. Run from repository root: python -m sensor_map.viewer."""
from pathlib import Path
import argparse, csv, hashlib, json, math, queue, time
from datetime import datetime
import tkinter as tk
from tkinter import messagebox
import numpy as np
from .core import Calibration, SensorLocalizer
from .network import RobotConnection

ROOT=Path(__file__).resolve().parents[1]

class Viewer:
    def __init__(self,args):
        self.root=tk.Tk();self.root.title('Robot sensor map / 真实传感器地图 — PROVISIONAL')
        self.root.geometry(f'{min(1200,self.root.winfo_screenwidth()-80)}x{min(870,self.root.winfo_screenheight()-100)}+20+20');self.args=args
        map_bytes=Path(args.map).read_bytes();geo_bytes=Path(args.geometry).read_bytes()
        self.map_data=json.loads(map_bytes);self.geometry=json.loads(geo_bytes)
        self.cal=Calibration();self.localizer=SensorLocalizer(self.map_data,self.geometry,self.cal)
        self.latest=None;self.capture=None;self.samples=[];self.last_capture_stamp=None
        self.previous=None;self.last_seq=None;self.gaps=0;self.track=[]
        self.folder=ROOT/'run-logs'/('sensor-map-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        self.connection=RobotConnection(args.host,args.key_file,self.folder)
        self.connection.start()
        # The receiver creates the folder. Metadata is written by UI once it exists.
        self.metadata=dict(map_sha256=hashlib.sha256(map_bytes).hexdigest(),geometry_sha256=hashlib.sha256(geo_bytes).hexdigest(),geometry=self.geometry,calibration=None,position_source='reflectance-map likelihood + encoder propagation; not external ground truth',start_pose_world_mm_rad=[0,0,0],start_placement_confirmed=False)
        self.log=None;self.status=tk.StringVar(value='Connecting / 正在连接')
        self.raw=tk.StringVar(value='Waiting for real GRID1 observations');self.pose=tk.StringVar(value='No position: calibrate and initialize / 尚无定位')
        self.cal_status=tk.StringVar(value='Calibration required / 需要黑白校准')
        tk.Label(self.root,textvariable=self.status,anchor='w').pack(fill='x')
        tk.Label(self.root,textvariable=self.raw,anchor='w',justify='left',wraplength=1000,font=('Consolas',10)).pack(fill='x')
        tk.Label(self.root,textvariable=self.pose,anchor='w',justify='left',wraplength=1000,font=('Consolas',10)).pack(fill='x')
        tk.Label(self.root,text='Approximate geometry: span 60 mm; forward offset 30 mm. Cell IDs are inferred. / 几何近似，格子编号由定位推断。',wraplength=1000,fg='#a05000').pack(fill='x')
        bar=tk.Frame(self.root);bar.pack(fill='x')
        tk.Button(bar,text='Capture WHITE / 采白底',command=lambda:self.begin_cal('white')).pack(side='left')
        tk.Button(bar,text='Capture BLACK / 采黑底',command=lambda:self.begin_cal('black')).pack(side='left')
        tk.Label(bar,textvariable=self.cal_status).pack(side='left',padx=8)
        self.placed=tk.BooleanVar(value=False)
        tk.Checkbutton(self.root,text='I placed AXLE CENTRE at the green start, facing right / 已将轮轴中点放在绿色起点，车头向右',variable=self.placed).pack(anchor='w')
        bar=tk.Frame(self.root);bar.pack(fill='x')
        tk.Button(bar,text='Initialize at START / 起点初始化',command=self.initialize).pack(side='left')
        self.start_button=tk.Button(bar,text='START physical robot / 启动实机',command=self.start,state='disabled');self.start_button.pack(side='left',padx=10)
        tk.Button(bar,text='STOP / 停车 (Space / Esc)',command=self.stop,bg='#e88').pack(side='left')
        tk.Label(self.root,text='Green: sensor-fused estimate; gaps = no accepted match / 绿色为融合估计，缺口表示未匹配').pack(anchor='w')
        self.canvas=tk.Canvas(self.root,bg='#ddd',width=1100,height=590);self.canvas.pack(fill='both',expand=True)
        self.canvas.bind('<Configure>',lambda e:self.draw_map())
        self.root.bind('<space>',lambda e:self.stop());self.root.bind('<Escape>',lambda e:self.stop())
        self.root.protocol('WM_DELETE_WINDOW',self.close)
        self.root.after(50,self.poll)

    def metadata_save(self):
        if self.folder.exists():(self.folder/'metadata.json').write_text(json.dumps(self.metadata,indent=2),encoding='utf-8')

    def stationary_fresh(self):
        o=self.latest
        return o is not None and time.monotonic()-self.connection.last_frame<.6 and o.encoder_ok and o.sensor_ok and o.state!=1 and o.left_pwm==0 and o.right_pwm==0

    def begin_cal(self,colour):
        if not self.stationary_fresh():
            messagebox.showinfo('Calibration','Need fresh stationary data with zero PWM. / 需要新鲜静止数据。');return
        self.capture=colour;self.samples=[];self.last_capture_stamp=None
        self.cal_origin=(self.latest.left,self.latest.right);self.placed.set(False);self.localizer.initialized=False
        self.cal_status.set(f'Capturing {colour}: 0/60 unique timestamps')

    def calibrate(self,o):
        if not self.capture:return
        if not self.stationary_fresh() or abs(o.left-self.cal_origin[0])>2 or abs(o.right-self.cal_origin[1])>2:
            self.capture=None;self.cal_status.set('Capture rejected: robot moved / 小车移动，采集取消');return
        if not o.new_stamp or o.sensor_stamp==self.last_capture_stamp:return
        self.last_capture_stamp=o.sensor_stamp;self.samples.append(o.values)
        self.cal_status.set(f'Capturing {self.capture}: {len(self.samples)}/60')
        if len(self.samples)>=60:
            a=np.asarray(self.samples,dtype=float);value=np.median(a,axis=0)
            noise=np.std(a,axis=0);setattr(self.cal,self.capture,value)
            self.metadata[self.capture+'_capture']=dict(samples=len(a),median=value.tolist(),std=noise.tolist(),source_timestamp_last=o.sensor_stamp)
            self.capture=None
            if self.cal.ready:
                contrast=np.abs(self.cal.black-self.cal.white)
                white_noise=np.asarray(self.metadata.get('white_capture',{}).get('std',[0]*5))
                black_noise=np.asarray(self.metadata.get('black_capture',{}).get('std',[0]*5))
                if np.any(contrast<6*np.maximum(white_noise,black_noise)):
                    self.cal.black=None;self.cal_status.set('Noise too large: recalibrate / 噪声过大，需重测')
                else:self.cal_status.set('White/black calibration ready / 黑白校准完成')
            else:self.cal_status.set('Need both targets with sufficient contrast / 需完成两种底色且有足够差异')
            self.metadata['calibration']=self.cal.as_dict();self.metadata_save()

    def initialize(self):
        if not self.placed.get() or not self.cal.ready or not self.stationary_fresh():
            messagebox.showinfo('Initialize','Calibrate, place axle centre at START facing right, then tick confirmation. / 先校准，再按起点示意摆放并勾选。');return
        self.localizer.reset();self.previous=None;self.track=[];self.canvas.delete('trace')
        self.metadata['start_placement_confirmed']=True;self.metadata_save()

    def start(self):
        if self.can_start():self.connection.request('START')
    def stop(self):self.connection.request('STOP')
    def can_start(self):
        return self.connection.ready and self.stationary_fresh() and self.latest.state==0 and self.cal.ready and self.localizer.initialized and self.placed.get() and self.capture is None

    def paper_xy(self,x,y):
        return self.ox+x*self.scale,self.oy+y*self.scale
    def world_xy(self,x,y):
        sx,sy=self.map_data['start_axle_paper_mm'];return self.paper_xy(sx+x,sy-y)
    def draw_map(self):
        self.canvas.delete('all');w,h=self.map_data['paper_mm']
        self.scale=max(.1,min((self.canvas.winfo_width()-20)/w,(self.canvas.winfo_height()-20)/h));self.ox=10;self.oy=10
        self.canvas.create_rectangle(*self.paper_xy(0,0),*self.paper_xy(w,h),fill='white',outline='#999')
        x0,y0=self.map_data['grid_origin_paper_mm'];cell=self.map_data['cell_mm']
        for r,row in enumerate(self.map_data['cells']):
            for c,black in enumerate(row):
                if black:self.canvas.create_rectangle(*self.paper_xy(x0+c*cell,y0+r*cell),*self.paper_xy(x0+(c+1)*cell,y0+(r+1)*cell),fill='#222',outline='')
        sx,sy=self.paper_xy(*self.map_data['start_axle_paper_mm'])
        self.canvas.create_oval(sx-6,sy-6,sx+6,sy+6,outline='#00b840',width=3)
        self.canvas.create_line(sx,sy,sx+25,sy,fill='#00b840',width=3,arrow='last')
        for a,b in self.track:self.canvas.create_line(*self.world_xy(*a),*self.world_xy(*b),fill='#00df65',width=3,tags='trace')

    def poll(self):
        if self.folder.exists() and self.log is None:
            self.metadata_save();self.log=(self.folder/'estimates.jsonl').open('w',encoding='utf-8')
        count=0
        while count<500:
            try:kind,value=self.connection.events.get_nowait()
            except queue.Empty:break
            count+=1
            if kind=='status':self.status.set(value);continue
            o=value;self.latest=o
            if self.last_seq is not None and o.sequence>self.last_seq+1:self.gaps+=o.sequence-self.last_seq-1
            self.last_seq=o.sequence;self.calibrate(o);result=self.localizer.update(o)
            result.update(sequence=o.sequence,sensor_stamp=o.sensor_stamp)
            if self.log:self.log.write(json.dumps(result,allow_nan=False)+'\n')
            colours='uncalibrated'
            if self.cal.ready and o.sensor_ok:colours=' '.join('B' if x>.65 else 'W' if x<.35 else '?' for x in self.cal.normalized(o.values))
            self.raw.set(f'DN1..5 {o.values} | {colours} | fresh stamp={o.new_stamp} | PWM {o.left_pwm},{o.right_pwm} | stage {o.stage} | gaps {self.gaps}')
            self.pose.set(result['status']+' | inferred cells: '+','.join(x or 'outside' for x in result['inferred_cells']))
            if result['measurement_accepted']:
                point=(result['x_mm'],result['y_mm'])
                speed='pending' if result['speed_mm_s'] is None else f"{result['speed_mm_s']:.1f} mm/s"
                turn='pending' if result['turn_deg_s'] is None else f"{result['turn_deg_s']:.1f} deg/s"
                self.pose.set(f"{result['status']} | x={point[0]:.1f}, y={point[1]:.1f} mm, heading={math.degrees(result['theta_rad']):.1f} deg | v={speed}, turn={turn}")
                if self.previous and o.time_ms-self.previous[0]<200:
                    a=self.previous[1];self.track.append((a,point))
                    self.canvas.create_line(*self.world_xy(*a),*self.world_xy(*point),fill='#00df65',width=3,tags='trace')
                self.previous=(o.time_ms,point)
                self.canvas.delete('pose')
                for (forward,left),cell_id in zip(self.localizer.offsets,result['inferred_cells']):
                    th=result['theta_rad'];x=point[0]+math.cos(th)*forward-math.sin(th)*left;y=point[1]+math.sin(th)*forward+math.cos(th)*left
                    px,py=self.world_xy(x,y);self.canvas.create_oval(px-3,py-3,px+3,py+3,fill='#ff9c00',outline='white',tags='pose')
            else:self.previous=None;self.canvas.delete('pose')
        if self.log:self.log.flush()
        if time.monotonic()-self.connection.last_frame>.6:
            self.pose.set('STALE / 数据中断 — no current position');self.previous=None;self.canvas.delete('pose')
        self.start_button.config(state='normal' if self.can_start() else 'disabled')
        self.root.after(50,self.poll)

    def close(self):
        self.connection.stop();self.connection.join(timeout=3)
        if self.log:self.log.close()
        self.root.destroy()

def main():
    try:
        import ctypes
        ctypes.windll.user32.SetProcessDPIAware()
    except (AttributeError,OSError):pass
    p=argparse.ArgumentParser();p.add_argument('--host',default='lpath-com7.local');p.add_argument('--key-file',default=str(ROOT/'robot-programs/DigitalTwin_LPath/robot-control.key'))
    p.add_argument('--map',default=str(ROOT/'maps/coded_grid_v2/map.json'));p.add_argument('--geometry',default=str(ROOT/'sensor_map/geometry.example.json'))
    app=Viewer(p.parse_args());app.root.mainloop()
if __name__=='__main__':main()

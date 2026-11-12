from __future__ import annotations
from dataclasses import dataclass
import math
import numpy as np

GRID_HEADER='protocol,sequence,time_ms,encoder_ok,left_count,right_count,sensor_ok,sensor_timestamp_us,new_sensor_stamp,dn1,dn2,dn3,dn4,dn5,trial,stage,state,left_pwm,right_pwm,sensor_read_us'

@dataclass(frozen=True)
class Observation:
    sequence:int;time_ms:int;encoder_ok:bool;left:int;right:int
    sensor_ok:bool;sensor_stamp:int;new_stamp:bool;values:tuple
    trial:int;stage:int;state:int;left_pwm:int;right_pwm:int;read_us:int

    @classmethod
    def parse(cls,line):
        a=line.strip().split(',')
        if len(a)!=20 or a[0]!='GRID1':raise ValueError('Not a GRID1 frame')
        ints={i:int(a[i]) for i in list(range(1,9))+list(range(14,20))}
        if any(ints[i] not in (0,1) for i in (3,6,8)):raise ValueError('Invalid flags')
        if not 0<=ints[16]<=3 or not 0<=ints[15]<=8:raise ValueError('Invalid controller state')
        if any(not 0<=ints[i]<=0xffffffff for i in (1,2,7)):raise ValueError('Invalid clock/sequence')
        if any(not 0<=ints[i]<=0xffffffff for i in (14,19)):raise ValueError('Invalid trial/read duration')
        if any(not -(2**31)<=ints[i]<2**31 for i in (4,5)):raise ValueError('Invalid encoder count')
        if any(abs(ints[i])>200 for i in (17,18)):raise ValueError('Invalid PWM')
        values=tuple(int(x) for x in a[9:14]) if ints[6] else (None,)*5
        if ints[6] and any(not 0<=v<=65535 for v in values):raise ValueError('Invalid sensor value')
        if not ints[6] and (ints[8] or a[9:14]!=['NA']*5):raise ValueError('Failed reading must be absent')
        return cls(ints[1],ints[2],bool(ints[3]),ints[4],ints[5],bool(ints[6]),ints[7],bool(ints[8]),values,ints[14],ints[15],ints[16],ints[17],ints[18],ints[19])

class Calibration:
    def __init__(self,white=None,black=None):
        self.white=None if white is None else np.asarray(white,dtype=float)
        self.black=None if black is None else np.asarray(black,dtype=float)
    @property
    def ready(self):
        return self.white is not None and self.black is not None and self.white.shape==(5,) and self.black.shape==(5,) and np.all(np.isfinite(self.white)) and np.all(np.isfinite(self.black)) and np.all(np.abs(self.black-self.white)>=50)
    def normalized(self,values):
        if not self.ready:raise ValueError('White/black calibration required')
        return np.clip((np.asarray(values)-self.white)/(self.black-self.white),-.25,1.25)
    def as_dict(self):
        return dict(white=None if self.white is None else self.white.tolist(),black=None if self.black is None else self.black.tolist())

class GridMap:
    def __init__(self,data):
        self.data=data;self.cells=np.asarray(data['cells'],dtype=float)
        self.cell=float(data['cell_mm']);self.x0,self.y0=data['grid_origin_paper_mm']
        self.start=np.asarray(data['start_axle_paper_mm'],dtype=float)
    def expected(self,poses,offsets,blur_mm=1.0):
        # x,y,theta use a start-based, +y-up world frame. Offsets: forward,left.
        poses=np.atleast_2d(poses);offsets=np.asarray(offsets,dtype=float)
        co=np.cos(poses[:,2,None]);si=np.sin(poses[:,2,None])
        px=poses[:,0,None]+co*offsets[None,:,0]-si*offsets[None,:,1]+self.start[0]
        py=self.start[1]-(poses[:,1,None]+si*offsets[None,:,0]+co*offsets[None,:,1])
        total=np.zeros_like(px);valid=np.ones_like(px,dtype=bool)
        for dx,dy in ((-blur_mm,-blur_mm),(-blur_mm,blur_mm),(blur_mm,-blur_mm),(blur_mm,blur_mm)):
            ix=np.floor((px+dx-self.x0)/self.cell).astype(int)
            iy=np.floor((py+dy-self.y0)/self.cell).astype(int)
            inside=(ix>=0)&(iy>=0)&(ix<self.cells.shape[1])&(iy<self.cells.shape[0])
            valid&=inside
            total+=self.cells[np.clip(iy,0,self.cells.shape[0]-1),np.clip(ix,0,self.cells.shape[1]-1)]
        return total/4,valid
    def cell_ids(self,pose,offsets):
        p=np.asarray(pose);o=np.asarray(offsets);co,si=math.cos(p[2]),math.sin(p[2])
        px=p[0]+co*o[:,0]-si*o[:,1]+self.start[0]
        py=self.start[1]-(p[1]+si*o[:,0]+co*o[:,1])
        ix=np.floor((px-self.x0)/self.cell).astype(int);iy=np.floor((py-self.y0)/self.cell).astype(int)
        return [f'R{r+1:02d}C{c+1:02d}' if 0<=r<self.cells.shape[0] and 0<=c<self.cells.shape[1] else None for r,c in zip(iy,ix)]

def signed_delta(new,old):return ((new-old+2**31)%2**32)-2**31
def wrapped(a):return np.arctan2(np.sin(a),np.cos(a))

class SensorLocalizer:
    def __init__(self,map_data,geometry,calibration=None,particles=2500,seed=42):
        self.map=GridMap(map_data);self.geometry=geometry;self.cal=calibration or Calibration()
        self.offsets=np.asarray(geometry['sensor_offsets_forward_left_mm'],dtype=float)
        if self.offsets.shape!=(5,2):raise ValueError('Need five measured/configured sensor offsets')
        self.rng=np.random.default_rng(seed);self.n=particles
        self.mm_count=2*math.pi*geometry['wheel_radius_mm']/geometry['counts_per_revolution']
        self.sep=geometry['wheel_separation_mm'];self.initialized=False;self.last=None
        self.odom=np.zeros(3);self.poses=np.zeros((particles,3));self.weights=np.full(particles,1/particles)
        self.last_sensor_stamp=None;self.last_update=None;self.history=[]
    def reset(self,pose=(0,0,0)):
        self.poses=np.asarray(pose)+self.rng.normal(size=(self.n,3))*np.array([5,5,math.radians(6)])
        self.weights.fill(1/self.n);self.odom=np.asarray(pose,dtype=float).copy()
        self.initialized=True;self.last=None;self.last_sensor_stamp=None;self.last_update=None;self.history=[]
    def summary(self):
        mu=np.sum(self.poses[:,:2]*self.weights[:,None],axis=0)
        angle=math.atan2(np.sum(np.sin(self.poses[:,2])*self.weights),np.sum(np.cos(self.poses[:,2])*self.weights))
        spread=np.sqrt(np.sum((self.poses[:,:2]-mu)**2*self.weights[:,None],axis=0))
        angular=math.sqrt(np.sum(wrapped(self.poses[:,2]-angle)**2*self.weights))
        return np.r_[mu,angle],spread,angular
    def update(self,obs):
        result=dict(time_ms=obs.time_ms,status='INITIALIZE_REQUIRED',measurement_accepted=False,x_mm=None,y_mm=None,theta_rad=None,speed_mm_s=None,turn_deg_s=None,inferred_cells=[],geometry_provisional=not self.geometry.get('confirmed',False))
        if not self.initialized:return result
        if self.last is not None and obs.time_ms<self.last.time_ms and self.last.time_ms-obs.time_ms<0xf0000000:
            self.initialized=False;return result
        if not obs.encoder_ok:
            result['status']='ENCODER_READ_FAILED';return result
        dt=0
        if self.last is not None:
            dt=((obs.time_ms-self.last.time_ms)&0xffffffff)/1000
            dl=signed_delta(obs.left,self.last.left)*self.mm_count;dr=signed_delta(obs.right,self.last.right)*self.mm_count
            if dt<=0 or dt>1 or max(abs(dl),abs(dr))>400:
                self.initialized=False;result['status']='TIME_OR_ENCODER_GAP';return result
            ds=(dl+dr)/2;dh=(dr-dl)/self.sep
            mid=self.odom[2]+dh/2
            self.odom+=np.array([ds*math.cos(mid),ds*math.sin(mid),dh])
            distance=ds+self.rng.normal(0,.015+.035*abs(ds),self.n)
            rotation=dh+self.rng.normal(0,math.radians(.015)+.07*abs(dh),self.n)
            mid=self.poses[:,2]+rotation/2
            self.poses[:,0]+=distance*np.cos(mid);self.poses[:,1]+=distance*np.sin(mid);self.poses[:,2]=wrapped(self.poses[:,2]+rotation)
            result['encoder_speed_mm_s']=ds/dt
        self.last=obs
        result['odom_x_mm'],result['odom_y_mm']=map(float,self.odom[:2])
        if not self.cal.ready:result['status']='CALIBRATION_REQUIRED';return result
        if not obs.sensor_ok:result['status']='SENSOR_READ_FAILED';return result
        if not obs.new_stamp or obs.sensor_stamp==self.last_sensor_stamp:
            result['status']='NO_NEW_SENSOR_TIMESTAMP';return result
        self.last_sensor_stamp=obs.sensor_stamp
        observed=self.cal.normalized(obs.values)
        expected,valid=self.map.expected(self.poses,self.offsets,self.geometry.get('optical_blur_mm',1.0))
        usable=valid.sum(axis=1)>=3
        if not usable.any():result['status']='OUTSIDE_MAP';return result
        rms=np.sqrt(np.sum(np.where(valid,(expected-observed)**2,0),axis=1)/np.maximum(1,valid.sum(axis=1)))
        if np.min(rms[usable])>.4:result['status']='MAP_MISMATCH';return result
        likelihood=.9*np.exp(-.5*((expected-observed)/.22)**2)+.04
        logp=np.sum(np.log(np.where(valid,likelihood,.5)),axis=1)
        logp[~usable]=-50
        if np.ptp(logp[usable])<.15:
            result['status']='ODOMETRY_ONLY_NO_MAP_CONSTRAINT';return result
        weights=self.weights*np.exp(logp-logp.max())
        weights/=weights.sum();self.weights=weights
        mu,spread,angular=self.summary()
        # A particle cloud is an uncertainty estimate under model assumptions,
        # not an externally calibrated accuracy or confidence percentage.
        result.update(std_x_mm=float(spread[0]),std_y_mm=float(spread[1]),std_heading_deg=math.degrees(angular),normalized_values=observed.tolist())
        mean_expected,mean_valid=self.map.expected(mu,self.offsets,self.geometry.get('optical_blur_mm',1.0))
        mean_count=int(mean_valid.sum())
        mean_rms=float(np.sqrt(np.sum(np.where(mean_valid,(mean_expected-observed)**2,0))/max(1,mean_count)))
        if max(spread)>12 or angular>math.radians(15) or mean_count<3 or mean_rms>.4:
            result['status']='AMBIGUOUS_MATCH'
        else:
            result.update(status='SENSOR_FUSED_PROVISIONAL' if result['geometry_provisional'] else 'SENSOR_FUSED_UNVALIDATED',measurement_accepted=True,x_mm=float(mu[0]),y_mm=float(mu[1]),theta_rad=float(mu[2]),inferred_cells=self.map.cell_ids(mu,self.offsets))
            # Only stable, sensor-updated positions contribute to map velocity.
            if self.history and np.linalg.norm(mu[:2]-self.history[-1][1][:2])>15:self.history=[]
            self.history.append((obs.time_ms,mu.copy()));self.history=[h for h in self.history if obs.time_ms-h[0]<=600]
            if len(self.history)>=8 and self.history[-1][0]-self.history[0][0]>=300:
                times=np.array([h[0] for h in self.history],dtype=float)/1000;times-=times.mean()
                positions=np.array([h[1] for h in self.history]);den=times@times
                velocity=times@positions[:,:2]/den
                result['speed_mm_s']=float(np.linalg.norm(velocity))
                angles=np.unwrap(positions[:,2]);result['turn_deg_s']=float(np.degrees(times@angles/den))
        if 1/np.sum(self.weights**2)<.65*self.n:
            positions=(self.rng.random()+np.arange(self.n))/self.n
            idx=np.searchsorted(np.cumsum(self.weights),positions);idx=np.minimum(idx,self.n-1)
            self.poses=self.poses[idx].copy();self.weights.fill(1/self.n)
        return result

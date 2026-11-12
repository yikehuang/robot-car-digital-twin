"""Software checks only. Does not start hardware or establish physical accuracy."""
import json, socket, sys, tempfile, threading, time
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from sensor_map.core import Observation,Calibration,SensorLocalizer,signed_delta
from sensor_map.network import RobotConnection

def frame(seq=1,stamp=10,new=1,values=(100,200,300,400,500),ms=None,left=0,right=0):
    return f'GRID1,{seq},{ms if ms is not None else seq*20},1,{left},{right},1,{stamp},{new},'+','.join(map(str,values))+',0,0,0,0,0,700'

def main():
    data=json.loads((ROOT/'maps/coded_grid_v2/map.json').read_text());g=json.loads((ROOT/'sensor_map/geometry.example.json').read_text());a=np.array(data['cells'],dtype=np.uint8)
    seen=set()
    for r in range(24):
        for c in range(36):
            for k in range(4):
                key=np.rot90(a[r:r+5,c:c+5],k).tobytes();assert key not in seen;seen.add(key)
    assert signed_delta(-2147483648,2147483647)==1
    for bad in (frame().replace(',1,10,1,',',2,10,1,'),frame().replace(',100,',',70000,'),frame()+',0'):
        try:Observation.parse(bad)
        except ValueError:pass
        else:raise AssertionError('Bad frame accepted')
    cal=Calibration([100]*5,[1100]*5);f=SensorLocalizer(data,g,cal)
    assert f.update(Observation.parse(frame()))['x_mm'] is None
    f.reset();obs=Observation.parse(frame());f.update(obs)
    repeated=f.update(Observation.parse(frame(seq=2,stamp=10)))
    assert repeated['status']=='NO_NEW_SENSOR_TIMESTAMP' and repeated['x_mm'] is None
    f=SensorLocalizer(data,g,Calibration());f.reset()
    assert f.update(obs)['status']=='CALIBRATION_REQUIRED'
    # Straight synthetic motion, no square stages or PWM. Biased encoder distance.
    f=SensorLocalizer(data,g,cal,particles=3500);f.reset();errors=[];accepted=0
    for i in range(1,401):
        true_pose=np.array([i*.3,0.,0.]);expected,valid=f.map.expected(true_pose,f.offsets)
        raw=np.rint(100+1000*expected[0]).astype(int)
        counts=round(i*.3*1.04/f.mm_count)
        out=f.update(Observation.parse(frame(seq=i,stamp=i*20000,values=raw,left=counts,right=counts)))
        if out['measurement_accepted']:
            accepted+=1;errors.append(abs(out['x_mm']-true_pose[0]))
    assert accepted>100,(accepted,'too few synthetic matches')
    assert np.median(errors)<10,(np.median(errors),'unstable synthetic tracking')
    reboot=f.update(Observation.parse(frame(seq=1,stamp=1,ms=1)))
    assert reboot['x_mm'] is None and not f.initialized
    # Actual USB observations collected with wheels suspended: stationary, no command.
    capture=ROOT.parents[1]/'grid_stationary_20261112.csv'
    if capture.exists():
        observations=[Observation.parse(x) for x in capture.read_text(encoding='utf-8-sig').splitlines() if x.startswith('GRID1,')]
        assert len(observations)>100 and all(o.encoder_ok and o.sensor_ok and o.left_pwm==o.right_pwm==0 for o in observations)
        assert len(set((o.left,o.right) for o in observations))==1
        print('Real stationary USB observations:',len(observations),'unique sensor timestamps:',len({o.sensor_stamp for o in observations}))
    # Loopback server exercises real receiver AUTH/heartbeat/STOP without motion.
    with tempfile.TemporaryDirectory() as td:
        key=Path(td)/'control.key';key.write_text('a'*32)
        listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(3)
        received=[];done=threading.Event();errors_network=[]
        def serve():
            try:
                s,_=listener.accept()
                with s:
                    s.settimeout(.02);s.sendall(b'CTRL HELLO 0123456789abcdef SQUARE_REMOTE_V3\n');buf=b'';t=time.monotonic();n=0
                    while time.monotonic()-t<1.2:
                        n+=1;s.sendall((frame(n,stamp=n*20000)+'\n').encode())
                        try:
                            chunk=s.recv(4096)
                            if not chunk:break
                            buf+=chunk
                        except socket.timeout:pass
                        except (ConnectionAbortedError,ConnectionResetError):break
                        while b'\n' in buf:
                            line,buf=buf.split(b'\n',1);verb=line.decode().split()[0];received.append(verb)
                            if verb=='AUTH':s.sendall(b'CTRL READY 0123456789abcdef\n')
                        time.sleep(.02)
            except (ConnectionAbortedError,ConnectionResetError):pass
            except Exception as e:errors_network.append(str(e))
            finally:done.set()
        server=threading.Thread(target=serve);server.start()
        client=RobotConnection('127.0.0.1',key,port=listener.getsockname()[1]);client.start()
        deadline=time.monotonic()+2
        while not client.ready and time.monotonic()<deadline:time.sleep(.02)
        assert client.ready
        client.request('START');client.request('STOP') # STOP wins within a pending batch.
        time.sleep(.4);client.stop();client.join(3);done.wait(3);listener.close();server.join(3)
        assert not errors_network,errors_network
        assert 'AUTH' in received and 'HEARTBEAT' in received and 'STOP' in received and 'START' not in received,received
        assert client.start_requests_sent==0
    print('PASS: oriented patches',len(seen),'synthetic accepted',accepted,'median x error mm',round(float(np.median(errors)),3),'parser/stale/reboot/calibration/network guards')

if __name__=='__main__':main()

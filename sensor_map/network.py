"""Authenticated observation receiver. Only explicit UI actions can send START."""
from pathlib import Path
from datetime import datetime,timezone
import queue,re,socket,threading,time
from .core import Observation,GRID_HEADER

class RobotConnection(threading.Thread):
    def __init__(self,host,key_file=None,log_folder=None,port=80):
        super().__init__(daemon=True)
        self.host=host;self.port=port;self.events=queue.Queue(maxsize=5000);self.commands=queue.Queue()
        self.key=''
        if key_file and Path(key_file).is_file():
            candidate=Path(key_file).read_text(encoding='utf-8').strip().lower()
            if not re.fullmatch('[0-9a-f]{32}',candidate):raise ValueError('Invalid private key format')
            self.key=candidate
        self.quit=threading.Event();self.ready=False;self.nonce='';self.sequence=0;self.last_frame=0
        self.latest=None;self.status='Not connected';self.log_folder=Path(log_folder) if log_folder else None
        self.dropped_events=0;self.start_requests_sent=0
    def request(self,verb):
        if verb not in ('START','STOP'):raise ValueError('Unsupported command')
        self.commands.put(verb)
    def emit(self,event):
        try:self.events.put_nowait(event)
        except queue.Full:self.dropped_events+=1
    def stop(self):self.quit.set()
    def run(self):
        raw=grid=None
        try:
            if self.log_folder:
                self.log_folder.mkdir(parents=True,exist_ok=False)
                raw=(self.log_folder/'received.raw.log').open('w',encoding='utf-8')
                grid=(self.log_folder/'observations.csv').open('w',encoding='utf-8');grid.write(GRID_HEADER+'\n')
            while not self.quit.is_set():
                self.ready=False;self.nonce='';self.sequence=0;self.latest=None;self.last_frame=0
                while not self.commands.empty():self.commands.get_nowait() # Reconnect never carries a pending start.
                try:
                    self.status='Connecting';self.emit(('status',self.status))
                    with socket.create_connection((self.host,self.port),timeout=2) as sock:
                        sock.settimeout(.05);buf=b'';heartbeat=0;flush=0
                        self.status='Connected; awaiting GRID1';self.emit(('status',self.status))
                        def send(verb):
                            self.sequence+=1
                            sock.sendall(f'{verb} {self.nonce} {self.sequence}\n'.encode('ascii'))
                        while not self.quit.is_set():
                            now=time.monotonic()
                            requested=[]
                            while not self.commands.empty():requested.append(self.commands.get_nowait())
                            if self.ready and 'STOP' in requested:send('STOP')
                            elif self.ready and 'START' in requested and self.latest and self.latest.state==0 and self.latest.encoder_ok and now-self.last_frame<.6:
                                send('START');self.start_requests_sent+=1
                            if self.ready and now-self.last_frame<.6 and now-heartbeat>=.2:
                                send('HEARTBEAT');heartbeat=now
                            try:chunk=sock.recv(4096)
                            except socket.timeout:chunk=None
                            if chunk==b'':raise ConnectionError('Robot disconnected')
                            if chunk:buf+=chunk
                            if len(buf)>65536:raise ConnectionError('Oversized TCP line')
                            while b'\n' in buf:
                                line,buf=buf.split(b'\n',1);line=line.decode('utf-8',errors='replace').strip()
                                if raw:raw.write(datetime.now(timezone.utc).isoformat()+' '+line+'\n')
                                parts=line.split(' ')
                                if len(parts)==4 and parts[:2]==['CTRL','HELLO'] and parts[3]=='SQUARE_REMOTE_V3' and re.fullmatch('[0-9a-f]{16}',parts[2]):
                                    if self.nonce!=parts[2]:self.ready=False;self.sequence=0;self.nonce=parts[2]
                                    if self.key and not self.ready:sock.sendall(f'AUTH {self.nonce} {self.key}\n'.encode('ascii'))
                                    elif not self.key:self.emit(('status','Read-only: private key not paired'))
                                elif len(parts)==3 and parts[:2]==['CTRL','READY'] and parts[2]==self.nonce and self.key:
                                    self.ready=True;self.emit(('status','Authenticated / explicit START only'))
                                elif line.startswith('CTRL DENIED'):
                                    self.ready=False;self.emit(('status','Control key mismatch; read-only'))
                                if line.startswith('GRID1,'):
                                    try:obs=Observation.parse(line)
                                    except ValueError as exc:self.emit(('status','Invalid GRID1 frame: '+str(exc)));continue
                                    self.latest=obs;self.last_frame=time.monotonic();self.emit(('observation',obs))
                                    if grid:grid.write(line+'\n')
                            if now-flush>1:
                                if raw:raw.flush()
                                if grid:grid.flush()
                                flush=now
                        if self.ready:
                            try:send('STOP')
                            except OSError:pass
                except OSError as exc:
                    self.ready=False;self.emit(('status',str(exc)))
                    self.quit.wait(1)
        finally:
            self.ready=False
            if raw:raw.close()
            if grid:grid.close()

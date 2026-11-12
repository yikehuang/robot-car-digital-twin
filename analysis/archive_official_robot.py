"""Archive the complete official manual and primary mechanical drawings."""
from pathlib import Path
import hashlib,json,re,urllib.request,urllib.parse
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'knowledge-base/official-pololu-20261112'
OUT.mkdir(parents=True,exist_ok=True)
sources={
 'manual.html':'https://www.pololu.com/docs/0J83/all',
 'manual.pdf':'https://www.pololu.com/docs/pdf/0J83/3pi_plus_32u4.pdf',
 'chassis.html':'https://www.pololu.com/product/3725',
 'board-lcd.pdf':'https://www.pololu.com/file/0J1792/3pi-plus-32u4-control-board-dimensions.pdf',
 'board-oled.pdf':'https://www.pololu.com/file/0J1825/3pi-plus-32u4-oled-control-board-dimensions.pdf',
 'robot-lcd.pdf':'https://www.pololu.com/file/0J1796/3pi-plus-32u4-robot-dimensions.pdf',
 'robot-oled.pdf':'https://www.pololu.com/file/0J1827/3pi-plus-32u4-oled-robot-dimensions.pdf',
 'chassis.pdf':'https://www.pololu.com/file/0J1795/3pi-plus-chassis-kit-dimensions.pdf'}
manifest=[]
for name,url in sources.items():
    body=urllib.request.urlopen(url,timeout=40).read();(OUT/name).write_bytes(body)
    manifest.append(dict(file=name,url=url,sha256=hashlib.sha256(body).hexdigest(),bytes=len(body)))
(OUT/'sources.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
html=(OUT/'manual.html').read_text(encoding='utf-8')
links=sorted(set(urllib.parse.urljoin(sources['manual.html'],x) for x in re.findall(r'href=[\x22\x27]([^\x22\x27]+)',html) if '/file/' in x))
(OUT/'linked-resources.json').write_text(json.dumps(links,indent=2),encoding='utf-8')
g=ROOT/'sensor_map/geometry.example.json';data=json.loads(g.read_text())
data.update(provenance='Official 3pi03a/3pi03b probe-relative layout; axle-to-DN3 remains user approximate 30 mm, not official. Motor variant not confirmed.',sensor_offsets_forward_left_mm=[[16.5,30],[28.5,10],[30,0],[28.5,-10],[16.5,-30]],wheel_radius_mm=16.0)
data['parameter_status']={'probe_relative_layout':'official drawing page 5; both revisions agree','axle_to_dn3':'user approximate 30 mm; unverified','wheel_radius_mm':'nominal official 32 mm diameter / 2; rolling radius unmeasured','wheel_separation_mm':'legacy controller value; not yet verified against drawing','counts_per_revolution':'legacy 358.3; motor variant must be confirmed','optical_blur_mm':'unmeasured model approximation'}
g.write_text(json.dumps(data,indent=2),encoding='utf-8')
# Map regeneration must never overwrite independently maintained geometry.
p=ROOT/'analysis/create_coded_grid.py';s=p.read_text(encoding='utf-8');s='\n'.join(x for x in s.splitlines() if not x.lstrip().startswith(('geometry=dict(',"(ROOT/'sensor_map/geometry.example.json').write_text")))+'\n';p.write_text(s,encoding='utf-8')
print('Archived',len(manifest),'official documents; updated probe layout and nominal radius. No firmware upload.')

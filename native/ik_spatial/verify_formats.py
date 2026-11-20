"""发行解码器回归：命令行与 verify_mpv.py 相同，ffmpeg 仅生成门样本。"""
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import subprocess
import threading
import verify_mpv as gate

ffmpeg = os.environ.get('IK_GATE_FFMPEG', 'ffmpeg')
root = gate.output_dir
gate.render(48000,'','format-seed')
source=root/'input-48000.wav'
formats={'flac': ['-c:a','flac'], 'mp3': ['-c:a','libmp3lame'],
         'm4a': ['-c:a','aac'], 'ogg': ['-c:a','libvorbis'],
         'opus': ['-c:a','libopus'], 'dts': ['-c:a','dca','-strict','-2'],
         'wma': ['-c:a','wmav2'], 'm3u8': ['-c:a','aac','-f','hls','-hls_time','1']}
for extension, options in formats.items():
    subprocess.run([ffmpeg,'-y','-v','error','-i',str(source),*options,
                    str(root/f'sample.{extension}')],check=True)

class Quiet(SimpleHTTPRequestHandler):
    def log_message(self,*args): pass

server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(root)))
thread=threading.Thread(target=server.serve_forever,daemon=True)
thread.start()
cases=0
try:
    for extension in ['wav',*formats]:
        filename='input-48000.wav' if extension=='wav' else f'sample.{extension}'
        for network in (False, True):
            url=f'http://127.0.0.1:{server.server_port}/{filename}' if network else str(root/filename).replace('\\','/')
            pcm,frames,_,logs=gate.render(48000,
                '@ikspatial:lavfi=[equalizer=f=1000:t=q:w=1:g=-3,ikhrtf=strength=0.65:request=42]',
                f'{extension}-{"http" if network else "file"}',source_url=url,speed=1.25)
            assert int(frames)>0 and any(abs(x)>1e-6 for x in pcm), (extension,network,logs)
            assert not any('failed' in x.lower() for x in logs), (extension,network,logs)
            cases+=1
finally:
    server.shutdown()
    server.server_close()
print(f'U07 codec/file/HTTP/EQ/HRTF/speed gate: {cases} cases PASS')

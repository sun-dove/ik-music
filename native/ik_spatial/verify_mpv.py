"""Windows 发行 DLL 的真实解码→滤镜→PCM 门；不播放声音。"""
import argparse
import ctypes as c
import hashlib
import io
import math
from pathlib import Path
import struct
import time
import wave
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("--dll", required=True)
parser.add_argument("--output-dir", required=True)
args = parser.parse_args()
dll_path = Path(args.dll).resolve()
output_dir = Path(args.output_dir).resolve()
output_dir.mkdir(parents=True, exist_ok=True)
assert dll_path.stat().st_size <= 15525902+2097152, "U07 DLL size budget"
lib = c.CDLL(str(dll_path))
lib.mpv_create.restype = c.c_void_p
lib.mpv_initialize.argtypes = [c.c_void_p]
lib.mpv_set_option_string.argtypes = [c.c_void_p,c.c_char_p,c.c_char_p]
lib.mpv_set_property_string.argtypes = [c.c_void_p,c.c_char_p,c.c_char_p]
lib.mpv_get_property_string.argtypes = [c.c_void_p,c.c_char_p]
lib.mpv_get_property_string.restype = c.c_void_p
lib.mpv_free.argtypes = [c.c_void_p]
lib.mpv_command_string.argtypes = [c.c_void_p,c.c_char_p]
lib.mpv_terminate_destroy.argtypes = [c.c_void_p]
lib.mpv_request_log_messages.argtypes = [c.c_void_p,c.c_char_p]
lib.ik_spatial_processed_frames.argtypes = [c.c_int64]
lib.ik_spatial_processed_frames.restype = c.c_int64
class Event(c.Structure):
    _fields_ = [("event_id",c.c_int),("error",c.c_int),("reply_userdata",c.c_uint64),("data",c.c_void_p)]
class Log(c.Structure):
    _fields_ = [("prefix",c.c_char_p),("level",c.c_char_p),("text",c.c_char_p),("log_level",c.c_int)]
lib.mpv_wait_event.argtypes = [c.c_void_p,c.c_double]
lib.mpv_wait_event.restype = c.POINTER(Event)

def prop(handle, name):
    ptr = lib.mpv_get_property_string(handle,name.encode())
    if not ptr:
        return ""
    result = c.string_at(ptr).decode("utf-8", "replace")
    lib.mpv_free(ptr)
    return result


def render(rate, filter_string, label, source_url=None, speed=1):
    source = output_dir / f"input-{rate}.wav"
    # 稳态区脉冲避免把开启20ms平滑当作HRTF系数差异。
    samples = [0] * (rate*2)
    samples[(rate//4)*2] = 8192
    samples[(rate//2)*2+1] = 8192
    with wave.open(str(source), "wb") as wav:
        wav.setparams((2,2,rate,rate,"NONE","not compressed"))
        wav.writeframes(struct.pack("<"+"h"*len(samples),*samples))
    target = output_dir / f"{label}-{rate}.wav"
    handle = lib.mpv_create()
    assert handle
    logs = []
    frames = request = ""
    try:
        for name,value in {"config":"no","vo":"null","ao":"pcm",
            "ao-pcm-file":str(target),"audio-format":"float","keep-open":"yes",
            "idle":"yes","volume":"100","speed":str(speed),"af":filter_string}.items():
            assert lib.mpv_set_option_string(handle,name.encode(),value.encode()) >= 0, name
        assert lib.mpv_initialize(handle) == 0
        lib.mpv_request_log_messages(handle,b"warn")
        result = lib.mpv_command_string(handle, ('loadfile "'+(source_url or str(source).replace('\\','/'))+'"').encode())
        assert result == 0, result
        deadline=time.monotonic()+15
        while time.monotonic() < deadline:
            event=lib.mpv_wait_event(handle,.05).contents
            if event.event_id == 2:
                log=c.cast(event.data,c.POINTER(Log)).contents
                logs.append(log.text.decode("utf-8","replace").strip())
            if filter_string:
                request = "43" if label == "eq-hrtf" else "42"
                frames = str(lib.ik_spatial_processed_frames(int(request)))
            if prop(handle,"eof-reached") == "yes":
                break
        else:
            raise AssertionError("playback timeout: "+str(logs))
    finally:
        lib.mpv_terminate_destroy(handle)
    data=target.read_bytes()
    offset=data.index(b"data")+8
    pcm=struct.unpack("<"+"f"*((len(data)-offset)//4),data[offset:])
    return pcm,frames,request,logs


if __name__ == '__main__':
    assert lib.ik_spatial_abi_version() == 1
    cases=0
    for rate in (44100,48000):
        baseline,_,_,logs=render(rate,"","bypass")
        assert not any("failed" in x.lower() for x in logs), logs
        directional=[]
        for azimuth,elevation in ((0,0),(90,0),(180,0),(0,30),(0,-30)):
            pcm,frames,request,logs=render(rate,
                f"@ikspatial:lavfi=[ikhrtf=strength=1:azimuth={azimuth}:elevation={elevation}:request=42]",
                f"hrtf-{azimuth}-{elevation}")
            assert int(frames) > 0 and request == "42", (frames,request,logs)
            assert not any("failed" in x.lower() or "no such filter" in x.lower() for x in logs), logs
            left=sum(x*x for x in pcm[::2]); right=sum(x*x for x in pcm[1::2])
            assert left>0 and right>0 and pcm != baseline, (left,right)
            directional.append(pcm)
            cases += 1
        assert all(directional[0] != p for p in directional[1:]), "directions must differ"
        # 独立地从官方原始 WAV 解码并卷积，不读取C核心或生成的系数表。
        with zipfile.ZipFile(Path(__file__).parent/'data/mit-kemar-diffuse.zip') as archive:
            with wave.open(io.BytesIO(archive.read('elev0/H0e030a.wav'))) as wav:
                raw=struct.unpack('<256h',wav.readframes(128))
        for channel in (0,1):
            position=rate//4 if channel==0 else rate//2
            for ear in (0,1):
                source_ear=1-ear if channel==0 else ear
                impulse=[x/32768 for x in raw[source_ear::2]]
                for tap in range(256):
                    if rate==44100:
                        expected=impulse[tap] if tap<128 else 0
                    else:
                        where=tap*44100/rate
                        expected=0
                        for j in range(max(0,math.floor(where)-16),min(128,math.floor(where)+17)):
                            d=where-j
                            if abs(d)<16:
                                sinc=math.sin(math.pi*d)/(math.pi*d) if d else 1
                                expected+=impulse[j]*sinc*(.5+.5*math.cos(math.pi*d/16))*44100/rate
                    assert abs(directional[0][2*(position+tap)+ear]-.125*expected)<2e-6, 'raw HRTF golden mismatch'
        pcm,frames,request,logs=render(rate,
            "@ikspatial:lavfi=[equalizer=f=1000:t=q:w=1:g=-6,ikhrtf=strength=0.65:request=43]",
            "eq-hrtf")
        assert int(frames)>0 and request=="43", logs
        assert not any("failed" in x.lower() for x in logs), logs
        cases += 1
    print(f"U07 actual libmpv PCM: {cases} cases PASS; bytes={dll_path.stat().st_size}; sha256={hashlib.sha256(dll_path.read_bytes()).hexdigest()}")

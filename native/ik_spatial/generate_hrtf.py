"""从固定 MIT KEMAR 原始包生成共享系数；不联网、不生成合成耳间延迟。"""
import hashlib
import io
import math
from pathlib import Path
import struct
import wave
import zipfile

ROOT = Path(__file__).resolve().parent
ARCHIVE = ROOT / "data/mit-kemar-diffuse.zip"
EXPECTED = "a48e73137390626ef1e45d1de6a4d98530c6aa570e71b40f7c4442241ed5fa22"
raw = ARCHIVE.read_bytes()
assert hashlib.sha256(raw).hexdigest() == EXPECTED
archive = zipfile.ZipFile(io.BytesIO(raw))
measurements = {}
for name in archive.namelist():
    if not name.endswith(".wav"):
        continue
    label = Path(name).stem
    elevation, azimuth = map(int, label[1:-1].split("e"))
    with wave.open(io.BytesIO(archive.read(name))) as audio:
        assert audio.getparams()[:4] == (2, 2, 44100, 128)
        values = struct.unpack("<256h", audio.readframes(128))
    measurements[elevation, azimuth] = [
        [v / 32768 for v in values[ear::2]] for ear in range(2)
    ]


def direction(elevation, azimuth):
    mirror = azimuth > 180
    azimuth = 360 - azimuth if mirror else azimuth
    available = sorted(a for e, a in measurements if e == elevation)
    low = max(a for a in available if a <= azimuth)
    high = min(a for a in available if a >= azimuth)
    blend = (azimuth - low) / (high - low) if high != low else 0
    result = []
    for ear in range(2):
        side = 1 - ear if mirror else ear
        a, b = measurements[elevation, low][side], measurements[elevation, high][side]
        result.append([x + (y-x)*blend for x, y in zip(a, b)])
    return result


def resample(values, rate):
    if rate == 44100:
        return values + [0.0] * (256 - len(values))
    # 32 点窗 sinc 重采样，保持脉冲面积；在生成期完成，不随播放器执行。
    ratio = 44100 / rate
    out = []
    for i in range(256):
        position = i * ratio
        total = 0.0
        for j in range(max(0, math.floor(position)-16), min(128, math.floor(position)+17)):
            distance = position - j
            if abs(distance) >= 16:
                continue
            sinc = math.sin(math.pi*distance)/(math.pi*distance) if distance else 1
            window = 0.5 + 0.5*math.cos(math.pi*distance/16)
            total += values[j] * sinc * window * ratio
        out.append(total)
    return out


rows = ["/* 生成文件：MIT KEMAR，Bill Gardner / Keith Martin，1994。见 data/MIT-KEMAR-LICENSE。 */",
        "static const float ik_hrtf[2][3][24][2][256] = {"]
for rate in (44100, 48000):
    rows.append("{")
    for elevation in (-30, 0, 30):
        rows.append("{")
        for azimuth in range(0, 360, 15):
            rows.append("{")
            for ear in direction(elevation, azimuth):
                rows.append("{" + ",".join(f"{v:.9e}f" for v in resample(ear, rate)) + "},")
            rows.append("},")
        rows.append("},")
    rows.append("},")
rows.append("};")
destination = ROOT / "ik_hrtf_data.h"
destination.write_text("\n".join(rows) + "\n", encoding="utf-8")
print(f"HRTF: {2*3*24*2*256*4} coefficient bytes; sha256={hashlib.sha256(destination.read_bytes()).hexdigest()}")

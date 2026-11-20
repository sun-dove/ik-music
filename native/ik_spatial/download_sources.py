"""下载并校验固定原生源码，给本机与 CI 共用；无凭据。"""
import argparse
import hashlib
from pathlib import Path
import urllib.request

SOURCES = {
    "ffmpeg-6.0.tar.xz": ("https://ffmpeg.org/releases/ffmpeg-6.0.tar.xz", "57be87c22d9b49c112b6d24bc67d42508660e6b718b3db89c44e47e289137082"),
    "mpv.tar.gz": ("https://codeload.github.com/mpv-player/mpv/tar.gz/652a1dd907", "e13eff8194ebee42c60d016e12b4d773df63a484da8ad723081f08677d1ba797"),
    "freetype.tar.gz": ("https://codeload.github.com/freetype/freetype/tar.gz/refs/tags/VER-2-13-2", "427201f5d5151670d05c1f5b45bef5dda1f2e7dd971ef54f0feaaa7ffd2ab90c"),
    "fribidi.tar.gz": ("https://codeload.github.com/fribidi/fribidi/tar.gz/refs/tags/v1.0.13", "f24e8e381bcf76533ae56bd776196f3a0369ec28e9c0fdb6edd163277e008314"),
    "harfbuzz.tar.gz": ("https://codeload.github.com/harfbuzz/harfbuzz/tar.gz/refs/tags/8.3.0", "6a093165442348d99f3307480ea87ed83bdabaf642cdd9548cff6b329e93bfac"),
    "libass.tar.gz": ("https://codeload.github.com/libass/libass/tar.gz/refs/tags/0.17.1", "5ba42655d7e8c5e87bba3ffc8a2b1bc19c29904240126bb0d4b924f39429219f"),
}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True)
    parser.add_argument("--verify-only", action="store_true")
    options = parser.parse_args()
    directory = Path(options.directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    for filename, (url, expected) in SOURCES.items():
        target = directory / filename
        if not target.exists() and not options.verify_only:
            urllib.request.urlretrieve(url, target)
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit(f"源码 SHA-256 不匹配：{filename}")
        print(filename, actual)

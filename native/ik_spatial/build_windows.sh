#!/usr/bin/env bash
# 在 Ubuntu/WSL 的 MinGW 工具链构建一个音频 DLL；不更改全局包缓存。
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
work=${1:?需要独立构建目录}
cache=${2:?需要固定下载归档目录}
prefix="$work/prefix"
mkdir -p "$work/src" "$prefix"
python3 "$root/download_sources.py" --directory "$cache" --verify-only
cd "$work/src"
for archive in ffmpeg-6.0.tar.xz mpv.tar.gz freetype.tar.gz fribidi.tar.gz harfbuzz.tar.gz libass.tar.gz; do
    tar -xf "$cache/$archive"
done
cat > "$work/cross.ini" <<EOF
[binaries]
c = 'x86_64-w64-mingw32-gcc'
cpp = 'x86_64-w64-mingw32-g++'
ar = 'x86_64-w64-mingw32-ar'
strip = 'x86_64-w64-mingw32-strip'
windres = 'x86_64-w64-mingw32-windres'
pkgconfig = 'pkg-config'
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
[properties]
needs_exe_wrapper = true
[built-in options]
c_args = ['-O2']
c_link_args = ['-static-libgcc', '-static']
cpp_link_args = ['-static-libgcc', '-static-libstdc++', '-static']
EOF
export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig:$prefix/share/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
jobs=${IK_BUILD_JOBS:-8}
build_meson() {
    local name=$1 source=$2; shift 2
    meson setup "$work/$name" "$source" --prefix "$prefix" --libdir lib \
        --cross-file "$work/cross.ini" --default-library static --buildtype release "$@"
    ninja -C "$work/$name" -j "$jobs" install
}
if [[ ! -f "$prefix/lib/libfreetype.a" ]]; then
    build_meson freetype "$work/src/freetype-VER-2-13-2" \
        -Dzlib=disabled -Dbzip2=disabled -Dpng=disabled -Dharfbuzz=disabled -Dbrotli=disabled
fi
if [[ ! -f "$prefix/lib/libfribidi.a" ]]; then
    build_meson fribidi "$work/src/fribidi-1.0.13" -Ddocs=false -Dbin=false -Dtests=false
fi
if [[ ! -f "$prefix/lib/libharfbuzz.a" ]]; then
    build_meson harfbuzz "$work/src/harfbuzz-8.3.0" -Dglib=disabled -Dgobject=disabled \
        -Dcairo=disabled -Dicu=disabled -Dfreetype=disabled -Dtests=disabled -Ddocs=disabled -Dutilities=disabled
fi
if [[ ! -f "$prefix/lib/libass.a" ]]; then
    cd "$work/src/libass-0.17.1"
    autoreconf -fi
    ./configure --host=x86_64-w64-mingw32 --prefix="$prefix" --disable-shared \
        --enable-static --disable-fontconfig --disable-require-system-font-provider
    make -j "$jobs"
    make install
fi
cd "$work/src/ffmpeg-6.0"
patch -p1 --forward < "$root/ffmpeg-binutils-2.41.patch"
cp "$root/af_ikhrtf.c" "$root/ik_spatial.c" "$root/ik_spatial.h" "$root/ik_hrtf_data.h" libavfilter/
python3 - <<'PY'
from pathlib import Path
p=Path('libavfilter/Makefile')
s=p.read_text()
if 'CONFIG_IKHRTF_FILTER' not in s:
    p.write_text(s+'\nOBJS-$(CONFIG_IKHRTF_FILTER) += af_ikhrtf.o ik_spatial.o\n')
p=Path('libavfilter/allfilters.c')
s=p.read_text()
if 'ff_af_ikhrtf;' not in s:
    p.write_text(s.replace('extern const AVFilter ff_af_abench;', 'extern const AVFilter ff_af_ikhrtf;\nextern const AVFilter ff_af_abench;'))
PY
./configure --prefix="$prefix" --cross-prefix=x86_64-w64-mingw32- --arch=x86_64 \
    --target-os=mingw32 --enable-cross-compile --pkg-config=pkg-config --pkg-config-flags=--static \
    --disable-autodetect --disable-gpl --disable-nonfree --enable-version3 --enable-static \
    --disable-shared --disable-programs --disable-doc --enable-small --disable-debug \
    --disable-muxers --disable-encoders --disable-decoders --disable-demuxers --disable-parsers \
    --enable-bsfs \
    --disable-protocols --disable-filters --disable-devices --disable-hwaccels --disable-avdevice \
    --disable-postproc --enable-network --enable-schannel \
    --enable-decoder='aac*,ac3,alac,als,ape,atrac*,eac3,flac,gsm*,mp1*,mp2*,mp3*,mpc*,opus,ra*,ralf,shorten,tak,tta,vorbis,wavpack,wma*,pcm*,dsd*,dca,mjpeg,ljpeg,jpegls,jpeg2000,png,gif,bmp,tiff,webp' \
    --enable-demuxer='aac,ac3,aiff,ape,asf,au,avi,flac,flv,matroska,mov,m4v,mp3,mpc*,ogg,pcm*,rm,shorten,tak,tta,wav,wv,xwma,dsf,dts,truehd,dtshd,hls' \
    --enable-parser='aac*,ac3,cook,flac,gsm,mpegaudio,tak,vorbis,dca,h264' \
    --enable-protocol='async,cache,crypto,data,ffrtmphttp,file,ftp,hls,http,httpproxy,https,pipe,rtmp,rtmps,rtmpt,rtmpts,rtp,subfile,tcp,tls,udp' \
    --enable-filter='ikhrtf,aresample,aformat,equalizer,volume,atempo,anull' \
    --extra-cflags='-O2' --extra-ldflags='-static-libgcc -static'
make -j "$jobs"
make install
cd "$work/src/mpv-652a1dd907"
if [[ ! -f "$work/mpv/build.ninja" ]]; then
    meson setup "$work/mpv" . --prefix "$prefix" --cross-file "$work/cross.ini" \
        --buildtype release --default-library shared --prefer-static -Dauto_features=disabled \
        -Dgpl=false -Dlibmpv=true -Db_ndebug=false -Dcplayer=false -Dwasapi=enabled \
        -Dwin32-internal-pthreads=enabled \
        -Dsdl2=disabled -Diconv=disabled -Dgl=disabled
fi
ninja -C "$work/mpv" -j "$jobs"
x86_64-w64-mingw32-strip -s "$work/mpv/libmpv-2.dll"
bytes=$(stat -c %s "$work/mpv/libmpv-2.dll")
(( bytes <= 15525902+2097152 )) || { echo "DLL exceeds U07 size budget: $bytes"; exit 1; }
sha256sum "$work/mpv/libmpv-2.dll"
printf 'U07 DLL bytes: %s\n' "$bytes"
python3 - "$work" "$root" <<'PY'
from pathlib import Path
import shutil, sys
work, root = map(Path, sys.argv[1:])
out = work/'licenses'
out.mkdir(exist_ok=True)
for source in (work/'src').iterdir():
    if source.is_dir():
        for name in ('LICENSE', 'LICENSE.md', 'LICENSE.GPL', 'LICENSE.LGPL', 'Copyright', 'COPYING', 'COPYING.LESSER', 'COPYING.LGPLv2.1', 'COPYING.LGPLv3', 'COPYING.GPLv2', 'COPYING.GPLv3', 'docs/FTL.TXT'):
            path=source/name
            if path.is_file():
                shutil.copy2(path, out/(source.name+'-'+path.name))
shutil.copy2(root/'data/MIT-KEMAR-LICENSE', out)
for package in ('gcc-mingw-w64-x86-64-posix', 'mingw-w64-common'):
    shutil.copy2(Path('/usr/share/doc')/package/'copyright', out/(package+'-copyright'))
shutil.copy2(root/'README.md', out/'源码与构建说明.md')
PY

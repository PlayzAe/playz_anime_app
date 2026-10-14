#!/bin/sh
# usage: shot.sh name  -> scratchpad/shots/name.png (downscaled to 480w)
S="$(dirname "$0")"
mkdir -p "$S/shots"
adb exec-out screencap -p > "$S/shots/raw.png"
python -c "
from PIL import Image;im=Image.open(r'$(dirname "$0")/shots/raw.png').convert('RGB');w,h=im.size;s=480/w;im=im.resize((480,int(h*s)));im.save(r'$(dirname "$0")/shots/$1.png',optimize=True)
"
echo "$S/shots/$1.png"

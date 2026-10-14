#!/bin/sh
# tap.sh x y   (coords in the 480-wide screenshot space)
adb shell input tap $(python -c "print(int($1*2.25), int($2*2.25))")

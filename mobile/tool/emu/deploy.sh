#!/bin/sh
# Build debug x64, install, relaunch. Prints analyzer errors if build fails.
cd "/c/Users/Moses/Desktop/Dev Code/Electron Conversion - transfer to mobile app"
if ! flutter build apk --debug --target-platform android-x64 > /tmp/build.log 2>&1; then grep -E "error|Error:" /tmp/build.log | head -20; exit 1; fi
adb install -r build/app/outputs/flutter-apk/app-debug.apk | tail -1
adb shell am force-stop tv.playzae.playzanime.debug
adb logcat -c
adb shell monkey -p tv.playzae.playzanime.debug -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo deployed

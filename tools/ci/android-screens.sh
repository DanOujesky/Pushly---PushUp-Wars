#!/usr/bin/env bash
# Runs inside the Android emulator job: installs the debug APK, grants the alarm permissions, opens each debug
# screen and takes a screenshot. The "ring" screen goes through the real path: a practice alarm armed with
# setAlarmClock → AlarmReceiver → AlarmRingService → full-screen RingActivity.
# Usage: tools/ci/android-screens.sh <apk> <out-dir>
set -uo pipefail
APK="$1"; OUT="$2"; PKG=app.pushly.debug
mkdir -p "$OUT"
adb wait-for-device
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb install -r "$APK"
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS || true
adb shell appops set $PKG SCHEDULE_EXACT_ALARM allow || true
adb shell appops set $PKG USE_FULL_SCREEN_INTENT allow || true
adb shell cmd deviceidle whitelist +$PKG || true
adb shell settings put system screen_off_timeout 1800000
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard || true

shot() { # name [wait-seconds]
  sleep "${2:-4}"
  adb exec-out screencap -p > "$OUT/$1.png"
  echo "captured $1"
}

open_screen() { # screen
  adb shell am force-stop $PKG
  adb shell am start -W -n $PKG/app.pushly.MainActivity --es debugScreen "$1" >/dev/null
}

for s in launch welcome signIn profileSetup update emptyWake wake editor permissions profile; do
  open_screen "$s"; shot "$s"
done

# Real alarm path: practice alarm in 3 s, phone locked.
adb shell am force-stop $PKG
adb shell am start -W -n $PKG/app.pushly.MainActivity --es debugScreen ring >/dev/null
sleep 1
adb shell input keyevent KEYCODE_SLEEP
sleep 8
adb shell input keyevent KEYCODE_WAKEUP
shot ring 3
adb shell dumpsys activity activities | grep -E "RingActivity|ResumedActivity" | head -5 > "$OUT/ring-activity.txt" || true
adb shell dumpsys activity services $PKG | grep -E "AlarmRingService|isForeground" | head -5 > "$OUT/ring-service.txt" || true
adb shell dumpsys alarm | grep -A3 "$PKG" | head -40 > "$OUT/alarms.txt" || true
adb logcat -d -s "Pushly/Alarm:*" "AndroidRuntime:E" | tail -80 > "$OUT/logcat.txt" || true
ls -la "$OUT"

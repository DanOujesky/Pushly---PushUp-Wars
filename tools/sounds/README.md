# Alarm sounds

`synth.py` generates the bundled alarm tones (`pulse`, `rise`, `arena`, `classic`, and the Pro pack `thunder`, `anthem`, `drill`, `sunrise` — D-074) from code, so they are
original and free of licence questions. They are placeholders until the licensed sound pack (decisions log Q-02).

```bash
python3 tools/sounds/synth.py android/feature/alarm/src/main/res/raw
python3 tools/sounds/synth.py ios/Pushly/Resources/Sounds
```
Ids: `bundled.<name>` (`AlarmSounds` on both platforms). 22.05 kHz mono 16-bit WAV, 24 s (Android loops them).

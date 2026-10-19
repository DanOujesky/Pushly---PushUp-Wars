"""Original synthesized alarm tones (public domain by construction). 22.05 kHz mono 16-bit WAV, 24 s, loop-friendly."""
import math, struct, sys, wave
from pathlib import Path

SR = 22050
DUR = 24.0
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)

def env(t, a=0.005, r=0.05, length=0.2):
    if t < 0 or t > length: return 0.0
    if t < a: return t / a
    if t > length - r: return max(0.0, (length - t) / r)
    return 1.0

def tone(f, t, harm=(1.0, 0.3, 0.12)):
    return sum(h * math.sin(2 * math.pi * f * (k + 1) * t) for k, h in enumerate(harm)) / sum(harm)

def render(name, fn):
    n = int(SR * DUR)
    frames = bytearray()
    peak = 0.0
    data = [fn(i / SR) for i in range(n)]
    peak = max(abs(x) for x in data) or 1.0
    for x in data:
        frames += struct.pack('<h', int(max(-1, min(1, x / peak * 0.89)) * 32767))
    with wave.open(str(out / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(bytes(frames))

def pulse(t):
    # beep-beep-beep … pause, 1 s cycle; pitch steps up every 8 s
    cyc = t % 1.0
    f = 880 * (1.0, 1.122, 1.26)[int(t // 8) % 3]
    return sum(env(cyc - s, length=0.12) for s in (0.0, 0.18, 0.36)) * tone(f, t)

def rise(t):
    # ascending arpeggio C-E-G-C, 0.6 s per bar
    notes = [523.25, 659.25, 783.99, 1046.5]
    cyc = t % 0.6
    i = int(cyc // 0.15)
    return env(cyc - i * 0.15, length=0.14) * tone(notes[i], t, (1.0, 0.5, 0.2))

def arena(t):
    # stadium horn stabs: low chord, two short + one long
    cyc = t % 2.0
    stabs = [(0.0, 0.18), (0.28, 0.18), (0.56, 0.7)]
    a = sum(env(cyc - s, a=0.02, r=0.08, length=l) for s, l in stabs)
    chord = sum(tone(f, t, (1.0, 0.7, 0.5, 0.35, 0.2)) for f in (196.0, 246.94, 293.66)) / 3
    return a * chord

def classic(t):
    # bell ring alternating 1000/1500 Hz, 0.5 s pattern with decay
    cyc = t % 0.5
    f = 1000.0 if int(t // 0.25) % 2 == 0 else 1500.0
    c = t % 0.25
    return math.exp(-c * 12) * tone(f, t, (1.0, 0.4, 0.25)) * (1 if cyc < 0.5 else 0)

for name, fn in [("pulse", pulse), ("rise", rise), ("arena", arena), ("classic", classic)]:
    render(name, fn)
    print("wrote", name)

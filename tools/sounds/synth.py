"""Original synthesized alarm tones (public domain by construction). 22.05 kHz mono 16-bit WAV, 24 s, loop-friendly."""
import math, random, struct, sys, wave
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

# --- Pro sound pack (D-074) -------------------------------------------------------------------------------------------
random.seed(7)
NOISE = [random.uniform(-1, 1) for _ in range(SR)]

def noise(t):
    return NOISE[int(t * SR) % SR]

def thunder(t):
    # war drums: boom-boom … BOOM, with a low brass swell every 4 s
    cyc = t % 1.0
    hits = [(0.0, 1.0), (0.25, 0.7), (0.5, 1.0)]
    drum = sum(v * math.exp(-max(0.0, cyc - s) * 18) * (cyc >= s) *
               (math.sin(2 * math.pi * (55 + 60 * math.exp(-(cyc - s) * 30)) * (cyc - s)) + 0.25 * noise(t))
               for s, v in hits)
    swell_t = t % 4.0
    swell = env(swell_t - 2.0, a=0.4, r=0.5, length=1.6) * tone(110.0, t, (1.0, 0.8, 0.6, 0.4, 0.3))
    return drum + 0.6 * swell

def anthem(t):
    # stadium fanfare: G4 C5 E5 G5 – E5 G5 (held), 3 s phrase
    melody = [(0.0, 0.2, 392.0), (0.25, 0.2, 523.25), (0.5, 0.2, 659.25), (0.75, 0.55, 783.99),
              (1.4, 0.2, 659.25), (1.65, 1.0, 783.99)]
    cyc = t % 3.0
    out = 0.0
    for s, l, f in melody:
        e = env(cyc - s, a=0.015, r=0.08, length=l)
        if e: out += e * tone(f, t, (1.0, 0.75, 0.55, 0.4, 0.25, 0.15))
    return out

def drill(t):
    # drill sergeant: snare roll then two whistle blasts, 1.6 s
    cyc = t % 1.6
    snare = 0.0
    if cyc < 0.6:
        c = cyc % 0.075
        snare = math.exp(-c * 60) * noise(t) * (0.5 + cyc)
    w = env(cyc - 0.75, a=0.01, r=0.03, length=0.22) + env(cyc - 1.05, a=0.01, r=0.04, length=0.38)
    whistle = w * math.sin(2 * math.pi * (2800 + 120 * math.sin(2 * math.pi * 28 * t)) * t)
    return 0.8 * snare + whistle

def sunrise(t):
    # bright marimba arpeggio that climbs over 8 s, then starts again
    notes = [440.0, 554.37, 659.25, 880.0, 1108.73, 1318.51]
    step = 0.18
    i = int(t / step)
    c = t - i * step
    f = notes[i % len(notes)] * (1.0, 1.122, 1.26, 1.335)[int((t % 8.0) // 2)]
    return math.exp(-c * 9) * tone(f, t, (1.0, 0.0, 0.35, 0.0, 0.12)) * (c >= 0)

for name, fn in [("pulse", pulse), ("rise", rise), ("arena", arena), ("classic", classic),
                 ("thunder", thunder), ("anthem", anthem), ("drill", drill), ("sunrise", sunrise)]:
    render(name, fn)
    print("wrote", name)

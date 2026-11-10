"""Synthesise the game's basic sound effects (no samples needed).

    python3 tools/make_sfx.py assets/audio/sfx

Writes short mono 22 kHz WAVs (small, instant to decode on phones) and a
looping engine OGG. Screams and other voices come from a generator instead.
"""
import os, sys, wave
import numpy as np

SR = 22050
rng = np.random.default_rng(7)


def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(n, attack=0.002, decay=0.2):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    return a * np.exp(-x / max(decay, 1e-4))


def lowpass(x, cutoff):
    alpha = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = alpha * acc + (1 - alpha) * v
        y[i] = acc
    return y


def noise(seconds):
    return rng.uniform(-1, 1, int(SR * seconds))


def thump(seconds, f0, f1, decay):
    x = t(seconds)
    freq = f1 + (f0 - f1) * np.exp(-x * 30)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * env(len(x), 0.001, decay)


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def save(path, x):
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def gunshot(kind):
    d = {"pistol": (0.35, 2600, 0.05, 140), "rifle": (0.45, 3200, 0.06, 110), "shotgun": (0.7, 1800, 0.12, 80)}[kind]
    length, cut, crack_decay, boom = d
    crack = lowpass(noise(length), cut) * env(int(SR * length), 0.0005, crack_decay)
    body = thump(length, boom * 3, boom, 0.09) * 0.9
    tail = lowpass(noise(length), 900) * env(int(SR * length), 0.01, length * 0.5) * 0.35
    return norm(crack * 1.4 + body + tail)


def punch(heavy):
    length = 0.28 if heavy else 0.18
    body = thump(length, 220 if heavy else 300, 60, 0.07 if heavy else 0.045)
    slap = lowpass(noise(length), 2500) * env(int(SR * length), 0.0005, 0.02)
    return norm(body * (1.3 if heavy else 1.0) + slap * 0.8)


def whoosh():
    length = 0.3
    n = noise(length)
    sweep = np.sin(np.linspace(0, np.pi, len(n))) ** 2
    return norm(lowpass(n, 1400) * sweep, 0.6)


def explosion():
    length = 1.8
    rumble = lowpass(noise(length), 300) * env(int(SR * length), 0.005, 0.6)
    crack = lowpass(noise(length), 3000) * env(int(SR * length), 0.001, 0.08)
    return norm(rumble * 1.6 + crack + thump(length, 120, 35, 0.4))


def surge():
    x = t(0.9)
    sweep = np.sin(2 * np.pi * np.cumsum(80 + 900 * x) / SR)
    zap = lowpass(noise(0.9), 4000) * 0.4
    return norm((sweep + zap) * env(len(x), 0.02, 0.35) + thump(0.9, 160, 40, 0.3))


def skid():
    length = 1.2
    x = t(length)
    tone = np.sin(2 * np.pi * (900 + 60 * np.sin(2 * np.pi * 7 * x)) * x)
    hiss = lowpass(noise(length), 3500)
    fade = np.minimum(1, np.minimum(x / 0.05, (length - x) / 0.05))
    return norm((tone * 0.5 + hiss * 0.5) * fade, 0.5)


def crash():
    length = 0.9
    metal = sum(np.sin(2 * np.pi * f * t(length)) for f in (420, 655, 1130, 1720)) * env(int(SR * length), 0.001, 0.25)
    bang = lowpass(noise(length), 2000) * env(int(SR * length), 0.001, 0.12)
    return norm(metal * 0.4 + bang + thump(length, 150, 50, 0.15))


def footstep():
    return norm(lowpass(noise(0.12), 900) * env(int(SR * 0.12), 0.002, 0.03) + thump(0.12, 120, 60, 0.03) * 0.5, 0.5)


def click():
    return norm(thump(0.06, 1800, 900, 0.01), 0.5)


def reload():
    a = lowpass(noise(0.08), 5000) * env(int(SR * 0.08), 0.001, 0.015)
    gap = np.zeros(int(SR * 0.18))
    return norm(np.concatenate([a, gap, a * 1.2]), 0.6)


def engine_loop():
    # One second, seamless: harmonics of a 4-cylinder at idle-ish rpm.
    x = t(1.0)
    base = 36.0   # Hz, whole number of cycles per second -> loops cleanly
    wave_ = sum((0.9 / k) * np.sin(2 * np.pi * base * k * x + k) for k in (1, 2, 3, 4, 6))
    rumble = lowpass(rng.uniform(-1, 1, len(x)), 200) * 0.3
    return norm(np.tanh(wave_ * 1.5) + rumble, 0.6)


def siren():
    x = t(2.0)
    f = 700 + 450 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.5 * x - np.pi / 2))
    return norm(np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sin(4 * np.pi * np.cumsum(f) / SR), 0.5)


def main(out):
    os.makedirs(out, exist_ok=True)
    sounds = {
        "gun_pistol": gunshot("pistol"), "gun_rifle": gunshot("rifle"), "gun_shotgun": gunshot("shotgun"),
        "punch_light": punch(False), "punch_heavy": punch(True), "whoosh": whoosh(),
        "explosion": explosion(), "surge": surge(), "skid": skid(), "crash": crash(),
        "footstep": footstep(), "click": click(), "reload": reload(),
    }
    for name, data in sounds.items():
        save(os.path.join(out, name + ".wav"), data)
    for name, data in {"engine_loop": engine_loop(), "siren_loop": siren()}.items():
        tmp = os.path.join(out, name + "_tmp.wav")
        save(tmp, data)
        os.system(f'ffmpeg -loglevel error -y -i "{tmp}" -c:a libvorbis -q:a 4 "{os.path.join(out, name + ".ogg")}"')
        os.remove(tmp)
    print("wrote", len(sounds) + 2, "sounds to", out)


if __name__ == "__main__":
    main(sys.argv[1])

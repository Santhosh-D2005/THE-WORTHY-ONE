"""Generates every sound of THE WORTHY ONE (Milestone 1.18). All sounds are ORIGINAL: synthesised here from noise and sine waves, with no
samples, recordings or third-party material, so they carry no licence obligations (released CC0 / public domain by the project).

    python tools/make_audio.py            (writes assets/audio/*.wav, 22.05 kHz, 16-bit, mono)

Design rule: quiet, dark, natural. Short wooden ticks, soft stone thumps, one clear steel ring, a low two-note chime, a slow forest wind.
Peaks are kept low (the game also sets a volume per cue) and every sound starts and ends at zero so nothing clicks.
Seeds are fixed: running the script again produces identical files.
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'audio')
rng = np.random.default_rng(1815)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def one_pole_lowpass(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def bandpass(x, low_alpha, high_alpha):
    """Rough band: the difference of two one-pole low-passes (keeps the part between the two corner frequencies)."""
    return one_pole_lowpass(x, high_alpha) - one_pole_lowpass(x, low_alpha)


def fade_edges(x, attack=0.004, release=0.02):
    a = max(1, int(SR * attack))
    r = max(1, int(SR * release))
    x = x.copy()
    x[:a] *= np.linspace(0, 1, a)
    x[-r:] *= np.linspace(1, 0, r)
    return x


def normalise(x, peak):
    m = float(np.max(np.abs(x))) or 1.0
    return x * (peak / m)


def save(name, x):
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767).astype('<i2').tobytes()
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data)
    print('%-16s %.2f s  %6.1f KB' % (name, len(x) / SR, len(data) / 1024.0))


def thump(freq, seconds, noise_amount=0.25, decay=18.0):
    t = t_axis(seconds)
    body = np.sin(2 * np.pi * freq * t * (1.0 - 0.25 * t / seconds)) * np.exp(-decay * t)
    knock = one_pole_lowpass(rng.standard_normal(len(t)), 0.25) * np.exp(-60 * t) * noise_amount
    return body + knock


# ---- UI ----------------------------------------------------------------------------------------------
def ui_tap():
    t = t_axis(0.09)
    click = one_pole_lowpass(rng.standard_normal(len(t)), 0.35) * np.exp(-220 * t)
    tone = np.sin(2 * np.pi * 440 * t) * np.exp(-45 * t)
    return fade_edges(normalise(0.6 * click + 0.5 * tone, 0.45), 0.001, 0.02)


def ui_play():
    t = t_axis(0.55)
    a = np.sin(2 * np.pi * 196.0 * t) * np.exp(-6.0 * t)
    b = np.sin(2 * np.pi * 294.0 * t) * np.exp(-7.0 * t) * 0.6
    knock = thump(110, 0.55, 0.3, 14)
    return fade_edges(normalise(a + b + 0.7 * knock, 0.5), 0.003, 0.08)


# ---- Gameplay cues (already fired by LevelManager) ---------------------------------------------------
def tap():
    t = t_axis(0.07)
    tick = one_pole_lowpass(rng.standard_normal(len(t)), 0.22) * np.exp(-150 * t)
    wood = np.sin(2 * np.pi * 190 * t) * np.exp(-50 * t)
    return fade_edges(normalise(0.7 * tick + 0.6 * wood, 0.4), 0.001, 0.015)


def tap_slow():
    t = t_axis(0.12)
    wood = np.sin(2 * np.pi * 120 * t) * np.exp(-30 * t)
    tick = one_pole_lowpass(rng.standard_normal(len(t)), 0.1) * np.exp(-90 * t)
    return fade_edges(normalise(0.7 * wood + 0.4 * tick, 0.3), 0.002, 0.03)


def first_tap():
    return fade_edges(normalise(thump(88, 0.3, 0.3, 16), 0.5), 0.003, 0.05)


def planted():
    return fade_edges(normalise(thump(64, 0.45, 0.35, 12), 0.55), 0.003, 0.08)


def pull():
    """Steel dragged out of wood: filtered noise whose band rises, with a faint resonance that climbs, ending softly."""
    secs = 0.75
    t = t_axis(secs)
    noise = rng.standard_normal(len(t))
    low = bandpass(noise, 0.02, 0.18)
    high = bandpass(noise, 0.12, 0.45)
    mix = low * (1 - t / secs) + high * (t / secs)
    env = np.sin(np.pi * np.clip(t / secs, 0, 1)) ** 1.6
    sweep = np.sin(2 * np.pi * np.cumsum(520 + 900 * (t / secs) ** 1.5) / SR) * 0.18
    return fade_edges(normalise((mix + sweep) * env, 0.45), 0.01, 0.12)


def freed():
    """The blade comes free: one clear, restrained steel ring (inharmonic partials, long exponential decay) over a soft knock."""
    secs = 1.9
    t = t_axis(secs)
    ring = np.zeros(len(t))
    for freq, amp, decay in ((880.0, 1.0, 3.2), (1318.5, 0.6, 3.8), (2093.0, 0.32, 5.0), (3136.0, 0.14, 7.0)):
        ring += amp * np.sin(2 * np.pi * freq * t) * np.exp(-decay * t)
    knock = thump(150, secs, 0.2, 22)
    return fade_edges(normalise(ring * 0.8 + knock * 0.5, 0.45), 0.002, 0.25)


def level_complete():
    """Two soft bell tones, low in the register: A3 then E4. Calm, no fanfare."""
    secs = 2.4
    t = t_axis(secs)
    out = np.zeros(len(t))
    for start, freq, amp in ((0.0, 220.0, 1.0), (0.38, 329.6, 0.8)):
        local = np.clip(t - start, 0, None)
        env = (t >= start) * np.exp(-2.2 * local) * (1 - np.exp(-60 * local))
        out += amp * env * (np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2.0 * t) * np.exp(-3 * local))
    return fade_edges(normalise(out, 0.4), 0.004, 0.4)


def failure():
    """A low, slow sinking tone and a soft thump: the wood holds."""
    secs = 1.1
    t = t_axis(secs)
    sink = np.sin(2 * np.pi * np.cumsum(150 - 80 * (t / secs)) / SR) * np.exp(-2.6 * t) * (1 - np.exp(-30 * t))
    hush = one_pole_lowpass(rng.standard_normal(len(t)), 0.03) * np.exp(-4 * t) * 0.6
    knock = thump(70, secs, 0.2, 10)
    return fade_edges(normalise(sink + hush + 0.6 * knock, 0.45), 0.005, 0.25)


# ---- Forest ambience (loops seamlessly) -----------------------------------------------------------------
def ambience(loop_seconds=16.0, crossfade=1.5):
    total = loop_seconds + crossfade
    t = t_axis(total)
    n = len(t)
    noise = rng.standard_normal(n)
    rumble = one_pole_lowpass(noise, 0.008)                    # a very low, distant air movement
    wind = bandpass(rng.standard_normal(n), 0.015, 0.09)        # the body of the wind in the trees
    air = bandpass(rng.standard_normal(n), 0.08, 0.35)          # a little high air
    # slow swells whose periods divide the loop length, so they repeat exactly
    swell1 = 0.55 + 0.45 * np.sin(2 * np.pi * (1.0 / loop_seconds) * t + 0.7)
    swell2 = 0.60 + 0.40 * np.sin(2 * np.pi * (3.0 / loop_seconds) * t + 2.1)
    mix = rumble * 2.2 + wind * 1.6 * swell1 + air * 0.9 * swell2 * swell1
    # sparse, tiny leaf rustles (short, high, soft), placed at fixed random times
    rustle = np.zeros(n)
    for _ in range(int(loop_seconds * 0.9)):
        start = int(rng.uniform(0, loop_seconds) * SR)
        length = int(rng.uniform(0.03, 0.09) * SR)
        burst = bandpass(rng.standard_normal(length), 0.2, 0.55) * np.hanning(length) * rng.uniform(0.25, 0.6)
        end = min(n, start + length)
        rustle[start:end] += burst[:end - start]
    mix = mix + rustle * 0.9
    mix = normalise(mix, 0.35)
    # make the loop seamless: blend the extra tail into the head
    fade = int(crossfade * SR)
    loop_len = int(loop_seconds * SR)
    w = np.linspace(0.0, 1.0, fade)
    out = mix[:loop_len].copy()
    out[:fade] = mix[:fade] * w + mix[loop_len:loop_len + fade] * (1.0 - w)
    out[:int(0.002 * SR)] *= np.linspace(0, 1, int(0.002 * SR))  # (the file as a one-shot would start at 0; the loop itself is continuous)
    return out


if __name__ == '__main__':
    for name, fn in (('ui_tap', ui_tap), ('ui_play', ui_play), ('tap', tap), ('tap_slow', tap_slow), ('first_tap', first_tap),
                     ('planted', planted), ('pull', pull), ('freed', freed), ('level_complete', level_complete), ('failure', failure),
                     ('ambience', ambience)):
        save(name, fn())

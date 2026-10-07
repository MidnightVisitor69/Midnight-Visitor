"""Synthesizes every sound for the prototype. No samples, no downloads:
noise, sines and envelopes only (numpy + wave). Re-run to reproduce the WAVs
byte-identically (fixed seed). Output: 16-bit mono 44.1 kHz WAVs in
client/audio/ (one dir up from this script).

Mix targets sit deliberately under the independent guard limits
(pipeline/check_audio.py: peak <= -6 dBFS, rms <= -20 dBFS, <= 12% of energy
above 5 kHz, <= 3 s, 5 ms fade-in) so the sounds stay soft in a long session:
  E:/AI/ComfyUI/python_embeded/python.exe client/audio/src/make_sounds.py
"""
import os
import wave

import numpy as np

SR = 44100
OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))
MASTER_SEED = 20261007


# ---------------------------------------------------------------- helpers

def n_of(dur_s):
    return int(round(SR * dur_s))


def db(x):
    return 20.0 * np.log10(max(float(x), 1e-9))


def noise(n, rng):
    return rng.standard_normal(n)


def sin2_ramp(n):
    """0 -> 1 raised-cosine; gentle slopes keep clicks out."""
    x = np.linspace(0.0, 1.0, n)
    return np.sin(np.pi * 0.5 * x) ** 2


def shape(n, attack_s, release_s):
    """Raised-cosine attack/release around a sustain of 1."""
    e = np.ones(n)
    a, r = n_of(attack_s), n_of(release_s)
    if a > 0:
        e[:a] = sin2_ramp(a)
    if r > 0:
        e[n - r:] *= sin2_ramp(r)[::-1]
    return e


def fft_gain_filter(x, gain_fn):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    return np.fft.irfft(spec * gain_fn(freqs), len(x))


def lp_gain(fc, edge):
    def g(f):
        out = np.zeros_like(f)
        out[f <= fc] = 1.0
        mid = (f > fc) & (f < fc + edge)
        out[mid] = 0.5 + 0.5 * np.cos(np.pi * (f[mid] - fc) / edge)
        return out
    return g


def hp_gain(fc, edge):
    def g(f):
        out = np.ones_like(f)
        out[f <= fc - edge] = 0.0
        mid = (f > fc - edge) & (f < fc)
        out[mid] = 0.5 - 0.5 * np.cos(np.pi * (f[mid] - (fc - edge)) / edge)
        return out
    return g


def fft_lp(x, fc, edge=600.0):
    return fft_gain_filter(x, lp_gain(fc, edge))


def fft_hp(x, fc, edge=300.0):
    return fft_gain_filter(x, hp_gain(fc, edge))


def place(buf, sig, at_s):
    off = n_of(at_s)
    end = min(len(buf), off + len(sig))
    buf[off:end] += sig[: end - off]


def finalize(name, x, rms_db, peak_cap_db=-8.0):
    """DC removal, guaranteed fade-in/out (click guard), then loudness:
    scale = min(what the rms target allows, what the peak cap allows)."""
    x = x - np.mean(x)
    x = x * shape(len(x), 0.008, 0.015)
    peak = np.abs(x).max()
    rms = np.sqrt(np.mean(x ** 2))
    scale = min(10.0 ** (rms_db / 20.0) / max(rms, 1e-9),
                10.0 ** (peak_cap_db / 20.0) / max(peak, 1e-9))
    x = x * scale
    path = os.path.join(OUT_DIR, name + ".wav")
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    spec = np.abs(np.fft.rfft(x)) ** 2
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    hi = spec[freqs >= 5000.0].sum() / max(spec.sum(), 1e-12)
    print("%-22s %4.2fs peak %5.1f rms %5.1f hi %4.1f%%" % (
        name, len(x) / SR, db(np.abs(x).max()), db(np.sqrt(np.mean(x ** 2))), hi * 100.0))


# ---------------------------------------------------------------- building blocks

def thock(dur, f0=220.0, drop=0.22, tau=0.018, attack=0.012, harm2=0.25):
    """Damped low sine with a fast pitch settle: the 'felt mallet on card stock'."""
    n = n_of(dur)
    tt = np.arange(n) / SR
    f_inst = f0 * (1.0 - drop * (1.0 - np.exp(-tt / 0.008)))
    phase = 2.0 * np.pi * np.cumsum(f_inst) / SR
    env = shape(n, attack, min(0.02, dur * 0.4)) * np.exp(-tt / tau)
    return (np.sin(phase) + harm2 * np.sin(2.0 * phase)) * env


def mallet(dur, f0, partials, attack=0.012):
    """Struck bar: each partial (ratio, amp, tau) decays on its own."""
    n = n_of(dur)
    tt = np.arange(n) / SR
    x = np.zeros(n)
    for ratio, amp, tau in partials:
        x += amp * np.sin(2.0 * np.pi * f0 * ratio * tt) * np.exp(-tt / tau)
    return x * shape(n, attack, min(0.35 * dur, 0.4))


def pad(dur, notes, attack, release, rng, trem_hz=0.0, trem_depth=0.0,
        detune=0.0, partials=((1.0, 1.0),)):
    """Warm chord swell. notes: [(freq, rel_amp)]. detune adds a slow chorus."""
    n = n_of(dur)
    tt = np.arange(n) / SR
    x = np.zeros(n)
    for freq, namp in notes:
        for ratio, ramp in partials:
            voices = [(1.0, 1.0)]
            if detune > 0.0:
                voices.append((1.0 + detune, 0.55))
            for det, damp in voices:
                ph = 2.0 * np.pi * freq * ratio * det * tt + rng.uniform(0.0, 2.0 * np.pi)
                v = np.sin(ph)
                if trem_hz > 0.0:
                    tph = rng.uniform(0.0, 2.0 * np.pi)
                    v = v * (1.0 - trem_depth * (0.5 + 0.5 * np.sin(2.0 * np.pi * trem_hz * tt + tph)))
                x += namp * ramp * damp * v
    return x * shape(n, attack, release)


def bell(dur, f0, attack=0.012):
    """Soft chime: slightly inharmonic low partials, all kept under 5 kHz."""
    n = n_of(dur)
    tt = np.arange(n) / SR
    x = (np.sin(2.0 * np.pi * f0 * tt) * np.exp(-tt / 0.38)
         + 0.22 * np.sin(2.0 * np.pi * f0 * 2.76 * tt) * np.exp(-tt / 0.15)
         + 0.07 * np.sin(2.0 * np.pi * f0 * 5.40 * tt) * np.exp(-tt / 0.06))
    return x * shape(n, attack, min(0.03, dur * 0.3))


def crackle_env(n, density_per_s, rng):
    """Sparse random spikes smoothed into a bumpy 0..1 envelope (foil crunch)."""
    spikes = np.zeros(n)
    count = max(1, int(n / SR * density_per_s))
    idx = rng.integers(0, n, count)
    spikes[idx] = rng.uniform(0.3, 1.0, count)
    env = fft_lp(spikes, 500.0, 400.0)
    env -= env.min()
    return env / max(env.max(), 1e-9)


# ---------------------------------------------------------------- sounds

def make_pack_rustle(dur, lobes, lp, rng, name):
    n = n_of(dur)
    tt = np.arange(n) / SR
    x = fft_lp(fft_hp(noise(n, rng), 300.0), lp, 900.0)
    env = np.zeros(n)
    for center, width, amp in lobes:
        m = np.abs(tt - center) < width * 0.5
        env[m] += amp * np.cos(np.pi * (tt[m] - center) / width) ** 2
    tex = fft_lp(noise(n, rng), 25.0, 15.0)
    tex /= max(np.abs(tex).max(), 1e-9)
    finalize(name, x * env * (0.8 + 0.3 * tex), -24.0)


def make_pack_tear(rng):
    dur = 0.62
    x = np.zeros(n_of(dur))
    # Phase 1: foil crinkle under tension.
    n1 = n_of(0.45)
    c = fft_lp(fft_hp(noise(n1, rng), 250.0), 3400.0, 1000.0)
    tension = shape(n1, 0.09, 0.18) * (0.35 + 0.65 * crackle_env(n1, 90.0, rng))
    place(x, c * tension, 0.0)
    # Phase 2: the release: pitch-dropping low whoomp + a breath of air.
    nw = n_of(0.26)
    tt = np.arange(nw) / SR
    f_inst = 55.0 + 60.0 * np.exp(-tt / 0.07)
    phase = 2.0 * np.pi * np.cumsum(f_inst) / SR
    wenv = shape(nw, 0.015, 0.10) * np.exp(-tt / 0.09)
    place(x, np.sin(phase) * wenv, 0.36)
    breath = fft_lp(noise(nw, rng), 700.0, 300.0) * wenv
    place(x, breath * 0.45, 0.36)
    finalize("pack_tear", x, -21.5)


def make_card_slide(dur, f_lo, f_hi, sweep_up, rng, name):
    n = n_of(dur)
    base = fft_hp(noise(n, rng), 250.0)
    low = fft_lp(base, f_lo, 400.0)
    high = fft_lp(base, f_hi, 900.0)
    w = sin2_ramp(n)
    if not sweep_up:
        w = w[::-1]
    y = (1.0 - w) * low + w * high  # moving filter = the 'brush' travelling
    a = int(n * 0.35)
    env = np.ones(n)
    env[:a] = sin2_ramp(a)
    env[a:] = sin2_ramp(n - a)[::-1]
    finalize(name, y * env, -23.0)


def make_card_flip(dur, f0, rng, name):
    x = np.zeros(n_of(dur))
    flick = fft_lp(fft_hp(noise(n_of(0.04), rng), 400.0), 3000.0, 800.0)
    flick *= shape(len(flick), 0.010, 0.025)
    place(x, flick * 0.5, 0.0)
    place(x, thock(dur - 0.025, f0=f0, tau=0.030, attack=0.010, harm2=0.30), 0.025)
    finalize(name, x, -22.0)


def make_reveals(rng):
    # Same root (A) and same loudness across rarities: only harmonic richness
    # and tail length grow. A3=220, C#4=277.18, E4=329.63, A4=440, E5=659.26.
    rare = (mallet(1.0, 220.0, ((1, 1.0, 0.50), (2, 0.35, 0.22), (3, 0.12, 0.10)))
            + 0.40 * pad(1.0, [(220.0, 1.0), (329.63, 0.8)], 0.25, 0.40, rng,
                         trem_hz=4.5, trem_depth=0.12))
    finalize("reveal_rare", rare, -24.0, peak_cap_db=-7.0)

    epic = (mallet(1.5, 220.0, ((1, 1.0, 0.70), (2, 0.40, 0.35), (3, 0.18, 0.18), (4, 0.08, 0.08)))
            + 0.45 * pad(1.5, [(220.0, 1.0), (277.18, 0.9), (329.63, 0.85)], 0.30, 0.70, rng,
                         trem_hz=4.0, trem_depth=0.15, detune=0.0012,
                         partials=((1, 1.0), (2, 0.18))))
    finalize("reveal_epic", epic, -24.0, peak_cap_db=-7.0)

    leg = (mallet(2.3, 220.0, ((1, 1.0, 1.00), (2, 0.45, 0.55), (3, 0.22, 0.30), (4, 0.10, 0.15)))
           + 0.50 * pad(2.3, [(110.0, 0.55), (220.0, 1.0), (277.18, 0.9), (329.63, 0.85),
                              (440.0, 0.6), (659.26, 0.35)],
                        0.45, 1.00, rng, trem_hz=3.5, trem_depth=0.18, detune=0.0015,
                        partials=((1, 1.0), (2, 0.22), (3, 0.08))))
    finalize("reveal_legendary", leg, -24.0, peak_cap_db=-7.0)


def make_holo_shimmer(rng):
    notes = [(440.0, 1.0), (554.37, 0.8), (659.26, 0.7), (880.0, 0.5)]
    x = 0.25 * pad(1.1, notes, 0.35, 0.45, rng, trem_hz=3.0, trem_depth=0.35, detune=0.004)
    finalize("holo_shimmer", x, -27.0, peak_cap_db=-10.0)


def make_acquire(rng):
    x = np.zeros(n_of(0.6))
    place(x, 0.8 * thock(0.30, f0=190.0, tau=0.040, attack=0.012, harm2=0.20), 0.0)
    place(x, thock(0.30, f0=250.0, tau=0.050, attack=0.010, harm2=0.20), 0.13)
    tail = mallet(0.45, 220.0, ((1, 0.40, 0.35), (1.5, 0.20, 0.25)), attack=0.02)
    place(x, tail, 0.13)
    finalize("acquire", x, -23.0)


def make_tap(dur, f0, tau, rng, name):
    x = thock(dur, f0=f0, tau=tau, attack=0.012, harm2=0.22)
    tick = fft_lp(noise(n_of(0.008), rng), 2200.0, 600.0) * shape(n_of(0.008), 0.008, 0.003)
    place(x, tick * 0.10, 0.0)
    finalize(name, x, -22.0)


def make_gems(rng):
    dur = 0.75
    x = np.zeros(n_of(dur))
    notes = [(329.63, 0.90, 0.00), (392.00, 0.80, 0.09), (493.88, 1.00, 0.18), (659.26, 0.85, 0.27)]
    for f0, amp, at in notes:
        place(x, amp * bell(dur - at, f0), at)
    finalize("gems", x, -24.0)


def main():
    rng = np.random.default_rng(MASTER_SEED)
    make_pack_rustle(0.18, [(0.07, 0.12, 1.0), (0.14, 0.10, 0.7)], 2500.0, rng, "pack_rustle_1")
    make_pack_rustle(0.22, [(0.06, 0.10, 0.8), (0.14, 0.12, 1.0), (0.20, 0.08, 0.5)], 2900.0, rng, "pack_rustle_2")
    make_pack_rustle(0.26, [(0.08, 0.14, 0.9), (0.18, 0.14, 1.0)], 3200.0, rng, "pack_rustle_3")
    make_pack_tear(rng)
    make_card_slide(0.13, 700.0, 2400.0, True, rng, "card_slide_1")
    make_card_slide(0.15, 900.0, 2600.0, False, rng, "card_slide_2")
    make_card_slide(0.17, 600.0, 2100.0, True, rng, "card_slide_3")
    make_card_slide(0.19, 800.0, 2800.0, True, rng, "card_slide_4")
    make_card_flip(0.13, 195.0, rng, "card_flip_1")
    make_card_flip(0.15, 225.0, rng, "card_flip_2")
    make_card_flip(0.17, 255.0, rng, "card_flip_3")
    make_reveals(rng)
    make_holo_shimmer(rng)
    make_acquire(rng)
    make_tap(0.07, 245.0, 0.016, rng, "tap_1")
    make_tap(0.08, 275.0, 0.014, rng, "tap_2")
    make_tap(0.09, 215.0, 0.020, rng, "tap_3")
    make_gems(rng)


if __name__ == "__main__":
    main()

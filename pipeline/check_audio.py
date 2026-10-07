"""Independent guard for game sounds (the dev: nothing high-pitched, loud or annoying).
Usage: python check_audio.py <dir>   -> prints one line per file, exit 1 if any fails.
Limits are deliberately conservative for UI sounds heard hundreds of times a session."""
import sys, os, wave
import numpy as np

PEAK_MAX_DBFS = -6.0        # headroom: never clips, never jumps out of the mix
RMS_MAX_DBFS = -20.0        # perceived loudness ceiling
HIGH_HZ = 5000.0            # "high-pitched" band
HIGH_SHARE_MAX = 0.12       # at most 12% of spectral energy above 5 kHz
DURATION_MAX_S = 3.0        # UI sounds stay short (music/ambience is out of scope)
# Clicks: the first 5 ms may not already be at half the file's peak (needs a fade-in).


def db(x):
    return 20 * np.log10(max(x, 1e-9))


def load(path):
    with wave.open(path, "rb") as w:
        n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
    if sw != 2:
        raise ValueError(f"expected 16-bit PCM, got {sw * 8}-bit")
    a = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    return a, sr


def check(path):
    a, sr = load(path)
    problems = []
    dur = len(a) / sr
    peak, rms = db(np.abs(a).max()), db(np.sqrt(np.mean(a ** 2)))
    spec = np.abs(np.fft.rfft(a)) ** 2
    freqs = np.fft.rfftfreq(len(a), 1 / sr)
    high = spec[freqs >= HIGH_HZ].sum() / max(spec.sum(), 1e-12)
    head = a[: max(1, int(sr * 0.005))]
    if peak > PEAK_MAX_DBFS: problems.append(f"peak {peak:.1f} dBFS > {PEAK_MAX_DBFS}")
    if rms > RMS_MAX_DBFS: problems.append(f"rms {rms:.1f} dBFS > {RMS_MAX_DBFS}")
    if high > HIGH_SHARE_MAX: problems.append(f"{high:.0%} energy above {HIGH_HZ:.0f} Hz > {HIGH_SHARE_MAX:.0%}")
    if dur > DURATION_MAX_S: problems.append(f"duration {dur:.2f}s > {DURATION_MAX_S}s")
    if np.abs(head).max() > 0.5 * np.abs(a).max() and len(a) > sr * 0.05:
        problems.append("no fade-in: full level within the first 5 ms (clicky)")
    return dur, peak, rms, high, problems


def main(d):
    files = [os.path.join(r, f) for r, _, fs in os.walk(d) for f in fs if f.lower().endswith(".wav")]
    bad = 0
    for f in sorted(files):
        try:
            dur, peak, rms, high, probs = check(f)
        except Exception as e:
            print(f"FAIL {f}: {e}"); bad += 1; continue
        status = "FAIL" if probs else "OK  "
        bad += bool(probs)
        print(f"{status} {os.path.relpath(f, d)}  {dur:.2f}s peak {peak:.1f} rms {rms:.1f} hi {high:.0%}"
              + (" | " + "; ".join(probs) if probs else ""))
    print(f"AUDIO: {len(files)} files, {bad} failed")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main(sys.argv[1])

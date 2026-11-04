"""Peak-normalizes a mono 16-bit PCM WAV to -1 dBFS. usage: python3 -I normalize.py in.wav out.wav"""
import array, math, sys, wave
with wave.open(sys.argv[1]) as w:
    params, samples = w.getparams(), array.array("h", w.readframes(w.getnframes()))
peak = max(abs(s) for s in samples)
gain = 32767 * 10 ** (-1 / 20) / peak
print(f"{sys.argv[1]}: peak {20 * math.log10(peak / 32767):.1f} dBFS, gain {20 * math.log10(gain):+.1f} dB")
with wave.open(sys.argv[2], "wb") as w:
    w.setparams(params)
    w.writeframes(array.array("h", (max(-32768, min(32767, round(s * gain))) for s in samples)).tobytes())

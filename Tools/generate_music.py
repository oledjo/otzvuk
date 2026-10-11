#!/usr/bin/env python3
"""Синтезирует встроенные фоновые мелодии Otzvuk.

Все звуки создаются с нуля из синусоид и шума (без сторонних сэмплов), поэтому
у них нет внешних лицензионных ограничений. Каждая мелодия — бесшовный луп
длиной 60 секунд: хвост подмешивается в начало (кроссфейд), чтобы при
зацикливании не было щелчка.

Запуск:  python3 Tools/generate_music.py
Нужны: python3, numpy, afconvert (macOS).
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
LOOP_SECONDS = 60
XFADE_SECONDS = 6
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Otzvuk", "Resources", "Music")
rng = np.random.default_rng(20261011)


def lowpass_fft(x, cutoff_hz):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    spec *= 1.0 / (1.0 + (freqs / cutoff_hz) ** 4)
    return np.fft.irfft(spec, len(x))


def make_ir(seconds, decay, cutoff):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t / decay)
    ir = lowpass_fft(ir, cutoff)
    ir[0] = 0
    return ir / np.sqrt(np.sum(ir ** 2))


def reverb(x, ir, wet=0.65):
    n = len(x) + len(ir)
    size = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
    return (1 - wet) * x + wet * y


def pad(freqs, n, lfo_scale=1.0, detune=0.0015):
    """Мягкий пэд: каждая нота — несколько гармоник с медленным «дыханием»."""
    t = np.arange(n) / SR
    out = np.zeros((2, n))
    for i, f in enumerate(freqs):
        rate = (0.012 + 0.007 * ((i * 7) % 5)) * lfo_scale
        phase = rng.uniform(0, 2 * np.pi)
        env = 0.55 + 0.45 * np.sin(2 * np.pi * rate * t + phase)
        for ch, d in enumerate((1 - detune, 1 + detune)):
            ph = rng.uniform(0, 2 * np.pi)
            tone = (
                np.sin(2 * np.pi * f * d * t + ph)
                + 0.35 * np.sin(2 * np.pi * 2 * f * d * t + ph * 1.3)
                + 0.12 * np.sin(2 * np.pi * 3 * f * d * t + ph * 0.7)
            )
            out[ch] += tone * env / (1 + 0.15 * i)
    return out


def water(n, level):
    """Тихий шум воды: фильтрованный шум с медленной модуляцией."""
    t = np.arange(n) / SR
    out = np.zeros((2, n))
    for ch in range(2):
        noise = lowpass_fft(rng.standard_normal(n), 900)
        mod = 0.6 + 0.4 * np.sin(2 * np.pi * (0.07 + 0.02 * ch) * t + rng.uniform(0, 6.28))
        out[ch] = noise * mod * level
    return out


def seamless(stereo, loop_n, xfade_n):
    """Из сигнала длиной loop_n + xfade_n делает бесшовный луп длиной loop_n."""
    head = stereo[:, :loop_n].copy()
    tail = stereo[:, loop_n : loop_n + xfade_n]
    fade_in = np.sin(np.linspace(0, np.pi / 2, xfade_n)) ** 1
    fade_out = np.cos(np.linspace(0, np.pi / 2, xfade_n))
    head[:, :xfade_n] = head[:, :xfade_n] * fade_in + tail * fade_out
    return head


def finish(stereo, target_rms=0.07):
    stereo = stereo - stereo.mean(axis=1, keepdims=True)
    rms = np.sqrt(np.mean(stereo ** 2))
    stereo = stereo * (target_rms / rms)
    peak = np.max(np.abs(stereo))
    if peak > 0.85:
        stereo *= 0.85 / peak
    return stereo


def write_m4a(stereo, name):
    pcm = (np.clip(stereo.T, -1, 1) * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, name + ".wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        out = os.path.join(OUT_DIR, name + ".m4a")
        subprocess.run(["afconvert", wav_path, out, "-f", "m4af", "-d", "aac", "-b", "128000"], check=True)
    print(f"{name}: rms={np.sqrt(np.mean(stereo**2)):.3f} peak={np.max(np.abs(stereo)):.3f} -> {out}")


TRACKS = {
    # Cmaj9: тёплый, светлый
    "dawn": dict(freqs=[130.81, 196.00, 329.63, 493.88, 587.33], water=0.0, ir=(3.2, 1.6, 3500)),
    # Am7sus: спокойный, с лёгким шумом воды
    "water": dict(freqs=[110.00, 164.81, 220.00, 261.63, 392.00], water=0.55, ir=(3.6, 1.8, 3000)),
    # D–A–D–F#: глубокий низкий дрон
    "calm": dict(freqs=[73.42, 110.00, 146.83, 185.00, 220.00], water=0.0, ir=(4.0, 2.2, 2200)),
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    loop_n = LOOP_SECONDS * SR
    xfade_n = XFADE_SECONDS * SR
    total = loop_n + xfade_n
    for name, cfg in TRACKS.items():
        sig = pad(cfg["freqs"], total, lfo_scale=1.0)
        if cfg["water"] > 0:
            sig = sig + water(total, cfg["water"] * 1.2)
        secs, decay, cutoff = cfg["ir"]
        ir = make_ir(secs, decay, cutoff)
        sig = np.stack([reverb(sig[0], ir), reverb(sig[1], make_ir(secs, decay, cutoff))])
        loop = seamless(sig, loop_n, xfade_n)
        write_m4a(finish(loop), name)


if __name__ == "__main__":
    main()

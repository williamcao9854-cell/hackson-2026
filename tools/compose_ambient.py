#!/usr/bin/env python3
"""
合成物灵的背景音乐：古筝、古琴般的拨弦 + 刮奏 + 泛音 + 风铃、鸟鸣、水声，再加一个雨声层。

- 全部用代码合成，没有采样、没有版权素材，结果可复现（固定随机种子）
- 五声音阶：白天、夜里都是 D 宫（D E F♯ A B，明亮、不忧伤），夜里慢一些、低一些，像摇篮曲；
  和 App 里点水面的音（RitualSynth.waterScale，同样是 D E F♯ A B）是同一组音，怎么点都和得上
- 每一层都按循环长度做成"首尾相接"：音符的余音、混响的尾巴都绕回开头，
  AVAudioPlayer numberOfLoops = -1 循环播放时听不到接缝

用法（在仓库根目录）：
    python3 -m pip install numpy      # 只需一次
    python3 tools/compose_ambient.py
输出：Wuling/Resources/Sounds/ambient-day.wav、ambient-night.wav、ambient-rain.wav
（22.05 kHz、单声道、16-bit PCM：外放足够，且 AVAudioPlayer 循环无缝）
"""
import os
import wave

import numpy as np

SR = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Wuling", "Resources", "Sounds")

# 十二平均律，A4 = 440
def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)

D_GONG = [62, 64, 66, 69, 71]   # D4 E4 F#4 A4 B4（宫 商 角 徵 羽）


def scale_notes(low, high):
    """low..high（MIDI）之间所有属于 D E F# A B 的音"""
    pcs = {n % 12 for n in D_GONG}
    return [m for m in range(low, high + 1) if m % 12 in pcs]


# MARK: - 乐器

def pluck(f0, length, rng, gain=1.0, decay=3.0, slide=0.0, vibrato=0.0, brightness=1.0):
    """
    一声拨弦（加法合成）：
    - 泛音按 1/k 递减、高泛音衰减更快，略带弦的非谐性
    - slide：从低一点的地方滑进这个音（绰），vibrato：按音后的揉弦（吟猱）
    - 起音处一小撮低通噪声，是指甲触弦的声音
    """
    n = int(length * SR)
    t = np.arange(n) / SR
    bend = 1 - slide * np.exp(-t / 0.09)
    wobble = 1 + vibrato * np.sin(2 * np.pi * 5.2 * t + rng.uniform(0, 6.28)) * np.clip((t - 0.25) / 0.6, 0, 1) * np.exp(-t / 2.5)
    phase = 2 * np.pi * np.cumsum(f0 * bend * wobble) / SR
    out = np.zeros(n)
    pluck_pos = rng.uniform(0.12, 0.2)
    for k in range(1, 11):
        if f0 * k > SR * 0.45:
            break
        amp = abs(np.sin(np.pi * k * pluck_pos)) / k ** (1.15 / brightness)
        tau = decay / (1 + 0.55 * (k - 1))
        inharm = 1 + 0.00025 * k * k
        out += amp * np.sin(k * phase * inharm) * np.exp(-t / tau)
    attack = np.clip(t / 0.003, 0, 1)
    out *= attack
    # 触弦的"嚓"
    m = min(n, int(0.012 * SR))
    burst = rng.standard_normal(m) * np.exp(-np.arange(m) / (0.0025 * SR))
    burst = np.convolve(burst, np.ones(6) / 6, mode="same")
    out[:m] += burst * 0.08
    return out * gain


def harmonic(f0, length, gain=1.0, decay=4.0):
    """泛音：轻点弦上的徽位，清亮如钟，几乎只有基音"""
    n = int(length * SR)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * f0 * t) + 0.08 * np.sin(2 * np.pi * 2 * f0 * t) * np.exp(-t / 0.6)
    out *= np.exp(-t / decay) * np.clip(t / 0.004, 0, 1)
    return out * gain


def drip(f0, length, gain=1.0):
    """远处一滴水：音高往上跳的一个短气泡"""
    n = int(length * SR)
    t = np.arange(n) / SR
    f = f0 * (0.6 + 0.6 * np.clip(t / 0.04, 0, 1))
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * np.exp(-t / 0.05) * np.clip(t / 0.002, 0, 1) * gain


def periodic_noise(n, rng, shape):
    """在频域里造噪声：天生首尾相接。shape(freqs) 给出每个频率的幅度"""
    freqs = np.fft.rfftfreq(n, 1 / SR)
    spectrum = shape(freqs) * np.exp(1j * rng.uniform(0, 2 * np.pi, len(freqs)))
    spectrum[0] = 0
    x = np.fft.irfft(spectrum, n)
    return x / (np.std(x) + 1e-12)


def periodic_lfo(n, cycles, phase=0.0):
    """在循环长度里正好走完整数圈的慢速起伏"""
    t = np.arange(n) / n
    return np.sin(2 * np.pi * cycles * t + phase)


def place(buffer, sound, start):
    """把一个声音放进循环里，超出结尾的部分绕回开头"""
    n = len(buffer)
    i = int(start * SR) % n
    end = i + len(sound)
    if end <= n:
        buffer[i:end] += sound
    else:
        first = n - i
        buffer[i:] += sound[:first]
        rest = sound[first:]
        while len(rest) > 0:
            take = min(n, len(rest))
            buffer[:take] += rest[:take]
            rest = rest[take:]


def reverb(dry, rng, seconds, wet, predelay=0.025):
    """
    混响：用指数衰减的噪声当冲激响应，高频比低频散得快（像木结构的屋子）。
    用循环卷积（FFT），尾巴自然绕回开头。
    """
    n = len(dry)
    m = int(seconds * SR)
    t = np.arange(m) / SR
    noise = rng.standard_normal(m)
    spec = np.fft.rfft(noise)
    freqs = np.fft.rfftfreq(m, 1 / SR)
    bands = [(0, 600, 1.0), (600, 2500, 0.7), (2500, SR, 0.45)]
    ir = np.zeros(m)
    for lo, hi, scale in bands:
        mask = (freqs >= lo) & (freqs < hi)
        band = np.fft.irfft(spec * mask, m)
        rt60 = seconds * 0.55 * scale
        ir += band * np.exp(-6.9 * t / rt60)
    pd = int(predelay * SR)
    ir = np.concatenate([np.zeros(pd), ir])[:m]
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    padded = np.zeros(n)
    take = min(n, m)
    padded[:take] = ir[:take]
    wet_signal = np.fft.irfft(np.fft.rfft(dry) * np.fft.rfft(padded), n)
    return dry * (1 - wet * 0.5) + wet_signal * wet


def soft_limit(x, peak=0.89):
    x = x / (np.max(np.abs(x)) + 1e-12)
    x = np.tanh(x * 1.4) / np.tanh(1.4)
    return x * peak


# MARK: - 曲子

def chirp(rng, gain):
    """一声鸟鸣：两三下很快的上挑"""
    n = int(0.36 * SR)
    out = np.zeros(n)
    f0 = rng.uniform(2600, 3500)
    for k in range(rng.integers(2, 4)):
        start = int(k * 0.085 * SR)
        m = int(0.06 * SR)
        t = np.arange(m) / SR
        f = f0 * (1 + 0.35 * np.sin(np.pi * t / 0.06)) * (1 + 0.06 * k)
        phase = 2 * np.pi * np.cumsum(f) / SR
        out[start:start + m] += np.sin(phase) * np.sin(np.pi * t / 0.06) ** 2
    return out * gain


def chime(rng, notes, gain):
    """风过时一小串风铃：三四个高音错落着响"""
    out = np.zeros(int(2.4 * SR))
    for k in range(rng.integers(3, 5)):
        f = hz(rng.choice(notes))
        place(out, harmonic(f, 2.0, gain=gain * rng.uniform(0.6, 1.0), decay=0.9), k * rng.uniform(0.09, 0.16))
    return out


def compose(mood, seconds, seed):
    """
    白天、夜里都用 D 宫（D E F♯ A B，明亮的五声音阶），和 App 里点水面的音是同一组：
    - 一句是一个小动机，重复一遍（第二遍挪一挪位置），最后落回宫音或徵音
    - 句首有时来一串古筝式的上行刮奏，句尾偶尔点一个泛音
    - 白天轻快些，远处有几声鸟鸣；夜里慢一些、低一些，像摇篮曲
    """
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    strings = np.zeros(n)
    night = mood == "night"

    if night:
        scale = scale_notes(57, 83)       # A3 … B5
        beat, rest_range = 0.5, (2.4, 4.2)
        decay, brightness, gain_range = 2.8, 1.05, (0.45, 0.65)
        gliss_chance, bass_notes = 0.15, [50, 45]
    else:
        scale = scale_notes(62, 88)       # D4 … E6
        beat, rest_range = 0.38, (1.8, 3.2)
        decay, brightness, gain_range = 2.2, 1.25, (0.55, 0.78)
        gliss_chance, bass_notes = 0.3, [50, 57]
    home = [i for i, m in enumerate(scale) if m % 12 in (2, 9)]          # 宫（D）、徵（A）
    # 动机：在五声音阶上的级进与小跳，多数往上走
    motifs = [[0, 1, 2, 4], [0, 2, 1, 2], [0, 1, 2, 1], [2, 1, 2, 4], [0, 2, 4, 2], [1, 2, 4, 5], [0, 1, 0, 2]]
    rhythms = [[1, 1, 2, 2], [1, 1, 1, 2], [0.5, 0.5, 1, 2], [1, 0.5, 0.5, 2], [1, 1, 0.5, 1.5]]
    events = []

    def pluck_at(index, t, gain, length=4.5, d=decay):
        midi = scale[int(np.clip(index, 0, len(scale) - 1))]
        place(strings, pluck(hz(midi), length, rng, gain=gain, decay=d, brightness=brightness), t)
        events.append((t, midi))
        return midi

    t = rng.uniform(0.3, 0.8)
    while True:
        motif = motifs[rng.integers(len(motifs))]
        rhythm = rhythms[rng.integers(len(rhythms))]
        phrase_len = beat * (2 * sum(rhythm) + 3) + 0.6
        if t + phrase_len > seconds - 0.8:
            break
        start = home[rng.integers(0, max(1, len(home) // 2 + 1))]

        # 句首：一根低音空弦，再往上带一个五度
        bass = bass_notes[rng.integers(len(bass_notes))]
        place(strings, pluck(hz(bass), 5.0, rng, gain=0.32, decay=decay * 1.3, brightness=0.9), t)
        place(strings, pluck(hz(bass + 7), 4.0, rng, gain=0.22, decay=decay * 1.1, brightness=0.9), t + beat)
        # 古筝式的刮奏：从下往上一串，很快
        if rng.random() < gliss_chance:
            for k in range(7):
                pluck_at(start - 6 + k, t + 0.055 * k, 0.12 + 0.03 * k, length=2.0, d=1.1)
            t += 0.5

        # 动机两遍：第二遍挪个位置，节奏略变
        for rep in range(2):
            shift = 0 if rep == 0 else int(rng.choice([1, 2, -1]))
            for k, step in enumerate(motif):
                pluck_at(start + shift + step, t, rng.uniform(*gain_range))
                t += beat * rhythm[k % len(rhythm)] * (1 if rep == 0 else rng.choice([1, 1, 0.75]))
        # 落回宫音或徵音，余音长一点；有时在上面点一个泛音
        last = min(home, key=lambda i: abs(i - (start + 2)))
        midi = pluck_at(last, t, gain_range[1], length=6.0, d=decay * 1.5)
        if rng.random() < (0.55 if night else 0.35):
            f = hz(midi + 12)
            while f > 1900:
                f /= 2
            place(strings, harmonic(f, 4.0, gain=0.16, decay=2.2), t + beat * 1.5)
        t += beat * 3 + rng.uniform(*rest_range)

    # 远处：几滴水、一两串风铃；白天还有几声鸟鸣
    extras = np.zeros(n)
    water_notes = [hz(m) for m in scale_notes(86, 98)]
    for _ in range(int(seconds / (9 if night else 7))):
        place(extras, drip(rng.choice(water_notes), 0.4, gain=rng.uniform(0.04, 0.08)), rng.uniform(0, seconds))
    for _ in range(2 if night else 3):
        place(extras, chime(rng, scale_notes(86, 95), 0.06 if night else 0.07), rng.uniform(0, seconds))
    if not night:
        for _ in range(5):
            place(extras, chirp(rng, rng.uniform(0.025, 0.045)), rng.uniform(0, seconds))

    # 铺底：宫、角、徵（D、F♯、A，一个大三和弦）若有若无地呼吸，比只有五度暖
    drone = np.zeros(n)
    root = hz(62)
    for ratio, amp, cycles_lfo, phase in [(1, 1.0, 3, 0.3), (1.25, 0.45, 4, 1.7), (1.5, 0.6, 5, 2.9)]:
        cycles = round(root * ratio * seconds)
        lfo = 0.55 + 0.45 * periodic_lfo(n, cycles_lfo, phase)
        drone += amp * np.sin(2 * np.pi * cycles * np.arange(n) / n) * lfo

    # 水声：句与句之间也不空
    water = periodic_noise(n, rng, lambda f: np.where(f > 120, 1 / np.sqrt(np.maximum(f, 1)), 0) * np.exp(-((np.log(np.maximum(f, 1)) - np.log(560)) ** 2) / 1.2))
    water *= 0.7 + 0.3 * periodic_lfo(n, 5, 0.9) * periodic_lfo(n, 2, 0.2)

    mix = strings + extras + drone * (0.035 if night else 0.03) + water * (0.032 if night else 0.032)
    mix = reverb(mix, rng, seconds=3.0 if night else 2.2, wet=0.42 if night else 0.32)
    compose.events = events
    return soft_limit(mix, peak=0.85)


def rain(seconds, seed):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    # 雨幕：宽带、偏高的沙沙声
    hiss = periodic_noise(n, rng, lambda f: np.where(f > 300, 1 / np.maximum(f, 1) ** 0.35, 0) * np.exp(-((f / 7000) ** 2)))
    hiss *= 0.85 + 0.15 * periodic_lfo(n, 3, 0.4)
    # 落在瓦上、叶上的密密的雨点
    taps = np.zeros(n)
    for _ in range(int(seconds * 55)):
        m = int(0.006 * SR)
        click = rng.standard_normal(m) * np.exp(-np.arange(m) / (0.0012 * SR)) * rng.uniform(0.05, 0.25)
        place(taps, click, rng.uniform(0, seconds))
    # 偶尔一滴大的落进池子
    plops = np.zeros(n)
    notes = [hz(m) for m in scale_notes(74, 86)]
    for _ in range(int(seconds * 0.9)):
        place(plops, drip(rng.choice(notes), 0.4, gain=rng.uniform(0.1, 0.25)), rng.uniform(0, seconds))
    mix = hiss * 0.25 + taps + plops
    mix = reverb(mix, rng, seconds=1.6, wet=0.3)
    return soft_limit(mix, peak=0.8)


def write_wav(path, samples):
    data = (np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"✓ {os.path.relpath(path, ROOT)}  {len(samples) / SR:.1f}s  {os.path.getsize(path) / 1e6:.1f}MB")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    write_wav(os.path.join(OUT_DIR, "ambient-day.wav"), compose("day", 48, seed=2026))
    write_wav(os.path.join(OUT_DIR, "ambient-night.wav"), compose("night", 56, seed=1122))
    write_wav(os.path.join(OUT_DIR, "ambient-rain.wav"), rain(16, seed=7))


if __name__ == "__main__":
    main()

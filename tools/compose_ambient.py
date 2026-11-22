#!/usr/bin/env python3
"""
合成物灵的背景音乐：古琴般的拨弦 + 泛音 + 低低的空弦 + 水声，再加一个雨声层。

- 全部用代码合成，没有采样、没有版权素材，结果可复现（固定随机种子）
- 五声音阶：白天是 D 宫（D E F♯ A B），夜里是 B 羽（B D E F♯ A），
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

def compose(mood, seconds, seed):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    strings = np.zeros(n)
    night = mood == "night"

    if night:
        # 手机扬声器放不出 150Hz 以下：夜里只比白天低一点，靠更慢、更空来显得深
        melody = scale_notes(59, 81)      # B3 … A5
        home = [59, 71, 66, 78]           # B 与 F#：羽调的主音、属音
        gap_range, rest_range = (0.8, 1.9), (5.5, 9.0)
        phrase_range = (2, 5)
        decay_base = 4.2
    else:
        melody = scale_notes(62, 86)      # D4 … D6
        home = [62, 69, 74, 81]
        gap_range, rest_range = (0.45, 1.25), (3.2, 6.5)
        phrase_range = (3, 6)
        decay_base = 3.0

    t = rng.uniform(0.3, 1.2)
    index = rng.integers(len(melody) // 3, len(melody) // 2)
    while t < seconds - 2.0:
        # 一句的开头：低音区一根空弦，长长地响着
        open_string = (47 if night else 50) + rng.choice([0, 7, 12])   # B2 / D3 起的空弦，泛着五度、八度
        place(strings, pluck(hz(open_string), 7.0, rng, gain=0.45, decay=decay_base * 1.6, brightness=0.8), t)

        notes = rng.integers(*phrase_range, endpoint=True)
        for k in range(notes):
            # 五声音阶上的小步走，偶尔跳一下
            step = rng.choice([-2, -1, -1, 1, 1, 2, 3, -3], p=[0.1, 0.22, 0.13, 0.22, 0.13, 0.1, 0.05, 0.05])
            index = int(np.clip(index + step, 0, len(melody) - 1))
            last = k == notes - 1
            if last:
                # 句尾落在主音或属音上
                index = min(range(len(melody)), key=lambda i: min(abs(melody[i] - h) for h in home) * 10 + abs(i - index))
            midi = melody[index]
            f = hz(midi)
            slide = rng.choice([0, 0, 0.03, 0.06]) if not last else 0.0
            vibrato = 0.004 if last else rng.choice([0, 0, 0.002])
            place(strings, pluck(f, 6.0, rng, gain=rng.uniform(0.55, 0.85), decay=decay_base * (1.25 if last else 1.0),
                                 slide=slide, vibrato=vibrato), t)
            # 偶尔一个倚音
            if not last and rng.random() < 0.18:
                grace = melody[int(np.clip(index + 1, 0, len(melody) - 1))]
                place(strings, pluck(hz(grace), 2.5, rng, gain=0.3, decay=1.2), t - 0.11)
            t += rng.uniform(*gap_range) * (1.6 if last else 1.0)

        # 句尾有时点两个泛音，像余音飘到水面上
        if rng.random() < (0.75 if night else 0.55):
            for j, interval in enumerate(rng.choice([[12, 19], [19, 24], [12, 24]])):
                f = hz(melody[index] + interval)
                while f > 1900:   # 太高的泛音刺耳，折回低八度
                    f /= 2
                place(strings, harmonic(f, 6.0, gain=0.22, decay=3.2), t + 0.35 + j * 0.62)
        t += rng.uniform(*rest_range)

    # 远处几滴水
    water_notes = [hz(m) for m in scale_notes(86, 98)]
    drops = np.zeros(n)
    for _ in range(int(seconds / (9 if night else 6))):
        place(drops, drip(rng.choice(water_notes), 0.4, gain=rng.uniform(0.05, 0.11)), rng.uniform(0, seconds))

    # 若有若无的持续低音：宫与徵（夜里是羽与角），慢慢呼吸
    drone_root = hz(59) if night else hz(62)   # B3 / D4
    breath_a = 0.55 + 0.45 * periodic_lfo(n, 3, 0.3)
    breath_b = 0.55 + 0.45 * periodic_lfo(n, 4, 1.7)
    # 让频率在循环里也首尾相接：取最接近的、在循环长度里正好走完整数圈的频率
    drone = np.zeros(n)
    for ratio, amp, lfo in [(1, 1.0, breath_a), (1.5, 0.6, breath_b), (2, 0.25, breath_a)]:
        cycles = round(drone_root * ratio * seconds)
        drone += amp * np.sin(2 * np.pi * cycles * np.arange(n) / n) * lfo

    # 水声：200～1500Hz 一带的流水，起伏缓慢
    water = periodic_noise(n, rng, lambda f: np.where(f > 120, 1 / np.sqrt(np.maximum(f, 1)), 0) * np.exp(-((np.log(np.maximum(f, 1)) - np.log(520)) ** 2) / 1.2))
    water *= 0.7 + 0.3 * periodic_lfo(n, 5, 0.9) * periodic_lfo(n, 2, 0.2)

    mix = strings * 1.0 + drops + drone * (0.05 if night else 0.04) + water * (0.03 if night else 0.035)
    mix = reverb(mix, rng, seconds=4.0 if night else 3.2, wet=0.55 if night else 0.45)
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

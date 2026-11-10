"""Gera loops de motor a partir das gravações do usuário (Sonsmotor/*.mp3).

Para cada motor:
  1. rastreia uma linha harmônica forte (frequência ao longo do tempo)
  2. escolhe trechos com volume alto e tom contínuo, espalhados do grave ao agudo
  3. "desliza" cada trecho para tom constante (de-chirp) e corta um número inteiro de ciclos -> loop sem emenda
  4. gera versão "alívio" (filtrada, mais abafada)
  5. do V8, recorta o som real das trocas de marcha (one-shot)
Saída: assets/audio/<motor>/*.wav (com chunk 'smpl' de loop) + scripts/data/engine_samples.gd (tabela rpm -> arquivo)
"""
import os, sys, struct, json
import numpy as np
import soundfile as sf
from scipy import signal
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

PROJ = sys.argv[1]
DBG = sys.argv[2]
SRC = os.path.join(PROJ, "Sonsmotor")
SR_OUT = 44100
REDLINE = 12000.0

ENGINES = {
    # chave: arquivo, faixa da linha harmônica guia (Hz), janelas "acelerando" e "aliviando" (s)
    "valkyr": {"file": "V10_trocas_refinadas.mp3", "band": (250, 360),
               "on": [(1.2, 2.2), (6.4, 7.4)], "off": []},
    "orion": {"file": "V6_trocas_refinadas.mp3", "band": (480, 620),
              "on": [(1.6, 2.6), (3.4, 4.4)], "off": [(5.25, 5.55, 380, 560), (5.75, 6.1, 280, 470), (6.35, 6.8, 190, 380), (7.1, 7.6, 120, 270)]},
    "kestrel": {"file": "V8_trocas_refinadas.mp3", "band": (500, 620),
                "on": [(0.3, 1.25, 520, 620), (3.6, 4.6, 430, 530)], "off": [(6.75, 7.2, 300, 520), (7.4, 7.9, 250, 480)]},
    "helix": {"file": "V12_trocas_refinadas.mp3", "band": (620, 780),
              "on": [(2.3, 3.3), (3.6, 4.6)], "off": [(5.4, 6.3), (7.0, 7.9)]},
}
TOP_RPM = 11500.0     # giro que o trecho "acelerando" mais agudo representa


def load(path):
    d, sr = sf.read(path)
    x = d.mean(axis=1) if d.ndim > 1 else d
    if sr != SR_OUT:
        x = signal.resample_poly(x, SR_OUT, sr)
    return x.astype(np.float64), SR_OUT


def track_line(x, sr, band, hop=256, win=4096):
    f, t, Z = signal.stft(x, sr, nperseg=win, noverlap=win - hop)
    S = np.abs(Z)
    lo, hi = np.searchsorted(f, band[0]), np.searchsorted(f, band[1])
    energy = S[lo:hi].max(axis=0)
    start = int(np.argmax(energy))
    track = np.zeros(S.shape[1])
    conf = np.zeros(S.shape[1])

    def peak_near(k, fc, tol):
        a, b = np.searchsorted(f, fc * (1 - tol)), np.searchsorted(f, fc * (1 + tol))
        a, b = max(a, 1), min(b, len(f) - 2)
        if b <= a:
            return fc, 0.0
        i = a + int(np.argmax(S[a:b, k]))
        # interpolação parabólica do pico
        y0, y1, y2 = np.log(S[i - 1, k] + 1e-12), np.log(S[i, k] + 1e-12), np.log(S[i + 1, k] + 1e-12)
        den = y0 - 2 * y1 + y2
        off = 0.5 * (y0 - y2) / den if den != 0 else 0.0
        return f[i] + off * (f[1] - f[0]), S[i, k]

    track[start] = f[lo + int(np.argmax(S[lo:hi, start]))]
    conf[start] = S[lo:hi, start].max()
    for direction in (1, -1):
        k = start
        while 0 <= k + direction < S.shape[1]:
            fc = track[k]
            k += direction
            fn, c = peak_near(k, fc, 0.06)
            # troca de marcha: tom despenca -> busca mais larga
            if c < conf[k - direction] * 0.15:
                fn2, c2 = peak_near(k, fc, 0.3)
                if c2 > c * 3:
                    fn, c = fn2, c2
            track[k], conf[k] = fn, c
    return t, track, conf, S, f


def dechirp_loop(x, sr, t_tr, f_tr, t0, t1, cycles_target=0.5):
    """Recorta [t0,t1], deixa o tom constante e devolve um loop fechado + frequência média."""
    n0, n1 = int(t0 * sr), int(t1 * sr)
    seg = x[n0:n1]
    tt = np.arange(len(seg)) / sr + t0
    fi = np.interp(tt, t_tr, f_tr)
    fm = float(np.mean(fi))
    # fase acumulada em "ciclos" da linha rastreada
    phase = np.cumsum(fi) / sr
    # amostra de saída n tem fase fm*n/sr -> acha tempo de entrada correspondente
    n_out = int(phase[-1] / fm * sr) - 1
    out_phase = np.arange(n_out) * fm / sr
    idx = np.interp(out_phase, phase, np.arange(len(seg)))
    y = np.interp(idx, np.arange(len(seg)), seg)
    # loop com número inteiro de ciclos + cruzamento suave
    xf = int(0.02 * sr)
    cyc = max(4, int(round(cycles_target * fm)))
    cyc = max(2, min(cyc, int((len(y) - xf - 2) / sr * fm)))
    L = int(round(cyc / fm * sr))
    xf = min(xf, L // 3, len(y) - L - 1)
    print(f"    janela {t0:.2f}-{t1:.2f}s: f={fm:.1f}Hz saída={len(y)/sr:.3f}s ciclos={cyc}")
    if xf < 50:
        return (None, fm)
    st = (len(y) - L - xf) // 2
    body = y[st:st + L + xf].copy()
    ramp = np.linspace(0, 1, xf)
    loop = body[:L].copy()
    loop[:xf] = body[L:L + xf] * (1 - ramp) + body[:xf] * ramp
    return (loop, fm)


def write_wav_loop(path, data, sr, loop=True):
    data = np.clip(data, -1, 1)
    pcm = (data * 32767).astype("<i2").tobytes()
    chunks = b""
    fmt = struct.pack("<HHIIHH", 1, 1, sr, sr * 2, 2, 16)
    chunks += b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(pcm)) + pcm
    if loop:
        n = len(data)
        smpl = struct.pack("<IIIIIIIII", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<IIIIII", 0, 0, 0, n - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)


def rms(a):
    return float(np.sqrt(np.mean(a ** 2)) + 1e-9)


def choose_segments(x, sr, t_tr, f_tr, conf, n_seg=5, seg_len=0.36):
    env = np.sqrt(np.convolve(x ** 2, np.ones(2048) / 2048, mode="same"))
    env_t = np.interp(t_tr, np.arange(len(x)) / sr, env)
    good = []
    dt = t_tr[1] - t_tr[0]
    w = int(seg_len / dt)
    for k in range(0, len(t_tr) - w, max(1, w // 4)):
        fseg = f_tr[k:k + w]
        jump = np.max(np.abs(np.diff(fseg)) / fseg[:-1])
        if jump > 0.03:
            continue
        if env_t[k:k + w].min() < env.max() * 0.35:
            continue
        good.append((t_tr[k], t_tr[k] + seg_len, float(np.mean(fseg)), float(np.mean(env_t[k:k + w]))))
    if not good:
        raise RuntimeError("sem trechos bons")
    good.sort(key=lambda g: g[2])
    # espalha pelos tons disponíveis
    picks = []
    qs = np.linspace(0, 1, n_seg)
    for q in qs:
        g = good[int(round(q * (len(good) - 1)))]
        if all(abs(g[2] - p[2]) / p[2] > 0.06 for p in picks):
            picks.append(g)
    return picks


def shift_oneshots(x, sr, t_tr, f_tr):
    """Momentos em que o tom cai bruscamente (troca de marcha)."""
    shots = []
    dt = t_tr[1] - t_tr[0]
    k = 0
    while k < len(f_tr) - 10:
        ratio = f_tr[k + int(0.12 / dt)] / f_tr[k] if k + int(0.12 / dt) < len(f_tr) else 1
        if ratio < 0.86:
            t0 = t_tr[k] - 0.03
            n0 = int(t0 * sr)
            seg = x[n0:n0 + int(0.28 * sr)].copy()
            env = np.minimum(1, np.linspace(0, 8, len(seg))) * np.exp(-np.linspace(0, 3.5, len(seg)))
            shots.append(seg * env)
            k += int(0.5 / dt)
        else:
            k += 1
    return shots


def make_loop(x, sr, t_tr, f_tr, w, cycles):
    if len(w) == 4:
        # faixa própria para esta janela: rastreia só dentro dela
        seg_t0, seg_t1, lo, hi = w
        n0, n1 = int(max(seg_t0 - 0.3, 0) * sr), int((seg_t1 + 0.3) * sr)
        tt, ff, _, _, _ = track_line(x[n0:n1], sr, (lo, hi))
        ff = signal.medfilt(ff, 9)
        return dechirp_loop(x, sr, tt + n0 / sr, ff, seg_t0, seg_t1, cycles)
    return dechirp_loop(x, sr, t_tr, f_tr, w[0], w[1], cycles)


def main():
    os.makedirs(DBG, exist_ok=True)
    table = {}
    fig, axes = plt.subplots(len(ENGINES), 1, figsize=(16, 4 * len(ENGINES)))
    shift_total = 0
    for row, (key, cfg) in enumerate(ENGINES.items()):
        x, sr = load(os.path.join(SRC, cfg["file"]))
        x = signal.sosfilt(signal.butter(2, 30, "hp", fs=sr, output="sos"), x)
        t_tr, f_tr, conf, S, f = track_line(x, sr, cfg["band"])
        f_tr = signal.medfilt(f_tr, 9)
        out_dir = os.path.join(PROJ, "assets", "audio", key)
        os.makedirs(out_dir, exist_ok=True)
        for old in os.listdir(out_dir):
            os.remove(os.path.join(out_dir, old))
        print(key)
        ons = [o for o in (make_loop(x, sr, t_tr, f_tr, w, 0.5) + (w,) for w in cfg["on"]) if o[0] is not None]
        offs = [o for o in (make_loop(x, sr, t_tr, f_tr, w, 0.3) + (w,) for w in cfg["off"]) if o[0] is not None]
        f_top = max(o[1] for o in ons)
        ref = np.median([rms(o[0]) for o in ons])
        on_entries, off_entries = [], []
        for i, (lp, fm, w) in enumerate(sorted(ons, key=lambda o: o[1])):
            name = f"on_{i}.wav"
            write_wav_loop(os.path.join(out_dir, name), lp * (0.3 / ref), sr)
            on_entries.append({"file": name, "rpm": round(TOP_RPM * fm / f_top), "hz": round(fm, 1), "w": w})
        if not offs:
            # sem trecho de alívio na gravação: versão abafada do "acelerando"
            for i, (lp, fm, w) in enumerate(sorted(ons, key=lambda o: o[1])):
                o = signal.sosfiltfilt(signal.butter(2, 1100, "lp", fs=sr, output="sos"), lp)
                offs.append((o, fm, w))
            off_gain = [0.3 / ref * 0.7] * len(offs)
        else:
            off_ref = np.median([rms(o[0]) for o in offs])
            off_gain = [0.3 / off_ref * 0.75] * len(offs)
        for i, (lp, fm, w) in enumerate(sorted(offs, key=lambda o: o[1])):
            name = f"off_{i}.wav"
            write_wav_loop(os.path.join(out_dir, name), lp * off_gain[i], sr)
            off_entries.append({"file": name, "rpm": round(TOP_RPM * fm / f_top), "hz": round(fm, 1), "w": w})
        table[key] = {"on": on_entries, "off": off_entries}
        ax = axes[row]
        ax.pcolormesh(t_tr, f, 20 * np.log10(S + 1e-6), shading="auto", vmin=-80, vmax=-10, cmap="magma")
        ax.plot(t_tr, f_tr, "c-", lw=0.8)
        for e in on_entries:
            ax.axvspan(e["w"][0], e["w"][1], color="lime", alpha=0.25)
        for e in off_entries:
            ax.axvspan(e["w"][0], e["w"][1], color="red", alpha=0.25)
        ax.set_ylim(0, 1500)
        ax.set_title(f"{key} ({cfg['file']}) on: " + ", ".join(f"{e['hz']}Hz={e['rpm']}" for e in on_entries) + " | off: " + ", ".join(f"{e['hz']}Hz={e['rpm']}" for e in off_entries))
        print(key, "on", [(e["hz"], e["rpm"]) for e in on_entries], "off", [(e["hz"], e["rpm"]) for e in off_entries])
    # trocas de marcha reais: V8 refinado + V8 original
    shots = []
    for fname, band in (("V8_trocas_refinadas.mp3", (500, 620)), ("V8_aceleracao_mudancas.mp3", (150, 460))):
        x, sr = load(os.path.join(SRC, fname))
        t_tr, f_tr, conf, S, f = track_line(x, sr, band)
        f_tr = signal.medfilt(f_tr, 9)
        shots += shift_oneshots(x, sr, t_tr, f_tr)
    shots = sorted(shots, key=lambda s: -rms(s))[:4]
    for i, sh in enumerate(shots):
        write_wav_loop(os.path.join(PROJ, "assets", "audio", f"shift_{i}.wav"), sh / (np.abs(sh).max() + 1e-9) * 0.8, SR_OUT, loop=False)
    print("trocas de marcha recortadas:", len(shots))
    plt.tight_layout()
    plt.savefig(os.path.join(DBG, "loops.png"), dpi=55)
    lines = ["class_name EngineSamples", "## GERADO por tools/build_engine_samples.py a partir de Sonsmotor/*_refinadas.mp3 — não editar à mão.",
             "## Para cada motor: loops gravados 'on' (acelerando) e 'off' (aliviando) e o rpm que cada um representa.", "",
             "const SHIFT_COUNT := %d" % len(shots), "", "const DATA := {"]
    for key, d in table.items():
        lines.append('	"%s": {' % key)
        for kind in ("on", "off"):
            lines.append('		"%s": [' % kind)
            for e in d[kind]:
                lines.append('			{"file": "%s", "rpm": %d.0},' % (e["file"], e["rpm"]))
            lines.append("		],")
        lines.append("	},")
    lines.append("}")
    with open(os.path.join(PROJ, "scripts", "data", "engine_samples.gd"), "w", encoding="utf-8") as fh:
        fh.write(chr(10).join(lines) + chr(10))


main()

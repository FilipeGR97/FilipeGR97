"""Gera os loops de motor do jogo a partir de uma gravação real (Sonsmotor/videoplayback.m4a).

A gravação tem, em sequência: V6, V8, V10, V12 e H16 (o H16 é ignorado). Para cada motor:
  1. rastreia a linha harmônica mais forte ao longo do trecho (acompanha as trocas de marcha)
  2. separa as "puxadas" (giro subindo entre duas trocas) e os trechos de giro caindo
  3. dentro delas, recorta janelas curtas em vários tons diferentes (do giro baixo ao alto)
  4. deixa cada janela com tom constante (de-chirp) e corta um número inteiro de ciclos -> loop sem emenda
  5. "on" = loops acelerando; "off" = loops de alívio (trechos de giro caindo, ou versão abafada do on)
O tom mais agudo encontrado em cada motor é mapeado para TOP_RPM do jogo; os demais por proporção.

Uso:
  pip install --target <pasta> soundfile av numpy scipy matplotlib
  PYTHONPATH=<pasta> python tools/build_engine_samples.py <pasta_do_projeto> <pasta_debug>
Saída: assets/audio/<motor>/{on,off}_N.wav (com chunk 'smpl' de loop) + scripts/data/engine_samples.gd
"""
import os, sys, struct
import numpy as np
from scipy import signal

PROJ = sys.argv[1]
DBG = sys.argv[2] if len(sys.argv) > 2 else os.path.join(PROJ, ".audio_debug")
SRC = os.path.join(PROJ, "Sonsmotor", "videoplayback.m4a")
SR = 44100
TOP_RPM = 12000.0
N_ON = 8          # loops "acelerando" por motor
N_OFF = 4         # loops "aliviando" por motor

# trechos da gravação (s) e faixa inicial da linha harmônica guia (Hz)
ENGINES = {
    "orion":   {"label": "V6 turbo híbrido", "t": (0.05, 6.35), "band": (180, 300)},
    "kestrel": {"label": "V8",               "t": (6.45, 17.85), "band": (250, 330)},
    "valkyr":  {"label": "V10",              "t": (17.95, 26.15), "band": (370, 460)},
    "helix":   {"label": "V12",              "t": (26.25, 32.85), "band": (300, 380)},
}


def decode(path):
    import av
    c = av.open(path)
    sr = c.streams.audio[0].rate
    out = []
    for fr in c.decode(audio=0):
        a = fr.to_ndarray().astype(np.float64)
        if fr.format.is_planar:
            a = a.T
        else:
            a = a.reshape(-1, len(fr.layout.channels))
        out.append(a)
    x = np.concatenate(out).mean(axis=1)
    if sr != SR:
        x = signal.resample_poly(x, SR, sr)
    return x


def track(x, band, hop=256, win=8192):
    f, t, Z = signal.stft(x, SR, nperseg=win, noverlap=win - hop)
    S = np.abs(Z)
    df = f[1] - f[0]
    lo, hi = np.searchsorted(f, band[0]), np.searchsorted(f, band[1])
    k0 = 3
    tr = np.zeros(S.shape[1])
    tr[k0] = f[lo + int(np.argmax(S[lo:hi, k0]))]

    def peak(k, fc, tol):
        a = max(int((fc * (1 - tol)) / df), 1)
        b = min(int((fc * (1 + tol)) / df) + 1, len(f) - 2)
        i = a + int(np.argmax(S[a:b, k]))
        y0, y1, y2 = np.log(S[i - 1, k] + 1e-12), np.log(S[i, k] + 1e-12), np.log(S[i + 1, k] + 1e-12)
        den = y0 - 2 * y1 + y2
        return f[i] + (0.5 * (y0 - y2) / den if den != 0 else 0.0) * df, S[i, k]

    for direction in (1, -1):
        k = k0
        while 0 <= k + direction < S.shape[1]:
            fc = tr[k]
            k += direction
            fn, c = peak(k, fc, 0.04)
            # troca de marcha: o tom cai ~10-25% de uma vez -> procura abaixo
            fn2, c2 = peak(k, fc * 0.82, 0.12)
            if c2 > c * 2.5:
                fn, c = fn2, c2
            tr[k] = fn
    return t, signal.medfilt(tr, 7), f, S


def segments(t, tr, min_len=0.3):
    """Separa em trechos contínuos (sem troca de marcha); devolve (i0, i1, inclinação)."""
    jumps = np.where(np.abs(np.diff(tr)) / tr[:-1] > 0.035)[0]
    cuts = [0] + list(jumps + 1) + [len(tr)]
    out = []
    dt = t[1] - t[0]
    for a, b in zip(cuts[:-1], cuts[1:]):
        a2, b2 = a + int(0.06 / dt), b - int(0.06 / dt)
        if (b2 - a2) * dt >= min_len:
            slope = (tr[b2 - 1] - tr[a2]) / ((b2 - a2) * dt) / np.mean(tr[a2:b2])
            out.append((a2, b2, slope))
    return out


def envelope(y, cutoff=18.0):
    return np.sqrt(np.maximum(signal.sosfiltfilt(signal.butter(2, cutoff, "lp", fs=SR, output="sos"), y ** 2), 0.0) + 1e-10)


def flatten(y, cutoff=18.0):
    """Remove a modulação lenta de volume (pulsação < cutoff Hz) sem mexer no timbre.
    O ganho é limitado (no máx. 2x) para nunca amplificar trechos quase silenciosos."""
    env = envelope(y, cutoff)
    med = float(np.median(env))
    env = np.maximum(env, med * 0.5)
    return y / env * med


def has_dropout(y):
    """Trecho com 'buraco' de volume (corte de ignição na troca de marcha, etc.)."""
    env = envelope(y, 25.0)
    return float(np.min(env[len(env) // 20: -len(env) // 20])) < 0.35 * float(np.median(env))


def dechirp_loop(x, t_tr, f_tr, t0, t1, cycles_s=1.1):
    n0, n1 = int(t0 * SR), int(t1 * SR)
    seg = x[n0:n1]
    tt = np.arange(len(seg)) / SR + t0
    fi = np.interp(tt, t_tr, f_tr)
    fm = float(np.mean(fi))
    phase = np.cumsum(fi) / SR
    n_out = int(phase[-1] / fm * SR) - 1
    idx = np.interp(np.arange(n_out) * fm / SR, phase, np.arange(len(seg)))
    y = np.interp(idx, np.arange(len(seg)), seg)
    y = flatten(y)
    xf = int(0.04 * SR)
    cyc = max(4, int(round(cycles_s * fm)))
    cyc = max(2, min(cyc, int((len(y) - xf - 2) / SR * fm)))
    L = int(round(cyc / fm * SR))
    xf = min(xf, L // 3, len(y) - L - 1)
    if xf < 64:
        return None, fm
    st = (len(y) - L - xf) // 2
    body = y[st:st + L + xf]
    ramp = np.sin(np.linspace(0, np.pi / 2, xf)) ** 2
    loop = body[:L].copy()
    loop[:xf] = body[L:L + xf] * (1 - ramp) + body[:xf] * ramp
    return loop, fm


def piece(x, t_tr, f_tr, t0, t1, f_target):
    """Trecho com tom constante, levado exatamente para f_target e sem pulsação de volume."""
    n0, n1 = int(t0 * SR), int(t1 * SR)
    seg = x[n0:n1]
    tt = np.arange(len(seg)) / SR + t0
    fi = np.interp(tt, t_tr, f_tr)
    phase = np.cumsum(fi) / SR                      # ciclos acumulados
    n_out = int(phase[-1] / f_target * SR) - 1
    idx = np.interp(np.arange(n_out) * f_target / SR, phase, np.arange(len(seg)))
    if np.any(np.diff(phase) <= 0) or not np.all(np.isfinite(phase)):
        return np.zeros(0)
    raw = np.interp(idx, np.arange(len(seg)), seg)
    if len(raw) < 64 or has_dropout(raw):
        return np.zeros(0)
    y = flatten(raw)
    return y if np.all(np.isfinite(y)) else np.zeros(0)


def stitched_loop(x, t_tr, f_tr, cands, f_target, length_s=1.6):
    """Costura vários trechos diferentes (de marchas/momentos diferentes) no mesmo tom.
    Resultado: loop longo que não repete o mesmo pedaço — some o 'na na na'."""
    xf = int(0.03 * SR)
    ramp = np.sin(np.linspace(0, np.pi / 2, xf)) ** 2
    out = None
    used = []
    tol = 0.03
    while tol <= 0.14 and (out is None or len(out) < length_s * SR + 2 * xf):
        near = sorted([c for c in cands if abs(c[2] - f_target) / f_target < tol], key=lambda c: abs(c[2] - f_target))
        for c in near:
            if any(abs(c[0] - u) < 0.2 for u in used):
                continue
            p = piece(x, t_tr, f_tr, c[0], c[1], f_target)
            if len(p) < 3 * xf:
                continue
            used.append(c[0])
            p = p / (rms(p) + 1e-9) * 0.2           # cada pedaço com o mesmo volume
            if out is not None:
                # alinha a fase: desloca o novo pedaço (até 1 período) para casar com o fim do anterior
                per = int(SR / f_target) + 1
                tail = out[-xf:]
                best, bk = -1e9, 0
                for k in range(0, min(per, len(p) - xf - 1)):
                    c = float(np.dot(tail, p[k:k + xf]))
                    if c > best:
                        best, bk = c, k
                p = p[bk:]
            out = p if out is None else np.concatenate([out[:-xf], out[-xf:] * (1 - ramp) + p[:xf] * ramp, p[xf:]])
            if len(out) >= length_s * SR + 2 * xf:
                break
        tol += 0.02
    if out is None:
        return None
    xf2 = int(0.04 * SR)
    cyc = int((len(out) - xf2) / SR * f_target)
    L = int(round(cyc / f_target * SR))
    if L < int(0.3 * SR):
        return None
    loop = out[:L].copy()
    r2 = np.sin(np.linspace(0, np.pi / 2, xf2)) ** 2
    loop[:xf2] = out[L:L + xf2] * (1 - r2) + out[:xf2] * r2
    # nivela o volume do loop pronto de forma circular (também na volta do loop)
    big = flatten(np.tile(loop, 3), cutoff=12.0)
    return big[L:2 * L]


def write_wav(path, data, loop=True):
    pk = float(np.max(np.abs(data))) if len(data) else 0.0
    if pk > 0.85:
        data = data * (0.85 / pk)
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    ch = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(pcm)) + pcm
    if loop:
        smpl = struct.pack("<IIIIIIIII", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0) + struct.pack("<IIIIII", 0, 0, 0, len(data) - 1, 0, 0)
        ch += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", 4 + len(ch)) + b"WAVE" + ch)


def rms(a):
    return float(np.sqrt(np.mean(a ** 2)) + 1e-9)


def spread(cands, n, key):
    """Escolhe n candidatos espalhados pelo tom (evita repetidos < 5%)."""
    cands = sorted(cands, key=key)
    if not cands:
        return []
    picks = []
    for q in np.linspace(0, 1, n * 3):
        c = cands[int(round(q * (len(cands) - 1)))]
        if all(abs(key(c) - key(p)) / key(p) > 0.05 for p in picks):
            picks.append(c)
    if len(picks) > n:
        idx = np.round(np.linspace(0, len(picks) - 1, n)).astype(int)
        picks = [picks[i] for i in idx]
    return picks


def main():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    os.makedirs(DBG, exist_ok=True)
    full = decode(SRC)
    full = signal.sosfilt(signal.butter(2, 35, "hp", fs=SR, output="sos"), full)
    table = {}
    fig, axes = plt.subplots(len(ENGINES), 1, figsize=(18, 4.5 * len(ENGINES)))
    for row, (key, cfg) in enumerate(ENGINES.items()):
        a, b = cfg["t"]
        x = full[int(a * SR):int(b * SR)]
        t, tr, f, S = track(x, cfg["band"])
        segs = segments(t, tr)
        dt = t[1] - t[0]
        on_c, off_c = [], []
        for i0, i1, slope in segs:
            seg_dur = (i1 - i0) * dt
            win = min(0.4, seg_dur - 0.04)   # matéria-prima curta; o loop final é costurado (longo)
            if win < 0.28:
                continue
            n = int(win / dt)
            for k in range(i0, i1 - n + 1, max(1, n // 4)):
                fseg = tr[k:k + n]
                if np.max(np.abs(np.diff(fseg)) / fseg[:-1]) > 0.02:
                    continue
                c = (t[k], t[k] + win, float(np.mean(fseg)), win)
                (on_c if slope > -0.05 else off_c).append(c)
        on_p, off_p = [], []
        out_dir = os.path.join(PROJ, "assets", "audio", key)
        os.makedirs(out_dir, exist_ok=True)
        for old in os.listdir(out_dir):
            os.remove(os.path.join(out_dir, old))
        ons = []
        fmin, fmax = min(c[2] for c in on_c), max(c[2] for c in on_c)
        for f_target in np.geomspace(fmin * 1.01, fmax * 0.995, N_ON):
            lp = stitched_loop(x, t, tr, on_c, f_target)
            if lp is not None:
                srcs = sorted(on_c, key=lambda c: abs(c[2] - f_target))[:3]
                ons.append((lp, float(f_target), min(c[0] for c in srcs) + a, max(c[1] for c in srcs) + a))
        ons.sort(key=lambda o: o[1])
        f_top = ons[-1][1]
        ref = np.median([rms(o[0]) for o in ons])
        on_e, off_e = [], []
        for i, (lp, fm, t0, t1) in enumerate(ons):
            # mantém um pouco da variação natural de volume com o giro, sem estourar
            g = 0.22 / rms(lp) * (0.75 + 0.25 * fm / f_top)
            write_wav(os.path.join(out_dir, f"on_{i}.wav"), lp * g)
            on_e.append({"file": f"on_{i}.wav", "rpm": TOP_RPM * fm / f_top, "hz": fm, "w": (t0, t1)})
        offs = []
        for c in off_c[:0]:
            pass
        # alívio no giro alto também (a redução leva o motor ao alto): versão abafada dos loops acelerando
        for j in sorted(set(np.round(np.linspace(0, len(ons) - 1, 4)).astype(int))):
            lp, fm, t0, t1 = ons[j]
            if all(abs(fm - o[1]) / fm > 0.05 for o in offs):
                soft = signal.sosfiltfilt(signal.butter(2, 1600, "lp", fs=SR, output="sos"), lp)
                offs.append((soft, fm, t0, t1))
        offs.sort(key=lambda o: o[1])
        for i, (lp, fm, t0, t1) in enumerate(offs):
            write_wav(os.path.join(out_dir, f"off_{i}.wav"), lp * (0.17 / rms(lp)))
            off_e.append({"file": f"off_{i}.wav", "rpm": TOP_RPM * fm / f_top, "hz": fm, "w": (t0, t1)})
        table[key] = {"on": on_e, "off": off_e}
        ax = axes[row]
        ax.pcolormesh(t + a, f, 20 * np.log10(S + 1e-7), shading="auto", vmin=-95, vmax=-20, cmap="magma")
        ax.plot(t + a, tr, "c-", lw=0.8)
        for e in on_e:
            ax.axvspan(*e["w"], color="lime", alpha=0.3)
        for e in off_e:
            ax.axvspan(*e["w"], color="red", alpha=0.3)
        ax.set_ylim(0, 1300)
        ax.set_title(f"{key} {cfg['label']} on: " + " ".join(f"{e['hz']:.0f}" for e in on_e) + " | off: " + " ".join(f"{e['hz']:.0f}" for e in off_e))
        print(f"{key:8s} {cfg['label']:18s} on rpm: {[round(e['rpm']) for e in on_e]}  off rpm: {[round(e['rpm']) for e in off_e]}")
    plt.tight_layout()
    plt.savefig(os.path.join(DBG, "loops.png"), dpi=50)
    for old in os.listdir(os.path.join(PROJ, "assets", "audio")):
        if old.startswith("shift_"):
            os.remove(os.path.join(PROJ, "assets", "audio", old))
    lines = ["class_name EngineSamples",
             "## GERADO por tools/build_engine_samples.py a partir de Sonsmotor/videoplayback.m4a — não editar à mão.",
             "## Para cada motor: loops gravados 'on' (acelerando) e 'off' (aliviando) e o rpm que cada um representa.",
             "", "const SHIFT_COUNT := 0", "", "const DATA := {"]
    for key, d in table.items():
        lines.append('\t"%s": {' % key)
        for kind in ("on", "off"):
            lines.append('\t\t"%s": [' % kind)
            for e in d[kind]:
                lines.append('\t\t\t{"file": "%s", "rpm": %.1f},' % (e["file"], e["rpm"]))
            lines.append("\t\t],")
        lines.append("\t},")
    lines.append("}")
    with open(os.path.join(PROJ, "scripts", "data", "engine_samples.gd"), "w", encoding="utf-8") as fh:
        fh.write(chr(10).join(lines) + chr(10))


if __name__ == "__main__":
    main()

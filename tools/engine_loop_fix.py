"""Corrige loops de motor com timbre fora da curva (Patch 5 / 5.1).

Os loops de cada motor são costurados de trechos diferentes da gravação. Às vezes um loop sai com "brilho"
(centroide espectral) bem diferente dos vizinhos — ao acelerar parece que o som troca de motor.

Correção automática, por motor (camada "on"):
  1. mede o centroide espectral de cada loop e ajusta uma reta log(centroide) x log(rpm)
  2. loop com desvio > 22% da reta é substituído pelo loop bom mais próximo, reafinado para o rpm dele
     (reamostragem por FFT do ciclo inteiro: continua um loop perfeito, sem emenda)
Os loops "off" (alívio) são versões abafadas dos "on" e são refeitos a partir dos "on" corrigidos.
Por fim, tons agudos isolados (> 1,5 kHz e mais de 24 dB acima do entorno) são aparados: no giro máximo,
com o pitch subindo, eles viravam um "piado" (queixa do V10 gerado da gravação nova, Patch 5.1).

Uso:  PYTHONPATH=<pasta com numpy e scipy> python tools/engine_loop_fix.py <pasta_do_projeto> [motores...]
Rode logo depois de build_engine_samples.py.
"""
import os, re, sys, struct
import numpy as np

PROJ = sys.argv[1]
ENGINES = sys.argv[2:] or ["orion", "kestrel", "valkyr", "helix"]
MAX_DEV = 0.22


def read_wav(path):
    data = open(path, "rb").read()
    off = 12
    fmt = pcm = None
    while off + 8 <= len(data):
        cid = data[off:off + 4]
        size = struct.unpack("<I", data[off + 4:off + 8])[0]
        body = data[off + 8:off + 8 + size]
        if cid == b"fmt ":
            fmt = struct.unpack("<HHIIHH", body[:16])
        elif cid == b"data":
            pcm = body
        off += 8 + size + (size & 1)
    a = np.frombuffer(pcm, dtype="<i2").astype(np.float64).reshape(-1, fmt[1]) / 32768.0
    return a, fmt[2]


def write_wav(path, data, sr):
    pk = float(np.max(np.abs(data)))
    if pk > 0.85:
        data = data * (0.85 / pk)
    n, ch = data.shape
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, ch, sr, sr * ch * 2, ch * 2, 16)
    out = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(pcm)) + pcm
    smpl = struct.pack("<IIIIIIIII", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0) + struct.pack("<IIIIII", 0, 0, 0, n - 1, 0, 0)
    out += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", 4 + len(out)) + b"WAVE" + out)


def resample_loop(a, ratio):
    """Reafina um loop periódico por 'ratio' (>1 = mais agudo), mantendo-o periódico."""
    n = a.shape[0]
    m = int(round(n / ratio))
    out = []
    for c in range(a.shape[1]):
        X = np.fft.rfft(a[:, c])
        Y = np.zeros(m // 2 + 1, dtype=complex)
        k = min(len(X), len(Y))
        Y[:k] = X[:k]
        out.append(np.fft.irfft(Y, m) * (m / n))
    return np.stack(out, axis=1)


def centroid(a, sr):
    m = a.mean(axis=1)
    S = np.abs(np.fft.rfft(m * np.hanning(len(m)))) ** 2
    F = np.fft.rfftfreq(len(m), 1 / sr)
    return float((S * F).sum() / S.sum())


def lowpass_loop(a, sr, fc):
    n = a.shape[0]
    F = np.fft.rfftfreq(n, 1 / sr)
    g = 1.0 / np.sqrt(1.0 + (F / fc) ** 4)
    return np.stack([np.fft.irfft(np.fft.rfft(a[:, c]) * g, n) for c in range(a.shape[1])], axis=1)


def tame_peaks(a, sr, f0=1500.0, max_db=24.0):
    """Apara picos estreitos acima de f0 que passam de max_db sobre a mediana local (circular: loop intacto)."""
    from scipy.ndimage import median_filter
    n = a.shape[0]
    F = np.fft.rfftfreq(n, 1 / sr)
    m = a.mean(axis=1)
    S = 20 * np.log10(np.abs(np.fft.rfft(m)) + 1e-9)
    med = median_filter(S, size=max(5, int(300.0 / (F[1] - F[0]))))
    over = np.clip(S - med - max_db, 0.0, None)
    over[F < f0] = 0.0
    g = 10 ** (-over / 20.0)
    out = np.stack([np.fft.irfft(np.fft.rfft(a[:, c]) * g, n) for c in range(a.shape[1])], axis=1)
    return out * (np.sqrt((a ** 2).mean()) / (np.sqrt((out ** 2).mean()) + 1e-12)), float(over.max())


def main():
    src = open(os.path.join(PROJ, "scripts/data/engine_samples.gd"), encoding="utf-8").read()
    for eng in ENGINES:
        blk = src[src.index('"%s": {' % eng):]
        blk = blk[:blk.index("\n\t},")]
        loops = {}
        for kind in ("on", "off"):
            part = blk[blk.index('"%s": [' % kind):]
            part = part[:part.index("]")]
            loops[kind] = [(f[:-4], float(r)) for f, r in re.findall(r'"file": "([^"]+)", "rpm": ([0-9.]+)', part)]
        d = os.path.join(PROJ, "assets/audio", eng)
        data = {name: read_wav(os.path.join(d, name + ".wav")) for name, _ in loops["on"]}
        rpm = dict(loops["on"])
        names = [n for n, _ in loops["on"]]
        x = np.log([rpm[n] for n in names])
        y = np.log([centroid(*data[n]) for n in names])
        # reta robusta: ajusta, descarta o pior, ajusta de novo
        good = np.ones(len(names), bool)
        for _ in range(3):
            coef = np.polyfit(x[good], y[good], 1)
            dev = np.abs(np.exp(y - np.polyval(coef, x)) - 1.0)
            worst = int(np.argmax(np.where(good, dev, -1)))
            if dev[worst] > MAX_DEV and good.sum() > 4:
                good[worst] = False
        coef = np.polyfit(x[good], y[good], 1)
        dev = np.abs(np.exp(y - np.polyval(coef, x)) - 1.0)
        bad = [i for i in range(len(names)) if dev[i] > MAX_DEV]
        for i in bad:
            ok = [j for j in range(len(names)) if j not in bad]
            j = min(ok, key=lambda j: abs(x[j] - x[i]))
            a, sr = data[names[j]]
            out = resample_loop(a, rpm[names[i]] / rpm[names[j]])
            out *= np.sqrt((data[names[i]][0] ** 2).mean()) / (np.sqrt((out ** 2).mean()) + 1e-12)
            write_wav(os.path.join(d, names[i] + ".wav"), out, sr)
            data[names[i]] = (out, sr)
            print("%s %s (desvio %.0f%%) <- %s x%.3f" % (eng, names[i], dev[i] * 100, names[j], rpm[names[i]] / rpm[names[j]]))
        worst = 0.0
        for nm in names:
            a, sr = data[nm]
            a2, cut = tame_peaks(a, sr)
            worst = max(worst, cut)
            write_wav(os.path.join(d, nm + ".wav"), a2, sr)
            data[nm] = (a2, sr)
        print("%s: tons agudos aparados (maior corte %.1f dB)" % (eng, worst))
        if not bad:
            print("%s: timbre coerente (desvio máx %.0f%%)" % (eng, dev.max() * 100))
        # "off" = versão abafada do "on" mais próximo (como no build_engine_samples.py), refeita
        for name, r in loops["off"]:
            j = min(range(len(names)), key=lambda j: abs(np.log(rpm[names[j]]) - np.log(r)))
            a, sr = data[names[j]]
            soft = lowpass_loop(resample_loop(a, r / rpm[names[j]]), sr, 1600.0)
            old, _ = read_wav(os.path.join(d, name + ".wav"))
            soft *= np.sqrt((old ** 2).mean()) / (np.sqrt((soft ** 2).mean()) + 1e-12)
            write_wav(os.path.join(d, name + ".wav"), soft, sr)


if __name__ == "__main__":
    main()

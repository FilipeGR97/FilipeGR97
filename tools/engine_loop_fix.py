"""Corrige loops de motor com timbre fora da curva (Patch 5).

Os loops de cada motor vêm de trechos diferentes da gravação. No V6, V8 e V12 alguns loops tinham "brilho"
muito diferente dos vizinhos (ex.: V12 abafado no giro baixo, V6 chiado até ~9.500 rpm e limpo acima), e ao
acelerar parecia que o som trocava de motor. O V10 já era coerente e não é alterado.

Correção: o loop ruim é substituído pelo loop bom mais próximo, reafinado para o rpm do loop substituído
(reamostragem por FFT do ciclo inteiro: o resultado continua um loop perfeito, sem emenda). É o mesmo que o
jogo faz em tempo real com o pitch, só que pré-calculado.

Depois, um equalizador fixo (o mesmo em todos os loops "on", então não cria pulsação) aproxima o equilíbrio de
frequências do V6 do de um carro 2026 de referência: o nosso V6 tinha 3-6 dB a menos entre 2 e 4 kHz (abafado)
e grave demais em ~180 Hz.

Uso:  PYTHONPATH=<pasta com numpy> python tools/engine_loop_fix.py <pasta_do_projeto>
Rode UMA vez sobre os loops recém-gerados por build_engine_samples.py (rodar de novo aplicaria o EQ duas vezes).
"""
import os, re, sys, struct
import numpy as np

PROJ = sys.argv[1]
# motor: {loop_ruim: loop_bom}
FIX = {
    "orion": {"on_0": "on_4", "on_1": "on_4", "on_2": "on_4", "on_3": "on_4"},
    "kestrel": {"on_7": "on_6"},
    "helix": {"on_0": "on_3", "on_1": "on_3", "on_2": "on_3", "on_4": "on_3"},
}


# motor: pontos (Hz, dB) do equalizador dos loops "on"
EQ = {
    "orion": [(100, 0), (177, -4), (250, -2), (500, 0), (1000, 0), (2000, 3), (2828, 5), (4000, 5), (5657, 2), (8000, 0)],
}


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


def main():
    src = open(os.path.join(PROJ, "scripts/data/engine_samples.gd"), encoding="utf-8").read()
    for eng, fixes in FIX.items():
        blk = src[src.index('"%s": {' % eng):]
        blk = blk[:blk.index("\n\t},")]
        rpm = {}
        for kind in ("on", "off"):
            part = blk[blk.index('"%s": [' % kind):]
            part = part[:part.index("]")]
            for fname, r in re.findall(r'"file": "([^"]+)", "rpm": ([0-9.]+)', part):
                rpm[fname[:-4]] = float(r)
        for bad, good in fixes.items():
            a, sr = read_wav(os.path.join(PROJ, "assets/audio", eng, good + ".wav"))
            ratio = rpm[bad] / rpm[good]
            out = resample_loop(a, ratio)
            out *= np.sqrt((a ** 2).mean()) / (np.sqrt((out ** 2).mean()) + 1e-12)
            write_wav(os.path.join(PROJ, "assets/audio", eng, bad + ".wav"), out, sr)
            print("%s %s <- %s x%.3f (%.2f s)" % (eng, bad, good, ratio, out.shape[0] / sr))
    for eng, pts in EQ.items():
        fx = np.log([p[0] for p in pts])
        gx = np.array([p[1] for p in pts], dtype=float)
        for k in range(8):
            path = os.path.join(PROJ, "assets/audio", eng, "on_%d.wav" % k)
            a, sr = read_wav(path)
            n = a.shape[0]
            F = np.fft.rfftfreq(n, 1 / sr)
            g = 10 ** (np.interp(np.log(np.maximum(F, 1.0)), fx, gx) / 20.0)
            rms0 = np.sqrt((a ** 2).mean())
            out = np.stack([np.fft.irfft(np.fft.rfft(a[:, c]) * g, n) for c in range(a.shape[1])], axis=1)
            out *= rms0 / (np.sqrt((out ** 2).mean()) + 1e-12)
            write_wav(path, out, sr)
        print("%s: EQ aplicado nos loops on" % eng)


if __name__ == "__main__":
    main()

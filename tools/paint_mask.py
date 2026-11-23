"""Máscara de pintura de um modelo externo (Patch 7.1): branco onde é pintura da equipe original.

Pinturas com marcas pintadas na própria textura (ex.: MP4/5): as áreas vermelhas e brancas viram pintura e o
"fechamento" morfológico engole letras e logos pequenos dentro delas — no jogo tudo isso recebe a pintura da
nossa equipe, então nenhuma marca real aparece. Partes pretas grandes (carbono) continuam como estão.

Uso: PYTHONPATH=<numpy, scipy, pillow> python tools/paint_mask.py <textura_cor> <saida_mascara.png> [raio_px]
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

src, dst = sys.argv[1], sys.argv[2]
rad = int(sys.argv[3]) if len(sys.argv) > 3 else 14
a = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255
r, g, b = a[..., 0], a[..., 1], a[..., 2]
mx, mn = a.max(axis=2), a.min(axis=2)
red = (r > 0.45) & (g < 0.35) & (b < 0.35)
white = (mn > 0.55) & (mx - mn < 0.2)
yellow = (r > 0.6) & (g > 0.45) & (b < 0.3)          # logos amarelos (ex.: concha) dentro da pintura
paint = red | white | yellow
st = ndimage.generate_binary_structure(2, 1)
closed = ndimage.binary_closing(paint, structure=st, iterations=rad)
closed = ndimage.binary_fill_holes(closed) & (closed | ndimage.binary_dilation(paint, iterations=rad))
out = ndimage.gaussian_filter(closed.astype(np.float32), 1.0)
Image.fromarray((out * 255).astype(np.uint8)).save(dst)
print("pintura: %.1f%% da textura" % (closed.mean() * 100))

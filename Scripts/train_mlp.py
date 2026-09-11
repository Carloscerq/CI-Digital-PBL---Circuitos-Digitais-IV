#!/usr/bin/env python3
"""Retreina o MLP 132-8-4-4 contra o front end que o RTL realmente executa.
Uso:
    python3 train_mlp.py                         # treina, avalia e exporta
    python3 train_mlp.py --cache feats.npz       # reaproveita as features
    python3 train_mlp.py --no-export             # so o relatorio de acuracia

"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np
import scipy.io as sio
from scipy.signal import lfilter

REPO = Path(__file__).resolve().parents[1]
COEFF_DIR = REPO / "RTL/FFT/model_sim_four_modes_quartus_shared_fft/coefficients"

# ---------------------------------------------------------------------------
# Constantes do datapath. Espelham system_types_pkg.sv e os parametros que
# top_system passa para dsp_preprocessing_subsystem -- se um lado mudar, o
# outro tem que mudar junto.
# ---------------------------------------------------------------------------
FS = 25600.0            # Hz, nominal das duas fontes
Q_INT, Q_FRAC = 9, 15   # Q9.15 com sinal em 24 bits
DATA_MAX = (1 << 23) - 1
DATA_MIN = -(1 << 23)

DECIM_RATE = 32         # FIR/32: 25,6 kHz -> 800 Hz
FFT_N = 64
FFT_HOP = 64            # HOP_SIZE = 64: quadros sem sobreposicao
BINS_USED = 32          # metade do espectro, o que o coletor guarda
LMS_TAPS = 8
LMS_COEFF_FRAC = 20     # coeficientes Q4.20
LMS_MU_SHIFT = 16       # LMS_MU_SHIFT do dsp_preprocessing_subsystem

# fft_peak_mdc.sv: os parametros do modulo MDC. K_MAX e uma banda de FREQUENCIA
# (162,5 Hz) escrita como indice de bin, entao acompanha o DECIM_RATE -- e a
# mesma derivacao do MDC_BAND_NOTE em system_types_pkg.sv, e por isso ela mora
# aqui como conta e nao como constante. Medido nos 56 250 quadros: em K_MAX=13
# o k0 retido vale 4 (50,0 Hz, os 3000 rpm reais) em 86,5% dos quadros; em 26,
# que era o valor herdado do caminho de 6,25 Hz/bin, cai para 3,0%.
MDC_BAND_HZ = 162.5
MDC_K_MAX = round(MDC_BAND_HZ / (FS / DECIM_RATE / FFT_N))
MDC_K_MIN, MDC_N_PEAKS = 2, 3

# Ganho do caminho absorvido em W0: registrador Q9.15 (x * 2^15) e FFT radix-2
# com escala 1/2 por estagio (|rFFT| / 64).  2^15 / 2^6 = 2^9.
HW_GAIN_BIN = 2.0 ** Q_FRAC / FFT_N

VIB_CHANNELS = ["x_direction_housing_A", "y_direction_housing_A",
                "x_direction_housing_B", "y_direction_housing_B"]
TDMS_CHANNELS = {
    "cDAQ9185-1F486B5Mod1/ai0": "Temperature_housing_A",
    "cDAQ9185-1F486B5Mod1/ai1": "Temperature_housing_B",
    "cDAQ9185-1F486B5Mod2/ai0": "U-phase",
    "cDAQ9185-1F486B5Mod2/ai2": "V-phase",
    "cDAQ9185-1F486B5Mod2/ai3": "W-phase",
}
TDMS_BY_NAME = {v: k for k, v in TDMS_CHANNELS.items()}
TEMP_CHANNELS = ["Temperature_housing_A", "Temperature_housing_B"]
PHASES = ["U-phase", "V-phase", "W-phase"]


# ---------------------------------------------------------------------------
# Aritmetica de ponto fixo -- as mesmas funcoes das quatro implementacoes RTL
# ---------------------------------------------------------------------------
def round_sym(value, shift):
    """value / 2**shift com arredondamento meio-para-longe-do-zero.

    E o `round_and_saturate` do FIR e do Hann e o `rounded_divide_64` do
    removedor de media: os tres somam meio LSB na MAGNITUDE e so depois
    reaplicam o sinal, entao -1,5 vai para -2 e nao para -1.
    """
    half = np.int64(1) << (shift - 1)
    return np.where(value >= 0, (value + half) >> shift, -((-value + half) >> shift))


def sat24(value):
    return np.clip(value, DATA_MIN, DATA_MAX)


def load_coeff_rom(path, width=18):
    """Le a mesma imagem .hex que o $readmemh do RTL carrega."""
    words = np.array([int(w, 16) for w in path.read_text().split()], dtype=np.int64)
    return np.where(words >= 1 << (width - 1), words - (1 << width), words)


# ---------------------------------------------------------------------------
# Front end
# ---------------------------------------------------------------------------
def fir_stage(x, coeffs, decimation):
    """Um estagio de fir_decimator_stage_dualmode.

    O estagio emite quando o contador de decimacao fecha, ou seja na entrada
    de indice (m+1)*D - 1, com o historico zerado no reset -- exatamente a
    convolucao causal de estado nulo amostrada nessa fase. O acumulador de 64
    bits e float64 aqui porque o produto (24+18 bits) somado sobre <= 83 taps
    cabe em 49 bits, dentro da mantissa de 53: a soma e EXATA, so o
    arredondamento final precisa ser feito a mao.
    """
    acc = lfilter(coeffs.astype(np.float64), [1.0], x.astype(np.float64))
    acc = np.rint(acc[decimation - 1::decimation]).astype(np.int64)
    return sat24(round_sym(acc, 17))          # coeficientes Q1.17


def fir_decimate_32(x, coeffs):
    """fir_decimator_32_dualmode: 25,6 kHz --/4--> 6,4 --/4--> 1,6 --/2--> 800 Hz."""
    for stage, decimation in zip(coeffs, (4, 4, 2)):
        x = fir_stage(x, stage, decimation)
    return x


def lms_residual(x, mu_shift=LMS_MU_SHIFT, taps=LMS_TAPS):
    """lms_filter_time_serial: preditor linear de 8 taps, saida = residual.

    y(n) = sat((sum w_i * h_i) >>> 20)     h_i = x(n-1-i), coeficientes Q4.20
    e(n) = sat(x(n) - y(n))                <- e ISTO que vai para o framer
    w_i += sat((e(n) * h_i) >>> UPDATE_SHIFT)

    UPDATE_SHIFT = 2*DATA_FRAC + MU_SHIFT - COEFF_FRAC. O `>>` do numpy em
    int64 e aritmetico, igual ao `>>>` do Verilog -- e e justamente esse piso
    que faz os taps descerem em rampa quando o produto fica abaixo de 1 LSB.

    x: (n, canais) int64. Os canais sao filtros independentes, vetorizados.
    """
    update_shift = 2 * Q_FRAC + mu_shift - LMS_COEFF_FRAC
    n, n_ch = x.shape
    w = np.zeros((taps, n_ch), np.int64)
    history = np.zeros((taps, n_ch), np.int64)
    out = np.empty_like(x)

    for t in range(n):
        desired = x[t]
        estimate = np.clip(np.sum(w * history, 0) >> LMS_COEFF_FRAC, DATA_MIN, DATA_MAX)
        error = np.clip(desired - estimate, DATA_MIN, DATA_MAX)
        out[t] = error
        w += (error * history) >> update_shift
        np.clip(w, DATA_MIN, DATA_MAX, out=w)
        history[1:] = history[:-1]
        history[0] = desired

    return out, w


def frame_view(x, size=FFT_N, hop=FFT_HOP):
    n_frames = (len(x) - size) // hop + 1
    idx = np.arange(n_frames)[:, None] * hop + np.arange(size)[None, :]
    return x[idx]


def spectrum_bins(residual, hann):
    """frame64 -> remove media -> Hann -> FFT64 -> |.|, um canal por vez.

    Devolve (n_quadros, n_canais, BINS_USED) de magnitudes inteiras, que e o
    que fft_to_mlp_collector escreve no banco de features.
    """
    per_channel = []
    for c in range(residual.shape[1]):
        frames = frame_view(residual[:, c]).astype(np.int64)

        # mean_remover_64_dualmode: soma exata, /64 simetrico, saida Q10.15.
        corrected = frames - round_sym(frames.sum(1, keepdims=True), 6)

        # hann_window_64_dualmode: coeficientes Q1.17, satura em 24 bits.
        windowed = sat24(round_sym(corrected * hann[None, :], 17))

        # fft_64_dualmode com NORMALIZE=1: seis estagios dividindo por 2.
        spec = np.fft.rfft(windowed.astype(np.float64), axis=1)[:, :BINS_USED] / FFT_N
        re = np.rint(spec.real).astype(np.int64)
        im = np.rint(spec.imag).astype(np.int64)

        # |z| ~= max + 0,375*min, a aproximacao do coletor e do modulo MDC.
        hi, lo = np.abs(re), np.abs(im)
        mx, mn = np.maximum(hi, lo), np.minimum(hi, lo)
        per_channel.append(np.minimum(mx + (mn >> 1) - (mn >> 3), DATA_MAX))

    return np.stack(per_channel, 1)


# ---------------------------------------------------------------------------
# Modulo MDC (fft_peak_mdc.sv)
# ---------------------------------------------------------------------------
def mdc_k0(mag_sum, k_max=MDC_K_MAX, k_min=MDC_K_MIN, n_peaks=MDC_N_PEAKS):
    """(k0, valid) por quadro, com o hold do ultimo k0 valido.

    O detector ve a SOMA dos quatro canais -- um somador, e a harmonica de
    rotacao aparece nos quatro. Limiar relativo de 5/32 = 0,15625, que o RTL
    faz com (mx>>3) + (mx>>5); maximo local exige mag[k] > mag[k-1] e
    mag[k] >= mag[k+1], os dois comparadores da janela deslizante.
    """
    k = np.arange(1, k_max + 1)
    band = mag_sum[:, 1:k_max + 1]
    threshold = (band.max(1) >> 3) + (band.max(1) >> 5)

    is_max = (mag_sum[:, k] > mag_sum[:, k - 1]) & (mag_sum[:, k] >= mag_sum[:, k + 1])
    is_peak = is_max & (mag_sum[:, k] >= threshold[:, None])

    k0 = np.zeros(len(mag_sum), np.int64)
    valid = np.zeros(len(mag_sum), bool)
    for f in np.flatnonzero(is_peak.sum(1) >= n_peaks):
        bins = k[is_peak[f]]
        # Empate resolvido pelo bin MAIS BAIXO, como o `>` estrito do RTL:
        # puxa para a fundamental em vez da harmonica.
        top = bins[np.argsort(-mag_sum[f, bins], kind="stable")[:n_peaks]]
        g = int(top[0])
        for b in top[1:]:
            g = np.gcd(g, int(b))
        if g >= k_min:
            k0[f], valid[f] = g, True

    # Resultado invalido segura o ultimo k0 valido: registrador com enable.
    held = np.zeros_like(k0)
    last = 0
    for f in range(len(k0)):
        if valid[f]:
            last = k0[f]
        held[f] = last
    return held, valid


# ---------------------------------------------------------------------------
# Dataset
# ---------------------------------------------------------------------------
def canonical(stem):
    """Os .mat gravam "Unbalalnce" onde os .tdms gravam "Unbalance"; sem
    normalizar, 5 dos 45 ensaios perdem o par e somem do dataset."""
    return stem.replace("Unbalalnce", "Unbalance")


def error_type(name):
    if "BPFI" in name or "BPFO" in name:
        return "Bearing"
    if "Unbalance" in name:
        return "Unbalance"
    if "Misalign" in name:
        return "Misalign"
    if "Normal" in name:
        return "None"
    raise ValueError(f"Tipo de falha desconhecido: {name}")


def find_runs(root):
    """Pareia .mat com .tdms. Aceita tanto o layout com subpastas
    (vibration/, current,temp/) quanto tudo solto na mesma pasta."""
    vib = {canonical(p.stem): p for p in root.rglob("*.mat")}
    cur = {canonical(p.stem): p for p in root.rglob("*.tdms")}
    keys = sorted(vib.keys() & cur.keys())
    if not keys:
        raise SystemExit(f"nenhum par .mat/.tdms em {root}")
    orphans = sorted(vib.keys() ^ cur.keys())
    if orphans:
        print(f"[dataset] sem par, ignorados: {', '.join(orphans)}")
    return keys, vib, cur


def load_vibration(path):
    """(n, 4) float64 + intervalo de amostragem, direto do .mat."""
    signal = sio.loadmat(str(path))["Signal"][0, 0]
    data = signal["y_values"][0, 0][0]

    dt = 1.0 / FS
    if "x_values" in (signal.dtype.names or ()) and signal["x_values"].size:
        x_struct = signal["x_values"][0, 0]
        if "increment" in (x_struct.dtype.names or ()):
            dt = float(np.ravel(x_struct["increment"])[0])

    if data.ndim == 2 and data.shape[1] == 5:      # coluna de tempo a frente
        data = data[:, 1:]
    return np.ascontiguousarray(data), dt


def load_current_temp(path, wanted):
    """(n, len(wanted)) float64 + intervalo. `TdmsFile.open` le canal a canal,
    em vez de carregar o arquivo inteiro na memoria como `read` faz."""
    from nptdms import TdmsFile

    with TdmsFile.open(str(path)) as tdms:
        log = tdms["Log"]
        dt = float(log.channels()[0].properties["wf_increment"])
        columns = [np.asarray(log[TDMS_BY_NAME[name]][:]) for name in wanted]
    return np.column_stack(columns), dt


def empty_phases(keys, cur_by_key):
    """Nos 9 ensaios BPFO as fases V e W foram gravadas vazias. Mante-las viraria
    vazamento de rotulo: "V-phase toda zerada" identificaria Bearing sozinha."""
    from nptdms import TdmsFile

    empty = set()
    for key in keys:
        with TdmsFile.open(str(cur_by_key[key])) as tdms:
            log = tdms["Log"]
            for name in PHASES:
                if len(log[TDMS_BY_NAME[name]]) == 0:
                    empty.add(name)
    return [name for name in PHASES if name not in empty]


def align_to(x, dt_src, n_dst, dt_dst):
    """Reamostra no grid de destino pegando o vizinho mais proximo -- o
    equivalente vetorizado de merge_asof(direction="nearest")."""
    idx = np.rint(np.arange(n_dst) * (dt_dst / dt_src)).astype(np.int64)
    np.clip(idx, 0, len(x) - 1, out=idx)
    return x[idx]


def frame_aggregates(aux, n_frames, n_temp):
    """Media (temperatura) e media dos quadrados (corrente) sobre o MESMO vao
    de cada quadro da FFT: DECIM_RATE * FFT_HOP = 2048 amostras brutas.

    A corrente entra como potencia, nao RMS: a raiz custa CORDIC ou
    Newton-Raphson no FPGA e para o MLP x^2 e uma reparametrizacao monotona da
    mesma grandeza. No RTL sao dois acumuladores por canal, sem guardar o sinal.
    """
    span = DECIM_RATE * FFT_HOP
    usable = aux[:n_frames * span].reshape(n_frames, span, aux.shape[1])
    mean = usable.mean(1)
    msq = (usable * usable).mean(1)
    return np.column_stack([mean[:, :n_temp], msq[:, n_temp:]])


# ---------------------------------------------------------------------------
# Extracao
# ---------------------------------------------------------------------------
def extract_features(root, mu_shift, use_lms, verbose=True):
    """Roda o front end inteiro sobre os 45 ensaios.

    Devolve X no DOMINIO DO HARDWARE: as 128 magnitudes ja sao os inteiros que
    saem da FFT, e as 4 agregadas ja vem multiplicadas por 2^9 -- que e o ganho
    que o host aplica antes de mandar pela UART (ver fft_to_mlp_collector.sv).
    O EXTRA_SHIFT de cada agregada e escolhido depois, na exportacao.
    """
    coeffs = [load_coeff_rom(COEFF_DIR / f"fir/stage{i}_decim{d}_q117.hex")
              for i, d in ((1, 4), (2, 4), (3, 2))]
    hann = load_coeff_rom(COEFF_DIR / "windowing/hann_64_q117.hex")

    keys, vib_by_key, cur_by_key = find_runs(root)
    phases_used = empty_phases(keys, cur_by_key)
    aux_channels = TEMP_CHANNELS + phases_used
    extra_names = [f"{c}_mean" for c in TEMP_CHANNELS] + \
                  [f"{c}_pow" for c in phases_used] + ["mdc_k0"]
    if verbose:
        print(f"[dataset] {len(keys)} ensaios | fases usadas: {phases_used}")

    bins_parts, extra_parts, y_parts, group_parts = [], [], [], []
    lock_rate, tap_last = [], None

    for i, key in enumerate(keys, 1):
        started = time.time()
        raw, dt_vib = load_vibration(vib_by_key[key])
        n_raw = len(raw)

        # ADC -> Q9.15. O dado ja chega quantizado num degrau ~7,8x mais grosso
        # que o LSB do Q9.15, entao a parte fracionaria sobra; o que aperta e a
        # inteira (pico de 161,7 em 4Nm_BPFI_03 contra os +-256 da faixa).
        quantized = sat24(np.rint(raw * (1 << Q_FRAC)).astype(np.int64))

        decimated = np.stack([fir_decimate_32(quantized[:, c], coeffs)
                              for c in range(len(VIB_CHANNELS))], 1)
        del quantized

        if use_lms:
            residual, tap_last = lms_residual(decimated, mu_shift)
        else:
            residual = decimated

        mag = spectrum_bins(residual, hann)             # (n_fr, 4, 32)
        n_frames = min(len(mag), n_raw // (DECIM_RATE * FFT_HOP))
        mag = mag[:n_frames]

        k0, valid = mdc_k0(mag.sum(1))
        lock_rate.append(valid.mean())

        aux, dt_cur = load_current_temp(cur_by_key[key], aux_channels)
        aux = align_to(aux, dt_cur, n_raw, dt_vib)
        agg = frame_aggregates(aux, n_frames, len(TEMP_CHANNELS))
        del aux

        bins_parts.append(mag.reshape(n_frames, -1).astype(np.float32))
        # As quatro agregadas entram no MAC com o mesmo ganho 2^9 dos bins. As
        # tres da UART ja chegam multiplicadas pelo host; o k0 nasce dentro do
        # FPGA como indice de bin puro, e o coletor repoe o 2^9 nele dobrando-o
        # dentro do proprio deslocamento (MDC_NET_SHIFT = 9 + EXTRA_SHIFT[3]).
        extra_parts.append(
            np.column_stack([agg, k0[:n_frames]]).astype(np.float32) * HW_GAIN_BIN)
        y_parts.append(np.full(n_frames, error_type(key)))
        group_parts.append(np.full(n_frames, key))

        if verbose:
            print(f"[{i:2d}/{len(keys)}] {key:<24} {n_frames:5d} quadros  "
                  f"MDC {valid.mean():5.1%}  {time.time() - started:4.1f}s", flush=True)

    X = np.hstack([np.concatenate(bins_parts), np.concatenate(extra_parts)])
    y = np.concatenate(y_parts)
    groups = np.concatenate(group_parts)

    if verbose:
        print(f"\n[front end] X {X.shape} ({X.nbytes / 1e6:.0f} MB)")
        print(f"[front end] MDC trava em {np.mean(lock_rate):.1%} dos quadros "
              f"(media dos ensaios)")
        if tap_last is not None:
            taps = tap_last[:, 0] / 2.0 ** LMS_COEFF_FRAC
            print(f"[front end] taps finais do LMS (canal 0, Q4.20): "
                  f"{np.array2string(taps, precision=3)}")
    return X, y, groups, extra_names


# ---------------------------------------------------------------------------
# Treino e avaliacao
# ---------------------------------------------------------------------------
def forward(W, b, x):
    """ReLU nas ocultas, argmax na saida -- softmax nao muda o argmax, entao o
    hardware nao precisa de exponencial."""
    a = x
    for i, (w, bias) in enumerate(zip(W, b)):
        a = a @ w + bias
        if i < len(W) - 1:
            a = np.maximum(a, 0)
    return a.argmax(axis=1)


def fit_one(X, y, train_idx, hidden, seed, classes):
    """Treino balanceado por reamostragem. Sem isso a classe `None` (3 ensaios
    em 45) some, e a acuracia global esconde o buraco."""
    from sklearn.neural_network import MLPClassifier
    from sklearn.preprocessing import StandardScaler

    rng = np.random.default_rng(seed)
    n = max(np.bincount(y[train_idx], minlength=len(classes)))
    balanced = np.concatenate([rng.choice(train_idx[y[train_idx] == c], n, replace=True)
                               for c in range(len(classes))])

    scaler = StandardScaler().fit(X[balanced])
    clf = MLPClassifier(hidden_layer_sizes=hidden, max_iter=400, random_state=seed,
                        early_stopping=True, n_iter_no_change=12)
    clf.fit(scaler.transform(X[balanced]), y[balanced])
    return clf, scaler


def cross_validate(X, y, groups, hidden, n_splits, seed, classes):
    """Acuracia com os ensaios de teste totalmente fora do treino.

    Split aleatorio de quadros nao mede nada aqui: quadros vizinhos do mesmo
    ensaio sao quase identicos e a acuracia sai perto de 1,0.
    """
    from sklearn.model_selection import StratifiedGroupKFold

    splitter = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=seed)
    accs, conf = [], np.zeros((len(classes),) * 2, int)
    for train_idx, test_idx in splitter.split(X, y, groups):
        clf, scaler = fit_one(X, y, train_idx, hidden, seed, classes)
        pred = clf.predict(scaler.transform(X[test_idx]))
        accs.append((pred == y[test_idx]).mean())
        for true, guess in zip(y[test_idx], pred):
            conf[true, guess] += 1
    return np.array(accs), conf


def report(accs, conf, classes, tag):
    recall = conf.diagonal() / conf.sum(1)
    print(f"\n{tag}")
    print(f"  acuracia     {accs.mean():.3f} +- {accs.std():.3f}   "
          f"(folds: {', '.join(f'{a:.3f}' for a in accs)})")
    print(f"  recall macro {recall.mean():.3f}")
    for name, r in zip(classes, recall):
        print(f"    {name:<10} {r:.3f}")
    return recall


# ---------------------------------------------------------------------------
# Exportacao
# ---------------------------------------------------------------------------
CLIP_GRID = (100.0, 99.9, 99.5, 99.0, 98.0, 95.0)


def quantize(W, b, X_train, bits=8, grid=CLIP_GRID, verbose=True):
    """Quantizacao simetrica por camada, com o limite escolhido no TREINO.

    Max-abs puro nao serve aqui. W0 = W_normalizado / sd, e um bin quase morto
    (desvio ~0) produz um peso ~73x maior que a mediana da camada; esse unico
    peso define o passo do int8 e os outros 1055 perdem resolucao. Medido, e a
    diferenca entre 0,676 e 0,713 de acuracia.

    O corte e escolhido maximizando a concordancia com o proprio modelo float
    nos quadros de TREINO -- nenhum ensaio de teste participa da escolha. Sai
    uma escala float por camada, que e exatamente o que mlp_scales.mem guarda:
    a estrategia muda, o contrato com o RTL nao.
    """
    qmax = 2 ** (bits - 1) - 1
    reference = forward(W, b, X_train)

    best = None
    for percentile in grid:
        scales = [(np.abs(w).max() if percentile == 100.0
                   else np.percentile(np.abs(w), percentile)) / qmax for w in W]
        W_int = [np.clip(np.round(w / s), -qmax, qmax).astype(np.int8)
                 for w, s in zip(W, scales)]
        agreement = (forward([wi * s for wi, s in zip(W_int, scales)], b,
                             X_train) == reference).mean()
        if best is None or agreement > best[0]:
            best = (agreement, percentile, W_int, scales)

    agreement, percentile, W_int, scales = best
    if verbose:
        print(f"[export] int{bits}: corte no percentil {percentile:g} dos pesos, "
              f"concordancia com o float em {agreement:.4%} dos quadros de treino")
    return W_int, scales


def fold_and_quantize(clf, scaler, X_hw, n_bins, extra_names, train_idx, bits=8):
    """Absorve o StandardScaler e a escala das agregadas em W0, depois quantiza.

    (x - mu)/sd @ W0 + b0 e a mesma coisa que x @ W0' + b0', entao o hardware
    alimenta o MLP com a magnitude crua da FFT: sem subtrair media, sem dividir.

    As 4 agregadas estao em outra escala fisica (graus, A^2, indice de bin). Se
    entrarem cruas, W0 fica com faixa de ~50x entre as linhas e a quantizacao
    por camada gasta toda a resolucao no maior peso. Um deslocamento constante
    por entrada -- fiacao no RTL -- iguala o desvio de cada agregada ao desvio
    mediano dos bins e devolve a resolucao.
    """
    W = [w.copy() for w in clf.coefs_]
    b = [bb.copy() for bb in clf.intercepts_]
    W[0] = W[0] / scaler.scale_[:, None]
    b[0] = b[0] - (scaler.mean_ / scaler.scale_) @ clf.coefs_[0]

    extra_shift = np.round(np.log2(np.median(scaler.scale_[:n_bins])
                                   / scaler.scale_[n_bins:])).astype(int)

    # O coletor implementa as agregadas com dois deslocamentos diferentes, e
    # cada um so aceita um sinal. As tres da UART saem de
    # `aux_features[i] >>> (-EXTRA_SHIFT[i])`, que exige deslocamento <= 0; o
    # k0 sai de `mdc_k0 <<< (9 + EXTRA_SHIFT[3])`, que exige a soma >= 0.
    uart_bad = [n for n, s in zip(extra_names[:-1], extra_shift[:-1]) if s > 0]
    if uart_bad:
        print(f"  AVISO: EXTRA_SHIFT positivo em {uart_bad}; "
              "fft_to_mlp_collector.sv so faz deslocamento a direita nessas tres.")
    if int(np.log2(HW_GAIN_BIN)) + extra_shift[-1] < 0:
        print(f"  AVISO: MDC_NET_SHIFT negativo ({int(np.log2(HW_GAIN_BIN))}"
              f" + {extra_shift[-1]}); fft_to_mlp_collector.sv so faz "
              "deslocamento a esquerda no k0.")

    gain = np.concatenate([np.ones(n_bins), 2.0 ** extra_shift])
    W[0] = W[0] / gain[:, None]
    X_shifted = X_hw * gain

    W_int, scales = quantize(W, b, X_shifted[train_idx], bits)
    return W, b, W_int, scales, extra_shift, X_shifted


def write_header(path, W_int, b, scales, extra_shift, extra_names, classes,
                 n_bins, mu_shift, use_lms):
    n_in = W_int[0].shape[0]
    hidden = " -> ".join(str(w.shape[1]) for w in W_int)
    bin_hz = FS / DECIM_RATE / FFT_N
    lines = [
        f"// MLP {n_in}-{hidden.replace(' -> ', '-')} para diagnostico de falhas"
        " -- gerado por Scripts/train_mlp.py",
        f"// entrada 0..{n_bins - 1}: |rFFT| do front end de vibracao do RTL",
        f"//   ADC {FS / 1000:.1f} kHz -> FIR/{DECIM_RATE} -> {FS / DECIM_RATE:.0f} Hz"
        + (f" -> LMS {LMS_TAPS} taps no TEMPO (MU_SHIFT={mu_shift}, residual)"
           if use_lms else " -> (sem LMS)"),
        f"//   -> frame {FFT_N}/hop {FFT_HOP} -> remove media -> Hann"
        f" -> FFT{FFT_N} (/2 por estagio) -> |.| alpha-max-beta-min",
        f"//   {BINS_USED} bins de {bin_hz:.2f} Hz por canal x {len(VIB_CHANNELS)}"
        f" canais; 1x do eixo (50 Hz) no bin {round(50 / bin_hz)}",
        f"//   amostras em Q{Q_INT}.{Q_FRAC} com sinal ({Q_INT + Q_FRAC} bits);"
        f" ganho do caminho 2^{int(np.log2(HW_GAIN_BIN))} ja embutido em W0",
        "//   NAO remover a media do quadro de novo e NAO normalizar: o"
        " StandardScaler e os ganhos ja estao em W0/b0.",
        f"// entrada {n_bins}..{n_in - 1}: agregados do quadro, cada um deslocado"
        " de MLP_EXTRA_SHIFT bits",
        f"//   {', '.join(extra_names)}",
        "//   temperatura = media das amostras do quadro; corrente = media dos"
        " quadrados (sem raiz);",
        f"//   mdc_k0 = bin fundamental do modulo MDC (f0 = k0 * {bin_hz:.2f} Hz),"
        " segurando o ultimo valido",
        "// camada i: acc = (W[i] @ x) * scale[i] + b[i], ReLU nas ocultas,"
        " argmax na saida",
        "",
        f"#define MLP_N_IN {n_in}",
        f"#define MLP_N_BINS {n_bins}",
        f"#define MLP_N_EXTRA {len(extra_shift)}",
        f"#define MLP_N_LAYERS {len(W_int)}",
        f"#define MLP_Q_INT {Q_INT}",
        f"#define MLP_Q_FRAC {Q_FRAC}",
        f"#define MLP_MDC_K_MAX {MDC_K_MAX}",
        f"#define MLP_MDC_K_MIN {MDC_K_MIN}",
        f"#define MLP_MDC_N_PEAKS {MDC_N_PEAKS}",
        "",
        "static const char *MLP_CLASSES[] = {"
        + ", ".join(f'"{c}"' for c in classes) + "};",
        "// deslocamento (bits, com sinal) aplicado a cada entrada agregada antes do MAC",
        f"static const signed char MLP_EXTRA_SHIFT[{len(extra_shift)}] = {{"
        + ", ".join(f"{s:d}" for s in extra_shift) + "};",
        "",
    ]
    for i, (w, bias, scale) in enumerate(zip(W_int, b, scales)):
        lines.append(f"// camada {i}: {w.shape[0]} -> {w.shape[1]}")
        lines.append(f"static const float MLP_SCALE_{i} = {scale:.9g}f;")
        lines.append(f"static const signed char MLP_W{i}[{w.shape[0]}][{w.shape[1]}] = {{")
        lines += [f"    {{{', '.join(f'{v:4d}' for v in row)}}}," for row in w]
        lines.append("};")
        lines.append(f"static const float MLP_B{i}[{len(bias)}] = {{"
                     + ", ".join(f"{v:.9g}f" for v in bias) + "};")
        lines.append("")
    path.write_text("\n".join(lines))


# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dataset", type=Path, default=REPO / (
        "Vibration, Acoustic, Temperature, and Motor Current Dataset of Rotating "
        "Machine Under Varying Load Conditions for Fault Diagnosis"),
        help="pasta com os .mat de vibracao e os .tdms de corrente/temperatura")
    parser.add_argument("--cache", type=Path,
                        help="npz com as features; le se existir, grava se nao")
    parser.add_argument("--out-dir", type=Path, default=REPO / "Scripts/export")
    parser.add_argument("--hidden", default="8,4", help="camadas ocultas")
    parser.add_argument("--folds", type=int, default=3)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--lms-mu-shift", type=int, default=LMS_MU_SHIFT,
                        help="LMS_MU_SHIFT do RTL (16 no build atual)")
    parser.add_argument("--no-lms", action="store_true",
                        help="modela USE_LMS = 0 (o pipeline _no_lms)")
    parser.add_argument("--no-export", action="store_true",
                        help="so avalia, nao escreve pesos")
    args = parser.parse_args()

    hidden = tuple(int(h) for h in args.hidden.split(","))
    use_lms = not args.no_lms

    # -- features ---------------------------------------------------------
    if args.cache and args.cache.exists():
        print(f"[cache] lendo {args.cache}")
        cached = np.load(args.cache, allow_pickle=False)
        X, y, groups = cached["X"], cached["y"], cached["groups"]
        extra_names = [str(n) for n in cached["extra_names"]]
    else:
        X, y, groups, extra_names = extract_features(
            args.dataset, args.lms_mu_shift, use_lms)
        if args.cache:
            args.cache.parent.mkdir(parents=True, exist_ok=True)
            np.savez_compressed(args.cache, X=X, y=y, groups=groups,
                                extra_names=np.array(extra_names))
            print(f"[cache] gravado {args.cache}")

    n_bins = len(VIB_CHANNELS) * BINS_USED
    n_extra = X.shape[1] - n_bins

    from sklearn.preprocessing import LabelEncoder

    encoder = LabelEncoder().fit(y)
    y_int = encoder.transform(y)          # sklearn quebra com rotulo string + early_stopping
    classes = [str(c) for c in encoder.classes_]

    print(f"\n[modelo] {X.shape[1]} entradas ({n_bins} bins + {n_extra} agregadas)"
          f" -> {' -> '.join(map(str, hidden))} -> {len(classes)}")
    print(f"[modelo] classes: {classes}")

    # -- avaliacao honesta, separada por ensaio ---------------------------
    accs, conf = cross_validate(X, y_int, groups, hidden, args.folds, args.seed, classes)
    report(accs, conf, classes,
           f"{args.folds} folds separados por ensaio, treino balanceado:")

    if args.no_export:
        return

    # -- modelo final -----------------------------------------------------
    from sklearn.model_selection import StratifiedGroupKFold

    splitter = StratifiedGroupKFold(n_splits=args.folds, shuffle=True,
                                    random_state=args.seed)
    train_idx, test_idx = next(splitter.split(X, y_int, groups))
    clf, scaler = fit_one(X, y_int, train_idx, hidden, args.seed, classes)
    pred = clf.predict(scaler.transform(X[test_idx]))
    print(f"\n[export] modelo do fold 1: acuracia {(pred == y_int[test_idx]).mean():.3f}"
          f" (o numero honesto e a media dos {args.folds} folds, acima)")

    W, b, W_int, scales, extra_shift, X_shifted = fold_and_quantize(
        clf, scaler, X, n_bins, extra_names, train_idx)

    agree = (forward(W, b, X_shifted[test_idx]) == pred).mean()
    assert agree > 0.999, f"a dobra do scaler divergiu em {1 - agree:.3%} dos quadros"
    print(f"[export] scaler e ganhos absorvidos em W0 -- mesma predicao em {agree:.4%}")
    print("[export] EXTRA_SHIFT: "
          f"{dict(zip(map(str, extra_names), extra_shift.tolist()))}")

    print(f"\n  {'largura':>8}{'acuracia':>10}{'bytes de peso':>15}")
    params = sum(w.size for w in W) + sum(len(bb) for bb in b)
    print(f"  {'float32':>8}"
          f"{(forward(W, b, X_shifted[test_idx]) == y_int[test_idx]).mean():>10.3f}"
          f"{params * 4:>15}")
    for bits, (Wq, sq) in [(8, (W_int, scales))] + [
            (n, quantize(W, b, X_shifted[train_idx], n, verbose=False))
            for n in (6, 4)]:
        dequantized = [w * s for w, s in zip(Wq, sq)]
        print(f"  {'int' + str(bits):>8}"
              f"{(forward(dequantized, b, X_shifted[test_idx]) == y_int[test_idx]).mean():>10.3f}"
              f"{int(np.ceil(params * bits / 8)):>15}")

    # -- arquivos ---------------------------------------------------------
    args.out_dir.mkdir(parents=True, exist_ok=True)
    header = args.out_dir / "mlp_lowband_weights.h"
    write_header(header, W_int, b, scales, extra_shift, extra_names, classes,
                 n_bins, args.lms_mu_shift, use_lms)

    np.savez(args.out_dir / "mlp_lowband_int8.npz",
             **{f"W{i}": w for i, w in enumerate(W_int)},
             **{f"b{i}": bb.astype(np.float32) for i, bb in enumerate(b)},
             **{f"scale{i}": np.float32(s) for i, s in enumerate(scales)},
             extra_names=np.array(extra_names),
             extra_shift=extra_shift.astype(np.int32),
             n_bins_in=np.int32(n_bins), n_extra_in=np.int32(n_extra),
             classes=encoder.classes_,
             bins_hz=np.tile(np.arange(BINS_USED) * (FS / DECIM_RATE / FFT_N),
                             len(VIB_CHANNELS)).astype(np.float32),
             channels=np.repeat(np.array(VIB_CHANNELS), BINS_USED),
             decimation=np.int32(DECIM_RATE), hop=np.int32(FFT_HOP),
             lms_taps=np.int32(LMS_TAPS), lms_mu_shift=np.int32(args.lms_mu_shift),
             lms_domain=np.array("time" if use_lms else "none"),
             mdc_k_max=np.int32(MDC_K_MAX), mdc_k_min=np.int32(MDC_K_MIN),
             mdc_n_peaks=np.int32(MDC_N_PEAKS),
             q_int=np.int32(Q_INT), q_frac=np.int32(Q_FRAC),
             hw_gain_bin=np.float64(HW_GAIN_BIN))
    print(f"\n[export] {header}")
    print(f"[export] {args.out_dir / 'mlp_lowband_int8.npz'}")

    # gen_mlp_weights_sv.py reescreve o pacote de dimensoes e as tres ROMs.
    sys.path.insert(0, str(REPO / "Scripts/export"))
    import gen_mlp_weights_sv as gen

    parsed = gen.parse_header(header.read_text())
    package = REPO / "RTL/mlp_model/mlp_weights.sv"
    package.write_text(gen.generate(parsed, header.name))
    print(f"[export] {package}")
    mem_dir = REPO / "RTL/mem/mlp"
    for name, text in gen.build_roms(parsed).items():
        (mem_dir / name).write_text(text)
        print(f"[export] {mem_dir / name}: {text.count(chr(10))} palavras")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Gera mlp_weights.sv (pacote SystemVerilog) a partir do .h exportado pelo notebook.

O .h guarda W[i] como [entrada][neuronio] e os bias/escalas em float; o RTL quer
W[neuronio][entrada] e tudo inteiro. A conversao segue exatamente o mlp_ref.cpp:

    bias_q  = round(b * 2**Q_FRAC)
    scale_q = round(scale * 2**(2*Q_FRAC))   camada 0, entrada inteira crua
    scale_q = round(scale * 2**Q_FRAC)       demais camadas, entrada Q15

Uso:
    python3 gen_mlp_weights_sv.py mlp_lowband_weights.h ../../RTL/mlp_model/mlp_weights.sv
"""

import re
import struct
import sys
from pathlib import Path


def f32(v):
    """O .h guarda bias/escala como `float`; o C++ le esse valor de 32 bits antes de
    quantizar. Sem arredondar aqui, bias exatamente em .5 (b0[5]) caem para o outro
    lado e o RTL deixa de bater com o mlp_ref.cpp por 1 LSB."""
    return struct.unpack("f", struct.pack("f", v))[0]


def parse_header(text):
    def define(name):
        return int(re.search(rf"#define {name}\s+(-?\d+)", text).group(1))

    def floats(name):
        body = re.search(rf"{name}\[\d+\]\s*=\s*{{(.*?)}}", text, re.S).group(1)
        return [f32(float(v.strip().rstrip("f"))) for v in body.split(",")]

    def scale(i):
        return f32(float(re.search(rf"MLP_SCALE_{i}\s*=\s*([-\d.e+]+)f", text).group(1)))

    def matrix(name):
        body = re.search(rf"{name}\[\d+\]\[\d+\]\s*=\s*{{(.*?)\n}};", text, re.S).group(1)
        return [[int(v) for v in row.split(",")]
                for row in re.findall(r"{([^{}]*)}", body)]

    def shifts():
        body = re.search(r"MLP_EXTRA_SHIFT\[\d+\]\s*=\s*{(.*?)}", text, re.S).group(1)
        return [int(v) for v in body.split(",")]

    n_layers = define("MLP_N_LAYERS")
    return {
        "n_in": define("MLP_N_IN"),
        "n_bins": define("MLP_N_BINS"),
        "n_extra": define("MLP_N_EXTRA"),
        "q_int": define("MLP_Q_INT"),
        "q_frac": define("MLP_Q_FRAC"),
        "extra_shift": shifts(),
        "classes": re.findall(r'"([^"]+)"', re.search(
            r"MLP_CLASSES\[\]\s*=\s*{(.*?)}", text, re.S).group(1)),
        "w": [matrix(f"MLP_W{i}") for i in range(n_layers)],
        "b": [floats(f"MLP_B{i}") for i in range(n_layers)],
        "scale": [scale(i) for i in range(n_layers)],
    }


def q_round(v):
    """round-half-away-from-zero, igual ao llround() do mlp_ref.cpp."""
    return int(v + 0.5) if v >= 0 else -int(-v + 0.5)


def sv_int(v, width, suffix="sd"):
    return f"-{width}'{suffix}{-v}" if v < 0 else f"{width}'{suffix}{v}"


def build_roms(h):
    """Os tres arquivos .mem lidos por $readmemh em mlp.sv.

    mlp_weights.mem e LANE-MAJOR: a lane n do banco de MACs guarda, em taps
    consecutivos, todo peso que ela precisa nas tres camadas --

        offset 0             .. N_IN-1        camada 0, W0[entrada][n]
        offset N_IN          .. N_IN+N_H0-1   camada 1, W1[entrada][n]
        offset N_IN+N_H0     .. W_DEPTH-1     camada 2, W2[entrada][n]

    Assim as N_H0 lanes compartilham um unico contador de tap e diferem so
    pela base. As lanes que nao existem numa camada (n >= N_H1 na 1, n >= N_OUT
    na 2) sao preenchidas com zero, o que dispensa o mux de selecao no RTL.

    mlp_biases.mem / mlp_scales.mem sao NEURON-MAJOR: bloco da camada 0, depois
    o da 1, depois o da 2. A escala e a mesma para todos os neuronios de uma
    camada; ela e repetida por neuronio porque a ROM e endereçada pelo indice
    do neuronio.
    """
    q = h["q_frac"]
    acc_w = h["q_int"] + h["q_frac"]
    n_in = h["n_in"]
    n_h = [len(b) for b in h["b"]]
    depth = n_in + n_h[0] + n_h[1]          # taps por lane
    bases = [0, n_in, n_in + n_h[0]]        # base de cada camada dentro da lane

    weights = []
    for lane in range(n_h[0]):
        for off in range(depth):
            layer = 2 if off >= bases[2] else (1 if off >= bases[1] else 0)
            w = h["w"][layer]
            weights.append(w[off - bases[layer]][lane] if lane < n_h[layer] else 0)

    biases, scales = [], []
    for i, (b, s) in enumerate(zip(h["b"], h["scale"])):
        # camada 0 recebe inteiro cru (nao Q15), entao a escala carrega 2**(2*Q_FRAC)
        scale_q = q_round(s * 2.0 ** ((2 * q) if i == 0 else q))
        for v in b:
            biases.append(q_round(v * 2 ** q))
            scales.append(scale_q)

    def hexdump(values, width, name):
        """O mascaramento para complemento de dois esconderia um estouro: um
        bias de 2^24 viraria 0 no .mem e o RTL classificaria errado sem nenhum
        aviso. Entao conferimos a faixa antes de mascarar."""
        lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
        bad = [v for v in values if not lo <= v <= hi]
        if bad:
            raise ValueError(
                f"{name}: {len(bad)} valor(es) fora de {width} bits com sinal "
                f"[{lo}, {hi}], pior caso {max(bad, key=abs)}. "
                "Reduza a escala da camada ou aumente ACC_WIDTH no RTL.")
        digits = width // 4
        return "".join(f"{v & ((1 << width) - 1):0{digits}X}\n" for v in values)

    return {
        "mlp_weights.mem": hexdump(weights, 8, "mlp_weights.mem"),
        "mlp_biases.mem": hexdump(biases, acc_w, "mlp_biases.mem"),
        "mlp_scales.mem": hexdump(scales, acc_w, "mlp_scales.mem"),
    }


def generate(h, src_name):
    """O pacote SystemVerilog. Guarda so dimensoes e o mapa das ROMs -- os pesos
    moram nos .mem desde que passaram a ser lidos por $readmemh (M10K)."""
    q = h["q_frac"]
    acc_w = h["q_int"] + h["q_frac"]
    n_h = [len(b) for b in h["b"]]
    depth = h["n_in"] + n_h[0] + n_h[1]

    out = [
        f"// Gerado por Scripts/export/gen_mlp_weights_sv.py a partir de {src_name}.",
        "// NAO editar a mao: rode o gerador de novo depois de retreinar o modelo.",
        f"// Classes (indice do argmax): {', '.join(h['classes'])}",
        "//",
        "// Os pesos NAO ficam mais aqui: foram para RTL/mem/mlp/*.mem, carregados",
        "// por $readmemh em arrays de leitura sincrona (inferencia de M10K).",
        "// Este pacote guarda so as dimensoes e o mapa de enderecos das ROMs.",
        "",
        "package mlp_weights_pkg;",
        "",
        "    localparam int W_WIDTH   = 8;   // weight width",
        f"    localparam int ACC_WIDTH = {acc_w};  // bias / scale / activation width",
        f"    localparam int Q_FRAC    = {q};",
        "",
        f"    localparam int N_IN  = {h['n_in']};",
        f"    localparam int N_H0  = {n_h[0]};",
        f"    localparam int N_H1  = {n_h[1]};",
        f"    localparam int N_OUT = {n_h[2]};",
        "",
        "    // entradas 0..N_BINS-1  : |rFFT| da banda baixa (Q9.15, ganho 2^9 no W0)",
        "    // entradas N_BINS..N_IN-1: agregados do quadro, cada um deslocado de",
        "    //                          EXTRA_SHIFT bits ANTES de entrar em `features`",
        "    //                          (negativo = deslocamento a direita).",
        f"    localparam int N_BINS  = {h['n_bins']};",
        f"    localparam int N_EXTRA = {h['n_extra']};",
        f"    localparam int EXTRA_SHIFT [{h['n_extra']}] = "
        "'{" + ", ".join(str(s) for s in h["extra_shift"]) + "};",
        "",
        "    // ---------------------------------------------------------------",
        "    // ROM layout (see build_roms() in the generator)",
        "    // ---------------------------------------------------------------",
        "    // mlp_weights.mem -- lane-major, one 8-bit weight per line.",
        "    //   lane n holds every weight MAC lane n needs, so all lanes share",
        "    //   one tap offset and differ only by their lane base:",
        "    //     offset 0            .. N_IN-1           : layer 0",
        "    //     offset N_IN         .. N_IN+N_H0-1      : layer 1",
        "    //     offset N_IN+N_H0    .. W_DEPTH-1        : layer 2",
        "    //   lanes >= N_H1 / N_OUT are zero-filled for layers 1 / 2, which is",
        "    //   what retires the old `(n < N_H1) ? ... : '0` select in RTL.",
        "    // The lane count is N_H0 (== N_MAC in mlp.sv); it is not redeclared",
        "    // here so the module's own localparam stays the single definition.",
        f"    localparam int W_DEPTH = N_IN + N_H0 + N_H1;   // {h['n_in']} + "
        f"{n_h[0]} + {n_h[1]} = {depth} taps per lane",
        f"    localparam int W_WORDS = N_H0 * W_DEPTH;       // {n_h[0]} * {depth} "
        f"= {n_h[0] * depth} words",
        "",
        "    // mlp_biases.mem / mlp_scales.mem -- neuron-major, one ACC_WIDTH word",
        "    // per line: layer 0 block, then layer 1, then layer 2.",
        f"    localparam int NB_WORDS = N_H0 + N_H1 + N_OUT;  // {n_h[0]} + {n_h[1]}"
        f" + {n_h[2]} = {sum(n_h)} words",
        "",
        "endpackage",
        "",
    ]
    return "\n".join(out)


def main():
    src = Path(sys.argv[1] if len(sys.argv) > 1 else "mlp_lowband_weights.h")
    rtl = Path(__file__).parents[2] / "RTL"
    dst = Path(sys.argv[2] if len(sys.argv) > 2 else rtl / "mlp_model/mlp_weights.sv")
    mem_dir = Path(sys.argv[3] if len(sys.argv) > 3 else rtl / "mem/mlp")

    h = parse_header(src.read_text())
    dst.write_text(generate(h, src.name))
    print(f"{dst}: {h['n_in']} entradas, camadas "
          f"{' -> '.join(str(len(b)) for b in h['b'])}")

    mem_dir.mkdir(parents=True, exist_ok=True)
    for name, text in build_roms(h).items():
        (mem_dir / name).write_text(text)
        print(f"{mem_dir / name}: {text.count(chr(10))} palavras")


if __name__ == "__main__":
    main()

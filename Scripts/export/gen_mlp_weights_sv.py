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


def emit_matrix(name, w_t, w_width, per_line=8):
    """w_t ja transposto: [neuronio][entrada]."""
    lines = [f"    parameter logic signed [W_WIDTH-1:0] {name} "
             f"[{len(w_t)}][{len(w_t[0])}] = '{{"]
    for n, row in enumerate(w_t):
        lines.append(f"        // neuron {n}")
        chunks = [row[i:i + per_line] for i in range(0, len(row), per_line)]
        body = [", ".join(f"{sv_int(v, w_width):>8}" for v in c) for c in chunks]
        for k, line in enumerate(body):
            open_b = "'{" if k == 0 else "  "
            close = "," if k < len(body) - 1 else (" }" if n == len(w_t) - 1 else " },")
            lines.append(f"        {open_b}{line}{close}")
    lines.append("    };")
    return lines


def generate(h, src_name):
    q = h["q_frac"]
    acc_w = h["q_int"] + h["q_frac"]
    n_h = [len(h["b"][i]) for i in range(len(h["b"]))]

    out = [
        f"// Gerado por Scripts/export/gen_mlp_weights_sv.py a partir de {src_name}.",
        "// NAO editar a mao: rode o gerador de novo depois de retreinar o modelo.",
        f"// Classes (indice do argmax): {', '.join(h['classes'])}",
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
    ]

    for i, (w, b, s) in enumerate(zip(h["w"], h["b"], h["scale"])):
        w_t = [[w[r][c] for r in range(len(w))] for c in range(len(w[0]))]
        relu = "linear -- logits, NO ReLU, argmax outside" if i == len(h["w"]) - 1 \
            else "ReLU"
        # camada 0 recebe inteiro cru (nao Q15), entao a escala carrega 2**(2*Q_FRAC)
        shift = 2 * q if i == 0 else q
        scale_q = q_round(s * 2.0 ** shift)
        dom = "raw integer input" if i == 0 else "Q15 input"

        out += [
            "    " + "-" * 63,
            f"    // Layer {i} : {len(w)} -> {len(w[0])}   ({relu})",
            "    " + "-" * 63,
        ]
        out += emit_matrix(f"L{i}_W", w_t, 8)
        out.append(f"    parameter logic signed [ACC_WIDTH-1:0] L{i}_B [{len(b)}] = '{{"
                   + ", ".join(sv_int(q_round(v * 2 ** q), acc_w) for v in b) + "};")
        out.append(f"    // float scale = {s:.9g}  ->  round(scale * 2**{shift})"
                   f" = {scale_q}   ({dom})")
        out.append(f"    parameter logic signed [ACC_WIDTH-1:0] L{i}_SCALE [{len(b)}] = "
                   "'{" + ", ".join([sv_int(scale_q, acc_w)] * len(b)) + "};")
        out.append("")

    out += ["endpackage", ""]
    # o "// ---" das bordas de camada usa o mesmo comprimento do arquivo original
    return "\n".join(out).replace("    " + "-" * 63,
                                  "    // " + "-" * 63)


def main():
    src = Path(sys.argv[1] if len(sys.argv) > 1 else "mlp_lowband_weights.h")
    dst = Path(sys.argv[2] if len(sys.argv) > 2
               else Path(__file__).parents[2] / "RTL/mlp_model/mlp_weights.sv")
    h = parse_header(src.read_text())
    dst.write_text(generate(h, src.name))
    print(f"{dst}: {h['n_in']} entradas, camadas "
          f"{' -> '.join(str(len(b)) for b in h['b'])}")


if __name__ == "__main__":
    main()

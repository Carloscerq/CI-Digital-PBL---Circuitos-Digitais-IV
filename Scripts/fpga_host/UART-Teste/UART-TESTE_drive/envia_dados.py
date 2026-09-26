from pathlib import Path
import serial
import time


# ============================================================
# CONFIGURACAO
# ============================================================

CASO = "4Nm_Normal"

PORTA = "/dev/ttyUSB0"
# No Windows poderia ser, por exemplo:
# PORTA = "COM5"

BAUD = 115200

NUM_SENSORES = 4

# Para o primeiro teste:
MAX_INSTANTES = 100


# ============================================================
# CAMINHOS
# ============================================================

BASE_DIR = Path(__file__).resolve().parent

DATASET_DIR = BASE_DIR / "dataset_q915"

CASE_DIR = DATASET_DIR / CASO


# ============================================================
# LEITURA .MEM
# ============================================================

def ler_mem(caminho):

    valores = []

    with caminho.open("r") as arquivo:

        for numero_linha, linha in enumerate(arquivo, start=1):

            linha = linha.strip()

            if not linha:
                continue

            if linha.startswith("#"):
                continue

            if linha.startswith("//"):
                continue

            if linha.lower().startswith("0x"):
                linha = linha[2:]

            linha = linha.replace("_", "")

            try:
                valor = int(linha, 16)

            except ValueError:

                raise ValueError(
                    f"{caminho}: linha {numero_linha} invalida"
                )

            if valor > 0xFFFFFF:

                raise ValueError(
                    f"{caminho}: linha {numero_linha} "
                    "possui mais de 24 bits"
                )

            valores.append(valor)

    return valores


# ============================================================
# CONVERTE UMA AMOSTRA DE 24 BITS EM 3 BYTES
# ============================================================

def pack24(valor):

    valor &= 0xFFFFFF

    return bytes([
        (valor >> 16) & 0xFF,
        (valor >> 8) & 0xFF,
        valor & 0xFF
    ])


# ============================================================
# CARREGA OS QUATRO SENSORES
# ============================================================

dados = []

print("=" * 70)
print("ENVIO UART - DATASET Q9.15 - 4 SENSORES")
print("=" * 70)

print(f"Caso  : {CASO}")
print(f"Porta : {PORTA}")
print(f"Baud  : {BAUD}")
print()

for sensor in range(1, NUM_SENSORES + 1):

    arquivo = (
        CASE_DIR /
        f"{CASO}_sensor{sensor}.mem"
    )

    if not arquivo.is_file():

        raise FileNotFoundError(
            f"Arquivo nao encontrado:\n{arquivo}"
        )

    print(f"Lendo {arquivo.name}...")

    valores = ler_mem(arquivo)

    dados.append(valores)

    print(
        f"  {len(valores)} amostras carregadas"
    )


# ============================================================
# CONFERE TAMANHOS
# ============================================================

tamanhos = [len(x) for x in dados]

if len(set(tamanhos)) != 1:

    raise RuntimeError(
        f"Sensores possuem tamanhos diferentes: {tamanhos}"
    )


num_amostras = tamanhos[0]

if MAX_INSTANTES == 0:
    quantidade_envio = num_amostras
else:
    quantidade_envio = min(
        MAX_INSTANTES,
        num_amostras
    )


print()
print(f"Amostras disponiveis : {num_amostras}")
print(f"Instantes a enviar    : {quantidade_envio}")
print(
    f"Bytes a enviar        : "
    f"{quantidade_envio * 12}"
)


# ============================================================
# ABRE UART
# ============================================================

print()
print(f"Abrindo porta {PORTA}...")

with serial.Serial(
    port=PORTA,
    baudrate=BAUD,
    bytesize=8,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_ONE,
    timeout=1
) as ser:

    time.sleep(0.5)

    ser.reset_input_buffer()
    ser.reset_output_buffer()

    print("Porta aberta.")
    print()
    print("Iniciando transmissao...")
    print()

    inicio = time.time()

    for n in range(quantidade_envio):

        pacote = bytearray()

        # sensor 1
        pacote.extend(pack24(dados[0][n]))

        # sensor 2
        pacote.extend(pack24(dados[1][n]))

        # sensor 3
        pacote.extend(pack24(dados[2][n]))

        # sensor 4
        pacote.extend(pack24(dados[3][n]))

        # ----------------------------------------------------
        # pacote possui exatamente 12 bytes
        # ----------------------------------------------------

        ser.write(pacote)

        # Mostra os primeiros 10 no terminal
        if n < 10:

            print(
                f"{n:4d}: "
                + " ".join(
                    f"{byte:02X}"
                    for byte in pacote
                )
            )

    ser.flush()

    tempo = time.time() - inicio


print()
print("=" * 70)
print("TRANSMISSAO CONCLUIDA")
print("=" * 70)

print(f"Instantes enviados : {quantidade_envio}")
print(f"Bytes enviados     : {quantidade_envio * 12}")
print(f"Tempo              : {tempo:.3f} s")
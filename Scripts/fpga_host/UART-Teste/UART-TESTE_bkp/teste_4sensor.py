from pathlib import Path
import serial
import time


# ============================================================
# CONFIGURACAO
# ============================================================

CASO = "4Nm_Normal"

NUM_SENSORES = 4
FRAC_BITS = 15

# Porta detectada pelo HW-598 / CP2102
PORTA = "/dev/ttyUSB0"

# Deve ser o mesmo baud usado no FPGA
BAUD = 115200

# Quantos instantes enviar neste teste.
# Cada instante = 4 sensores = 12 bytes
MAX_INSTANTES = 100

# Quantos pacotes mostrar no terminal
PRINT_PACOTES = 10


# ============================================================
# CAMINHOS
# ============================================================

BASE_DIR = Path(__file__).resolve().parent

DATASET_DIR = BASE_DIR / "dataset_q915"

CASE_DIR = DATASET_DIR / CASO


# ============================================================
# CONVERSAO
# ============================================================

def signed24(valor):
    """
    Interpreta 24 bits em complemento de dois.
    """

    valor &= 0xFFFFFF

    if valor & 0x800000:
        return valor - 0x1000000

    return valor


def q915_float(valor):
    """
    Converte Q9.15 para float somente para visualizacao.
    """

    return signed24(valor) / (1 << FRAC_BITS)


def pack24(valor):
    """
    Divide uma amostra de 24 bits em 3 bytes.

    Exemplo:
        FFB75B -> FF B7 5B
    """

    valor &= 0xFFFFFF

    return bytes([
        (valor >> 16) & 0xFF,
        (valor >> 8)  & 0xFF,
        valor         & 0xFF
    ])


# ============================================================
# LE UMA LINHA .MEM
# ============================================================

def converter_linha(linha, arquivo, numero_linha):

    linha = linha.strip()

    if not linha:
        return None

    if linha.startswith("#"):
        return None

    if linha.startswith("//"):
        return None

    if linha.lower().startswith("0x"):
        linha = linha[2:]

    linha = linha.replace("_", "")

    try:
        valor = int(linha, 16)

    except ValueError:
        raise ValueError(
            f"{arquivo}: linha {numero_linha}: "
            f"valor invalido '{linha}'"
        )

    if valor < 0 or valor > 0xFFFFFF:
        raise ValueError(
            f"{arquivo}: linha {numero_linha}: "
            f"valor fora de 24 bits: {linha}"
        )

    return valor


# ============================================================
# LOCALIZA OS QUATRO ARQUIVOS
# ============================================================

arquivos = []

for sensor in range(1, NUM_SENSORES + 1):

    caminho = (
        CASE_DIR /
        f"{CASO}_sensor{sensor}.mem"
    )

    if not caminho.is_file():
        raise FileNotFoundError(
            f"Arquivo nao encontrado:\n{caminho}"
        )

    arquivos.append(caminho)


# ============================================================
# CABECALHO DO TESTE
# ============================================================

print("=" * 80)
print("TESTE DE ENVIO UART - DATASET Q9.15 - 4 SENSORES")
print("=" * 80)

print(f"Caso          : {CASO}")
print(f"Porta serial  : {PORTA}")
print(f"Baud rate     : {BAUD}")
print(f"Instantes     : {MAX_INSTANTES}")
print(f"Bytes/instante: 12")
print(f"Bytes previstos: {MAX_INSTANTES * 12}")

print()

for sensor, arquivo in enumerate(arquivos, start=1):
    print(f"Sensor {sensor}: {arquivo.name}")


# ============================================================
# ABRE OS QUATRO ARQUIVOS
# ============================================================

files = [
    arquivo.open("r")
    for arquivo in arquivos
]


try:

    # ========================================================
    # ABRE A PORTA SERIAL
    # ========================================================

    print()
    print(f"Abrindo {PORTA}...")

    with serial.Serial(
        port=PORTA,
        baudrate=BAUD,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=1
    ) as ser:

        time.sleep(0.5)

        ser.reset_input_buffer()
        ser.reset_output_buffer()

        print("Porta aberta com sucesso.")
        print()
        print("=" * 80)
        print("INICIANDO TRANSMISSAO")
        print("=" * 80)

        inicio = time.time()

        instante = 0
        total_bytes = 0

        # ====================================================
        # LE OS 4 SENSORES EM PARALELO
        # ====================================================

        while instante < MAX_INSTANTES:

            valores = []

            fim_dataset = False

            # ------------------------------------------------
            # Pega uma amostra de cada sensor
            # ------------------------------------------------

            for sensor in range(NUM_SENSORES):

                while True:

                    linha = files[sensor].readline()

                    if linha == "":
                        fim_dataset = True
                        break

                    valor = converter_linha(
                        linha,
                        arquivos[sensor],
                        instante + 1
                    )

                    if valor is not None:
                        valores.append(valor)
                        break

                if fim_dataset:
                    break

            if fim_dataset:
                print()
                print("Fim do dataset encontrado.")
                break

            if len(valores) != 4:
                raise RuntimeError(
                    "Nao foi possivel obter uma amostra "
                    "de cada um dos 4 sensores."
                )

            # =================================================
            # MONTA O PACOTE DE 12 BYTES
            # =================================================

            pacote = bytearray()

            for valor in valores:
                pacote.extend(pack24(valor))

            # =================================================
            # ENVIA PELO HW-598
            # =================================================

            escritos = ser.write(pacote)

            if escritos != 12:
                raise RuntimeError(
                    f"Esperado enviar 12 bytes, "
                    f"mas apenas {escritos} foram aceitos."
                )

            total_bytes += escritos

            # =================================================
            # MOSTRA APENAS OS PRIMEIROS PACOTES
            # =================================================

            if instante < PRINT_PACOTES:

                print()
                print(f"Instante {instante}")

                for sensor in range(NUM_SENSORES):

                    raw = valores[sensor]

                    b = pack24(raw)

                    print(
                        f"  S{sensor + 1}: "
                        f"HEX={raw:06X} | "
                        f"Q9.15={q915_float(raw):10.6f} | "
                        f"UART="
                        f"{b[0]:02X} "
                        f"{b[1]:02X} "
                        f"{b[2]:02X}"
                    )

                print(
                    "  PACOTE: "
                    + " ".join(
                        f"{byte:02X}"
                        for byte in pacote
                    )
                )

            instante += 1

        # Garante que tudo foi entregue ao driver serial
        ser.flush()

        fim = time.time()


    # ========================================================
    # RESUMO
    # ========================================================

    tempo = fim - inicio

    print()
    print("=" * 80)
    print("RESUMO DA TRANSMISSAO")
    print("=" * 80)

    print(f"Instantes enviados : {instante}")
    print(f"Amostras enviadas  : {instante * 4}")
    print(f"Bytes enviados     : {total_bytes}")
    print(f"Tempo              : {tempo:.3f} s")

    if tempo > 0:
        print(
            f"Taxa efetiva       : "
            f"{total_bytes / tempo:.1f} bytes/s"
        )

    print()
    print("Teste concluido.")


finally:

    # ========================================================
    # FECHA OS ARQUIVOS
    # ========================================================

    for f in files:
        f.close()
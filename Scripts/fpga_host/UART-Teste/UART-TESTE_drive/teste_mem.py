from pathlib import Path


# ============================================================
# CONFIGURACAO
# ============================================================

CASO = "4Nm_Normal"
SENSOR = 1

FRAC_BITS = 15
WORD_BITS = 24


# ============================================================
# CAMINHOS
# ============================================================

# Pasta onde este script esta localizado:
#
# UART-TESTE/
BASE_DIR = Path(__file__).resolve().parent

# UART-TESTE/dataset_q915
DATASET_DIR = BASE_DIR / "dataset_q915"

# UART-TESTE/dataset_q915/4Nm_Normal
CASE_DIR = DATASET_DIR / CASO

# UART-TESTE/dataset_q915/4Nm_Normal/4Nm_Normal_sensor1.mem
ARQUIVO = CASE_DIR / f"{CASO}_sensor{SENSOR}.mem"


# ============================================================
# CONVERSAO Q9.15
# ============================================================

def signed24(valor):
    """
    Interpreta um valor de 24 bits em complemento de dois.
    """

    valor &= 0xFFFFFF

    if valor & 0x800000:
        return valor - 0x1000000

    return valor


def q915_float(valor):
    """
    Converte o valor bruto Q9.15 para float.
    Apenas para visualizacao.
    """

    return signed24(valor) / (1 << FRAC_BITS)


# ============================================================
# EMPACOTAMENTO PARA UART
# ============================================================

def empacotar_24bits(valor):
    """
    Divide uma palavra de 24 bits em 3 bytes.

    Exemplo:

        FFB75B

    vira:

        FF B7 5B
    """

    valor &= 0xFFFFFF

    return bytes([
        (valor >> 16) & 0xFF,
        (valor >> 8)  & 0xFF,
        valor         & 0xFF
    ])


# ============================================================
# VERIFICACAO DO ARQUIVO
# ============================================================

print("=" * 75)
print("TESTE DE LEITURA DO DATASET Q9.15")
print("=" * 75)

print(f"Dataset : {DATASET_DIR}")
print(f"Caso    : {CASO}")
print(f"Sensor  : {SENSOR}")
print(f"Arquivo : {ARQUIVO}")
print()


if not DATASET_DIR.is_dir():
    raise FileNotFoundError(
        f"Pasta dataset_q915 nao encontrada:\n{DATASET_DIR}"
    )


if not CASE_DIR.is_dir():
    raise FileNotFoundError(
        f"Pasta do caso nao encontrada:\n{CASE_DIR}"
    )


if not ARQUIVO.is_file():
    raise FileNotFoundError(
        f"Arquivo do sensor nao encontrado:\n{ARQUIVO}"
    )


# ============================================================
# LEITURA
# ============================================================

quantidade = 0

valor_min = None
valor_max = None

PRINT_AMOSTRAS = 20


with ARQUIVO.open("r") as f:

    for numero_linha, linha in enumerate(f, start=1):

        # Remove espacos
        linha = linha.strip()

        # Ignora linha vazia
        if not linha:
            continue

        # Ignora comentarios simples
        if linha.startswith("#"):
            continue

        if linha.startswith("//"):
            continue

        # Remove eventual 0x
        if linha.lower().startswith("0x"):
            linha = linha[2:]

        # Remove underscores, se existirem
        linha = linha.replace("_", "")

        try:
            valor_raw = int(linha, 16)

        except ValueError:
            raise ValueError(
                f"Linha {numero_linha}: "
                f"valor hexadecimal invalido: {linha}"
            )

        # Garante que o dado cabe em 24 bits
        if valor_raw > 0xFFFFFF:
            raise ValueError(
                f"Linha {numero_linha}: "
                f"valor maior que 24 bits: {linha}"
            )

        valor_signed = signed24(valor_raw)

        # Atualiza minimo e maximo
        if valor_min is None or valor_signed < valor_min:
            valor_min = valor_signed

        if valor_max is None or valor_signed > valor_max:
            valor_max = valor_signed

        # Empacota como seria enviado pela UART
        bytes_uart = empacotar_24bits(valor_raw)

        # Mostra apenas as primeiras amostras
        if quantidade < PRINT_AMOSTRAS:

            print(
                f"Amostra {quantidade:6d} | "
                f"HEX = {valor_raw:06X} | "
                f"INT = {valor_signed:8d} | "
                f"Q9.15 = {q915_float(valor_raw):10.6f} | "
                f"UART = "
                f"{bytes_uart[0]:02X} "
                f"{bytes_uart[1]:02X} "
                f"{bytes_uart[2]:02X}"
            )

        quantidade += 1


# ============================================================
# RESUMO
# ============================================================

print()
print("=" * 75)
print("RESUMO")
print("=" * 75)

print(f"Total de amostras : {quantidade}")
print(f"Bytes por amostra : 3")
print(f"Total de bytes    : {quantidade * 3}")

if quantidade > 0:

    print()
    print(
        f"Menor valor inteiro : {valor_min}"
    )

    print(
        f"Maior valor inteiro : {valor_max}"
    )

    print(
        f"Menor valor Q9.15   : "
        f"{valor_min / (1 << FRAC_BITS):.6f}"
    )

    print(
        f"Maior valor Q9.15   : "
        f"{valor_max / (1 << FRAC_BITS):.6f}"
    )

print()
print("Teste concluido.")
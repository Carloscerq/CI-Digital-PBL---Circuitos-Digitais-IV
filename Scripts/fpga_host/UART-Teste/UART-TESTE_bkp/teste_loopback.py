import serial
import time

PORTA = "/dev/ttyUSB0"
BAUD = 115200

dados = bytes([
    0xFF, 0xB7, 0x5B,
    0x01, 0x41, 0xA5,
    0xFF, 0xF4, 0x34,
    0xFF, 0xA1, 0x65
])

print("Enviado:")
print(" ".join(f"{x:02X}" for x in dados))

with serial.Serial(
    port=PORTA,
    baudrate=BAUD,
    bytesize=8,
    parity=serial.PARITY_NONE,
    stopbits=1,
    timeout=2
) as ser:

    time.sleep(0.5)

    ser.reset_input_buffer()

    ser.write(dados)
    ser.flush()

    recebido = ser.read(len(dados))

print()
print("Recebido:")
print(" ".join(f"{x:02X}" for x in recebido))

print()

if recebido == dados:
    print("PASSOU - loopback USB/UART funcionando corretamente")
else:
    print("FALHOU")
    print(f"Esperados : {len(dados)} bytes")
    print(f"Recebidos : {len(recebido)} bytes")
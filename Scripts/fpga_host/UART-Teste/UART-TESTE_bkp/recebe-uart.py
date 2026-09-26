import serial

PORTA = "COM5"
BAUD = 115200

ser = serial.Serial(PORTA, BAUD, timeout=1)

print("Recebendo...")

try:
    while True:
        dado = ser.read(1)

        if dado:
            valor = dado[0]
            print(f"0x{valor:02X}  {valor}")

except KeyboardInterrupt:
    pass

finally:
    ser.close()
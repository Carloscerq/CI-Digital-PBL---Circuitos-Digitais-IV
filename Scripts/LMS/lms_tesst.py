
TAPS = 4

mu = 0.01



w0 = 0.0
w1 = 0.0
w2 = 0.0
w3 = 0.0



x0 = 0.0
x1 = 0.0
x2 = 0.0
x3 = 0.0



x = [
    0.10,
    0.20,
    0.30,
    0.40,
    0.50,
    0.40,
    0.30,
    0.20,
    0.10
]

d = [
    0.15,
    0.30,
    0.45,
    0.60,
    0.75,
    0.60,
    0.45,
    0.30,
    0.15
]



for n in range(len(x)):



    x3 = x2
    x2 = x1
    x1 = x0
    x0 = x[n]


    y = (
        w0 * x0 +
        w1 * x1 +
        w2 * x2 +
        w3 * x3
    )


    erro = d[n] - y



    w0 = w0 + mu * erro * x0
    w1 = w1 + mu * erro * x1
    w2 = w2 + mu * erro * x2
    w3 = w3 + mu * erro * x3



    print("--------------------------------------------------")

    print("Amostra:", n)

    print("x =", x[n])
    print("d =", d[n])

    print("y =", y)

    print("erro =", erro)

    print("w0 =", w0)
    print("w1 =", w1)
    print("w2 =", w2)
    print("w3 =", w3)

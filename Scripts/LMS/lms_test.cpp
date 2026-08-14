#include <stdio.h>

#define N_TAPS 4
#define N_AMOSTRAS 10

int main()
{
    int n;
    int i;


    double mu = 0.01;


    double w[N_TAPS] = {0.0, 0.0, 0.0, 0.0};


    double x_reg[N_TAPS] = {0.0, 0.0, 0.0, 0.0};


    double x[N_AMOSTRAS] = {
        1.0,
        2.0,
        3.0,
        4.0,
        5.0,
        6.0,
        7.0,
        8.0,
        9.0,
        10.0
    };

    double d[N_AMOSTRAS] = {
        2.0,
        4.0,
        6.0,
        8.0,
        10.0,
        12.0,
        14.0,
        16.0,
        18.0,
        20.0
    };

    double y;
    double erro;

    for (n = 0; n < N_AMOSTRAS; n++)
    {

        for (i = N_TAPS - 1; i > 0; i--)
        {
            x_reg[i] = x_reg[i - 1];
        }

        x_reg[0] = x[n];


        y = 0.0;

        for (i = 0; i < N_TAPS; i++)
        {
            y = y + w[i] * x_reg[i];
        }


        erro = d[n] - y;


        for (i = 0; i < N_TAPS; i++)
        {
            w[i] = w[i] + mu * erro * x_reg[i];
        }


        printf("Amostra %d\n", n);

        printf("x     = %f\n", x[n]);
        printf("d     = %f\n", d[n]);
        printf("y     = %f\n", y);
        printf("erro  = %f\n", erro);

        printf("pesos = ");

        for (i = 0; i < N_TAPS; i++)
        {
            printf("%f ", w[i]);
        }

        printf("\n\n");
    }

    return 0;
}
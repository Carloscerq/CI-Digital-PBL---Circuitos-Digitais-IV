#include "mlp_weights.h"

#include <cmath>
#include <cstdint>
#include <cstdio>

static const int     Q_FRAC = MLP_Q_FRAC;          // 15
static const int     DW     = MLP_Q_INT + MLP_Q_FRAC;   // 24
static const int64_t SAT_HI =  (INT64_C(1) << (DW - 1)) - 1;
static const int64_t SAT_LO = -(INT64_C(1) << (DW - 1));

static const int N_IN = MLP_N_IN, N_H0 = 8, N_H1 = 4, N_OUT = 4;

// ------------------------------------------------------------- state
static int32_t g_in[N_IN];

static int32_t g_fx_logit[N_OUT];
static int     g_fx_class;
static int     g_fx_saturated;

static float   g_fl_logit[N_OUT];
static int     g_fl_class;

// quantised parameters, derived once from the header floats
static int64_t SC[3];
static int64_t BQ[3][N_H0];
static int     g_init_done = 0;

static int64_t q_round(double v) { return (int64_t)llround(v); }

static void ref_init(void)
{
    if (g_init_done) return;

    // layer 0 consumes the raw integers off the feature bus (|rFFT| bins after the
    // LMS plus the aggregates already shifted by MLP_EXTRA_SHIFT), so its scale
    // carries 2**30; layers 1 and 2 consume Q15 activations, so 2**15.
    SC[0] = q_round((double)MLP_SCALE_0 * ldexp(1.0, 2 * Q_FRAC));
    SC[1] = q_round((double)MLP_SCALE_1 * ldexp(1.0, Q_FRAC));
    SC[2] = q_round((double)MLP_SCALE_2 * ldexp(1.0, Q_FRAC));

    for (int j = 0; j < N_H0; j++) BQ[0][j] = q_round((double)MLP_B0[j] * (1 << Q_FRAC));
    for (int j = 0; j < N_H1; j++) BQ[1][j] = q_round((double)MLP_B1[j] * (1 << Q_FRAC));
    for (int j = 0; j < N_OUT; j++) BQ[2][j] = q_round((double)MLP_B2[j] * (1 << Q_FRAC));

    g_init_done = 1;
}

// ------------------------------------------------------- fixed model
// one perceptron, exactly as perceptron.sv computes it
static int32_t neuron(int64_t sum, int64_t scale, int64_t bias, int relu, int *sat)
{
    int64_t acc = (sum * scale) >> Q_FRAC;    // >> on a negative int64 is an
    acc += bias;                              // arithmetic shift, like >>>
    if (acc > SAT_HI || acc < SAT_LO) *sat = 1;
    if (relu && acc < 0) return 0;
    if (acc > SAT_HI) return (int32_t)SAT_HI;
    if (acc < SAT_LO) return (int32_t)SAT_LO;
    return (int32_t)acc;
}

static int argmax_first(const int32_t *v, int n)
{
    int idx = 0;
    for (int i = 1; i < n; i++)
        if (v[i] > v[idx]) idx = i;           // strict >, lowest index wins
    return idx;
}

static void forward_fixed(void)
{
    int32_t h0[N_H0], h1[N_H1];
    int64_t s;

    g_fx_saturated = 0;

    for (int j = 0; j < N_H0; j++) {
        s = 0;
        for (int i = 0; i < N_IN; i++)
            s += (int64_t)g_in[i] * (int64_t)MLP_W0[i][j];
        h0[j] = neuron(s, SC[0], BQ[0][j], 1, &g_fx_saturated);
    }

    for (int j = 0; j < N_H1; j++) {
        s = 0;
        for (int i = 0; i < N_H0; i++)
            s += (int64_t)h0[i] * (int64_t)MLP_W1[i][j];
        h1[j] = neuron(s, SC[1], BQ[1][j], 1, &g_fx_saturated);
    }

    for (int j = 0; j < N_OUT; j++) {         // linear: no ReLU on the output
        s = 0;
        for (int i = 0; i < N_H1; i++)
            s += (int64_t)h1[i] * (int64_t)MLP_W2[i][j];
        g_fx_logit[j] = neuron(s, SC[2], BQ[2][j], 0, &g_fx_saturated);
    }

    g_fx_class = argmax_first(g_fx_logit, N_OUT);
}

// ------------------------------------------------------- float model
static void forward_float(void)
{
    float h0[N_H0], h1[N_H1], acc;

    for (int j = 0; j < N_H0; j++) {
        acc = 0.0f;
        for (int i = 0; i < N_IN; i++) acc += (float)g_in[i] * (float)MLP_W0[i][j];
        acc = acc * MLP_SCALE_0 + MLP_B0[j];
        h0[j] = acc > 0.0f ? acc : 0.0f;
    }
    for (int j = 0; j < N_H1; j++) {
        acc = 0.0f;
        for (int i = 0; i < N_H0; i++) acc += h0[i] * (float)MLP_W1[i][j];
        acc = acc * MLP_SCALE_1 + MLP_B1[j];
        h1[j] = acc > 0.0f ? acc : 0.0f;
    }
    for (int j = 0; j < N_OUT; j++) {
        acc = 0.0f;
        for (int i = 0; i < N_H1; i++) acc += h1[i] * (float)MLP_W2[i][j];
        g_fl_logit[j] = acc * MLP_SCALE_2 + MLP_B2[j];
    }

    g_fl_class = 0;
    for (int i = 1; i < N_OUT; i++)
        if (g_fl_logit[i] > g_fl_logit[g_fl_class]) g_fl_class = i;
}

// --------------------------------------------------- DPI entry points
extern "C" {

void ref_set_input(int idx, int val)
{
    if (idx >= 0 && idx < N_IN) g_in[idx] = val;
}

void ref_run(void)
{
    ref_init();
    forward_fixed();
    forward_float();
}

int ref_get_logit(int idx)        { return (idx >= 0 && idx < N_OUT) ? g_fx_logit[idx] : 0; }
int ref_get_class(void)           { return g_fx_class; }
int ref_get_saturated(void)       { return g_fx_saturated; }
int ref_get_float_class(void)     { return g_fl_class; }
double ref_get_float_logit(int i) { return (i >= 0 && i < N_OUT) ? (double)g_fl_logit[i] : 0.0; }
int ref_get_scale(int layer)      { ref_init(); return (layer >= 0 && layer < 3) ? (int)SC[layer] : 0; }

}  // extern "C"

// ------------------------------------------------------- self-test
#ifdef REF_STANDALONE
int main(void)
{
    ref_init();
    printf("SCALE integers: L0=%lld L1=%lld L2=%lld\n",
           (long long)SC[0], (long long)SC[1], (long long)SC[2]);

    // a couple of fixed probes, easy to diff against another model
    const int cases = 3;
    for (int c = 0; c < cases; c++) {
        for (int i = 0; i < N_IN; i++) {
            int aggregate = i >= MLP_N_BINS;
            if      (c == 0) g_in[i] = 0;
            else if (c == 1) g_in[i] = aggregate ? 255 : 1000;
            else             g_in[i] = aggregate ? 200 + (i % 4) * 20
                                                 : (int)((i * 7919) % 2000) - 400;
        }
        ref_run();
        printf("case %d: logits", c);
        for (int j = 0; j < N_OUT; j++) printf(" %d", g_fx_logit[j]);
        printf("  fixed=%s float=%s sat=%d\n",
               MLP_CLASSES[g_fx_class], MLP_CLASSES[g_fl_class], g_fx_saturated);
    }
    return 0;
}
#endif

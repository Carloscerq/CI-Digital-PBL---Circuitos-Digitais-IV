# PBL-FFT — quatro modos com pré-processamento completo

Este pacote executa quatro configurações sobre os mesmos casos do dataset e
aplica a cadeia completa:

```text
sensor(es) -> FIR/32 -> LMS opcional -> frame 64/hop 8
            -> remoção da média -> Hann -> FFT64
```

O sinal original é considerado amostrado em 25,6 kHz. A decimação em três
estágios (`/4`, `/4`, `/2`) produz 800 Hz. Portanto:

- cada frame de 64 amostras cobre 80 ms;
- `hop=8` produz um novo frame a cada 10 ms;
- a resolução da FFT é 12,5 Hz;
- os coeficientes FIR e Hann usam Q1.17 nos dois formatos de amostra.

| Modo | Entrada | LMS | FFT | Saída |
|---|---|---|---|---|
| `q915_no_lms` | Q9.15, 24 bits | não | normalizada | DFT/64 |
| `q915_lms` | Q9.15, 24 bits | 8 taps | normalizada | DFT do erro LMS/64 |
| `q1116_no_lms` | Q11.16, 27 bits | não | sem normalização | DFT |
| `q1116_lms` | Q11.16, 27 bits | 8 taps | sem normalização | DFT do erro LMS |

Por padrão, `bins.csv` recebe os bins `0..31`. Use `SAVE_ALL_BINS=1` para
salvar os 64 bins.

## Estrutura

Extraia a pasta `model_sim_four_modes` na raiz do projeto:

```text
PBL-FFT/
├── dataset_split/
├── dataset_q915/
├── dataset_q1116/
└── model_sim_four_modes/
    ├── coefficients/
    │   ├── fir/
    │   └── windowing/
    ├── rtl/
    │   ├── fft/
    │   ├── framing/
    │   ├── lms/
    │   ├── pipeline/
    │   ├── preprocessing/
    │   └── windowing/
    ├── scripts/
    └── verification/
```

Os caminhos dos arquivos `.hex` são relativos à raiz `PBL-FFT`. Execute os
comandos abaixo nessa raiz.

## Gerar Q9.15 e Q11.16

Os CSVs brutos não são alterados e não é aplicada divisão por 256.

Dataset inteiro:

```powershell
py -3.10 .\model_sim_four_modes\scripts\convert_dataset_q915_q1116.py
```

Somente uma pasta:

```powershell
py -3.10 .\model_sim_four_modes\scripts\convert_dataset_q915_q1116.py `
  --case 4Nm_BPFI_03
```

Se as duas pastas convertidas já existem, não é necessário reconverter.

## ModelSim/Questa 2020.1

Uma pasta, dez frames, quatro modos:

```powershell
vsim -c -do "set CASE_PATTERN {4Nm_BPFI_03}; set MAX_CASES 1; set MAX_FRAMES 10; set DESIRED_SENSOR 1; set REFERENCE_SENSOR 3; do model_sim_four_modes/verification/run_four_modes_modelsim.do"
```

Uma pasta completa:

```powershell
vsim -c -do "set CASE_PATTERN {4Nm_BPFI_03}; set MAX_CASES 1; set MAX_FRAMES 0; set DESIRED_SENSOR 1; set REFERENCE_SENSOR 3; set PROGRESS_FRAMES 1000; do model_sim_four_modes/verification/run_four_modes_modelsim.do"
```

Dataset inteiro (`MAX_CASES=0`, `MAX_FRAMES=0`):

```powershell
vsim -c -do "set CASE_PATTERN {*}; set MAX_CASES 0; set MAX_FRAMES 0; set DESIRED_SENSOR 1; set REFERENCE_SENSOR 3; set PROGRESS_FRAMES 1000; do model_sim_four_modes/verification/run_four_modes_modelsim.do"
```

## Xcelium

Em Bash, WSL ou Linux, marque o script como executável e informe as variáveis
antes da execução:

```bash
chmod +x model_sim_four_modes/verification/run_four_modes_xcelium.sh
CASE_PATTERN='4Nm_BPFI_03' MAX_CASES=1 MAX_FRAMES=10 \
DESIRED_SENSOR=1 REFERENCE_SENSOR=3 \
model_sim_four_modes/verification/run_four_modes_xcelium.sh
```

Para o dataset inteiro:

```bash
CASE_PATTERN='*' MAX_CASES=0 MAX_FRAMES=0 PROGRESS_FRAMES=1000 \
DESIRED_SENSOR=1 REFERENCE_SENSOR=3 \
model_sim_four_modes/verification/run_four_modes_xcelium.sh
```

O executável `xrun` deve estar disponível no `PATH`.

## Parâmetros

| Variável | Padrão | Significado |
|---|---:|---|
| `DATASET_Q915` | `dataset_q915` | raiz dos `.mem` Q9.15 |
| `DATASET_Q1116` | `dataset_q1116` | raiz dos `.mem` Q11.16 |
| `OUTPUT_DIR` | `results_four_modes` | resultados |
| `CASE_PATTERN` | `*` | nome/padrão glob das pastas |
| `MAX_CASES` | `1` | máximo de pastas; `0` seleciona todas |
| `MAX_FRAMES` | `10` | frames por modo; `0` usa o arquivo todo |
| `DESIRED_SENSOR` | `1` | sensor principal `d(n)` |
| `REFERENCE_SENSOR` | `2` | referência `x(n)` nos modos LMS |
| `HOP_SIZE` | `8` | avanço entre frames, em amostras a 800 Hz |
| `ADAPT_SAMPLES` | `0` | entradas LMS a 800 Hz; `0` adapta até o fim |
| `MU_SHIFT` | `16` | passo inicial `mu = 2^-MU_SHIFT` |
| `SAVE_ALL_BINS` | `0` | `0`: bins 0..31; `1`: bins 0..63 |
| `PROGRESS_FRAMES` | `10` | intervalo de mensagens; `0` desabilita |

Para `MAX_FRAMES=N`, são necessárias
`32 * (64 + (N-1)*HOP_SIZE)` amostras brutas. Assim, dez frames com hop 8
consomem 4.352 amostras brutas, não 640.

## Escolha da referência LMS

`d(n)` deve ser o sensor que contém o sinal de interesse mais ruído. `x(n)`
deve vir de outro sensor correlacionado com o ruído, mas pouco correlacionado
com a falha que se deseja preservar. Usar o próprio sinal como referência em
um LMS convencional pode cancelar também a assinatura da falha.

O script apenas garante que os índices dos sensores sejam diferentes. A
qualidade física do par deve ser comparada usando redução do ruído fora das
frequências de falha e preservação das componentes BPFI/BPFO/BSF/FTF.

## Resultados

```text
results_four_modes/<caso>/<modo>/
├── bins.csv
├── frames.csv
├── report.txt
└── xrun.log                 # somente Xcelium
```

`bins.csv` possui uma linha por bin:

```text
mode,frame_index,bin,real_q,imag_q,real_value,imag_value
```

`real_q` e `imag_q` são inteiros signed. `real_value` e `imag_value` já estão
divididos por `2^15` ou `2^16`. A normalização da FFT é uma escala adicional:
Q9.15 representa DFT/64; Q11.16 representa DFT sem essa divisão.

`frames.csv` registra mínimo/máximo, overflow da FFT por estágio e contadores
cumulativos de saturação do FIR, LMS e Hann. `report.txt` contém parâmetros e
totais, incluindo taxas de amostragem, decimação, hop e número de frames.

Em Q11.16 sem normalização, overflow é um resultado experimental possível e
é contabilizado; não é ocultado nem transforma sozinho a execução em falha.

## Observações de validação

- Os arquivos FIR possuem 47, 67 e 83 coeficientes Q1.17.
- A Hann possui 64 coeficientes Q1.17.
- `MU_SHIFT=16` é o ponto inicial conservador. Como o LMS agora recebe o
  sinal decimado/filtrado, faça uma varredura posterior de `MU_SHIFT` e avalie
  convergência, saturações e preservação das frequências de falha.
- A cadeia usa `valid/ready`; o simulador pode pausar a entrada durante o
  processamento sem descartar ou reordenar amostras.

# Alterações e validação desta revisão

## Corrigido

- integração de FIR/32, LMS opcional, framing 64/hop configurável, remoção da
  média, janela Hann e FFT64;
- nomes dos módulos alinhados aos nomes dos arquivos `*_dualmode`;
- ROM FIR Q1.17 adicionada e caminhos dos `.hex` corrigidos;
- acumulador FIR ampliado para 64 bits, com arredondamento simétrico,
  saturação e contadores por estágio;
- framing corrigido para `HOP_SIZE=8` em vez de frames sem sobreposição;
- remoção da média com um bit de guarda;
- Hann Q1.17 com retorno saturado à largura da FFT;
- testbench atualizado para consumir amostras brutas suficientes após a
  decimação e auditar toda a cadeia;
- scripts do ModelSim e Xcelium atualizados para os quatro modos.

## Verificações executadas no pacote

- existência e referência de todos os fontes/coeficientes;
- 47, 67 e 83 palavras nos três FIRs e 64 palavras na Hann;
- largura hexadecimal compatível com coeficientes signed de 18 bits;
- sintaxe do script Bash e do conversor Python;
- inventário sem módulos duplicados e sem caminhos RTL antigos.

## Verificação ainda necessária no computador de destino

Não havia ModelSim/Questa, Xcelium, Icarus ou Verilator no ambiente usado para
esta revisão. Portanto, a compilação/elaboração HDL e a equivalência numérica
final devem ser confirmadas executando primeiro uma pasta e poucos frames.

Critérios recomendados antes do lote completo:

1. quatro relatórios com `status=PASS`;
2. zero saturações inesperadas no FIR, Hann e LMS;
3. `fft_overflow_components=0` nos modos Q9.15 normalizados;
4. contagem esperada de frames;
5. preservação das componentes de falha ao comparar com/sem LMS;
6. varredura de `MU_SHIFT` após a inclusão do FIR/32.

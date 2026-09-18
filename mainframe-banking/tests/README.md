# Testes de regressão

```bash
scripts/run-tests.sh            # compila, executa as suítes e compara com os arquivos esperados
scripts/run-tests.sh --update   # regrava os arquivos esperados (revise o diff antes de commitar)
```

Cada suíte parte de uma cópia limpa de `data/`, roda com o relógio fixo
`COB_CURRENT_DATE="2026/09/16 10:30:00.00"` e compara cinco artefatos com
`tests/expected/<suíte>/`: `RC`, `RSPOUT.txt`, `SYSOUT.txt`, `ACCTMAST.dat` e `TRXJRNL.dat`.

## Massa base (`data/`)

| Conta | Cliente | Tipo | Status | Saldo | Moeda | Uso |
|---|---|---|---|---:|---|---|
| 1000000001 | 0000000001 (A) | CHK | A | 1.500,00 | BRL | conta ativa principal |
| 1000000002 | 0000000001 (A) | SAV | A | 250,00 | BRL | saque do saldo exato |
| 1000000003 | 0000000002 (A) | CHK | **B** | 900,00 | BRL | conta bloqueada |
| 1000000004 | 0000000002 (A) | CHK | **C** | 0,00 | BRL | conta encerrada |
| 1000000005 | 0000000003 (**B**) | CHK | A | 500,00 | BRL | cliente bloqueado |
| 1000000006 | 0000000002 (A) | SAV | A | 9.999.999.999.999,00 | BRL | limite de saldo |
| 1000000007 | 0000000001 (A) | CHK | A | 1.000,00 | **USD** | moeda diferente |

Journal inicial: transações `…0001` (conta 1000000001) e `…0002` (conta 1000000003).

## Suíte `functional` — RC esperado 4

`tests/requests/functional.req`, uma requisição por linha, processadas em ordem
(a ordem importa: 7, 23 e 33 dependem de lançamentos anteriores).

| # | Operação | Cenário | Esperado |
|---:|---|---|---|
| 1 | ACCTINQ | conta existente | 0000 |
| 2 | ACCTINQ | conta inexistente | 2001 |
| 3 | ACCTINQ | identificador não numérico | 1002 |
| 4 | ACCTINQ | conta bloqueada (consulta é permitida) | 0000, status B |
| 5 | ACCTINQ | identificador todo zero | 1002 |
| 6 | ACCTDEP | depósito válido 100,50 | 0000, trx 3, saldo 1.600,50 |
| 7 | ACCTDEP | mesma chave, mesmo payload | **0001**, trx 3, saldo 1.600,50 (sem novo lançamento) |
| 8 | ACCTDEP | mesma chave, outro valor | 2007 |
| 9 | ACCTDEP | valor zero | 1004 |
| 10 | ACCTDEP | valor negativo | 1004 |
| 11 | ACCTDEP | valor com letras | 1003 |
| 12 | ACCTDEP | valor sem sinal | 1003 |
| 13 | ACCTDEP | conta bloqueada | 2002 |
| 14 | ACCTDEP | conta inexistente | 2001 |
| 15 | ACCTDEP | estouro do saldo máximo | 2004 |
| 16 | ACCTDEP | acima do limite por transação | 1005 |
| 17 | ACCTDEP | chave em branco | 1006 |
| 18 | ACCTDEP | chave com espaços internos | 1006 |
| 19 | ACCTDEP | chave curta (< 16) | 1006 |
| 20 | ACCTDEP | moeda diferente da conta | 2008 |
| 21 | ACCTDEP | moeda inválida (`br1`) | 1008 |
| 22 | ACCTWDR | saque válido 200,00 | 0000, trx 4, saldo 1.400,50 |
| 23 | ACCTWDR | mesma chave, mesmo payload | **0001**, trx 4 |
| 24 | ACCTWDR | chave do depósito #6 reutilizada em saque | 2007 |
| 25 | ACCTWDR | saque acima do saldo | 2003 |
| 26 | ACCTWDR | valor zero | 1004 |
| 27 | ACCTWDR | valor negativo | 1004 |
| 28 | ACCTWDR | conta encerrada | 2002 |
| 29 | ACCTWDR | cliente bloqueado | 2006 |
| 30 | ACCTWDR | saque do saldo exato | 0000, saldo 0,00 |
| 31 | ACCTWDR | saque com saldo zero | 2003 |
| 32 | ACCTDEP | depósito em conta USD | 0000, trx 6 |
| 33 | TRXINQ | transação criada no #6 | 0000 |
| 34 | TRXINQ | transação inexistente | 2005 |
| 35 | TRXINQ | identificador não numérico | 1007 |
| 36 | TRXINQ | identificador todo zero | 1007 |
| 37 | – | operação desconhecida | 1001 |
| 38 | – | operação em minúsculas | 1001 |
| 39 | ACCTINQ | versão de layout `02` | 1001 |
| 40 | ACCTINQ | saldo final da conta 1 | 0000, saldo 1.400,50 |
| 41 | TRXINQ | transação da massa inicial | 0000 |
| 42 | ACCTINQ | linha com mais de 200 bytes; o excedente contém uma requisição válida que **não** pode ser processada | 1001 (42 respostas, não 43) |

Estado final esperado: conta 1 com saldo 1.400,50 e versão 3; conta 2 com 0,00 e versão 2;
conta 7 com USD 1.010,00 e versão 2; journal com as transações 1 a 6. Os lançamentos
rejeitados não alteram nenhum arquivo.

## Suíte `failsafe` — RC esperado 12

Usa `tests/data/ACCTMAST-CORRUPT.dat` (saldo não numérico na conta 1000000003).

| # | Cenário | Esperado |
|---:|---|---|
| 1 | consulta de conta íntegra | 0000 |
| 2 | consulta da conta corrompida | 9002 + log técnico (sem dados da conta); **processamento interrompido** |
| 3 | consulta válida depois da falha | não processada (não há resposta) |

## Cenários verificados manualmente (não automatizados)

| Cenário | Resultado observado |
|---|---|
| Journal inexistente | Tratado como vazio: TRXINQ → 2005; o primeiro lançamento cria o arquivo com ID 1 |
| Arquivo de requisições vazio | RC 0, contadores zerados |
| `DD_ACCTWORK` ausente | Depósito → 9001 (`TECH=NOPATH`), master intacto, RC 12 |
| Módulo `ACCTDAO` ausente | Depósito → 9001 (`TECH=NOMODULE`), RC 12 |
| Falha na gravação do journal depois do update da conta | Compensação restaurou o saldo (versão +2), resposta 9001 |

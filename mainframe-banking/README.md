# mainframe-banking

Core bancário legado em COBOL: o **sistema de registro** das contas e dos lançamentos
financeiros do projeto `banking-core-mainframe`. A camada moderna (`banking-service`,
Java/Spring Boot) vai integrar com ele por IBM MQ usando os layouts documentados em
[docs/CONTRACT.md](docs/CONTRACT.md).

Esta primeira etapa roda **localmente com GnuCOBOL**. A persistência usa arquivos
sequenciais, atrás de uma camada de acesso a dados que será substituída por DB2.
CICS, DB2 e MQ **não** são simulados. O que depende deles está documentado em
[docs/ZOS-MIGRATION.md](docs/ZOS-MIGRATION.md).

| Operação | Programa | Descrição |
|---|---|---|
| Consulta de conta | `ACCTINQ` | Dados e saldo de uma conta |
| Depósito | `ACCTDEP` | Crédito idempotente |
| Saque | `ACCTWDR` | Débito idempotente, sem cheque especial |
| Consulta de transação | `TRXINQ` | Dados de um lançamento |

## Estrutura

```text
mainframe-banking/
├── programs/
│   ├── account/       ACCTINQ.cbl ACCTDEP.cbl ACCTWDR.cbl   programas de entrada
│   ├── transaction/   TRXINQ.cbl                            programa de entrada
│   ├── common/        ACCTPOST.cbl                          motor de lançamento
│   │                  BKVALID.cbl  BKRESP.cbl               validação / resposta
│   │                  ACCTDAO.cbl  CUSTDAO.cbl TRXDAO.cbl   acesso a dados (LAB)
│   ├── driver/        BKBATDRV.cbl                          driver batch (transporte)
│   └── adapter/       BKMQADP.cbl                           adaptador MQ/CICS (só z/OS)
├── copybooks/
│   ├── REQUEST.cpy  RESPONSE.cpy  RSPCODE.cpy               contrato de integração
│   ├── ACCOUNT.cpy  CUSTOMER.cpy  TRANSACT.cpy              entidades
│   └── DAOCTL.cpy   VALCTL.cpy    RSPCTL.cpy  PSTCTL.cpy    interfaces internas
├── jcl/
│   ├── compile/       BKCBLCL (PROC)  BKCOMPL  BKBUILD
│   └── batch/         BKDEFGDG  BKRUN  BKDAILY
├── data/
│   ├── accounts/      ACCTMAST.dat                          massa base
│   ├── customers/     CUSTMAST.dat
│   └── transactions/  TRXJRNL.dat
├── tests/             requisições, massa corrompida, respostas esperadas
├── scripts/           build.sh  run.sh  run-tests.sh
└── docs/              ARCHITECTURE.md  CONTRACT.md  ZOS-MIGRATION.md  MQ-INTEGRATION.md
```

Ajustes em relação à estrutura inicial (detalhes em
[docs/ARCHITECTURE.md §8](docs/ARCHITECTURE.md#8-estrutura-do-repositório)):

- `TRANSACTION.cpy` foi renomeado para `TRANSACT.cpy`, porque membro de PDS tem no máximo
  8 caracteres.
- Foram criados `common/`, `driver/` e `adapter/`, para reuso e para isolar os transportes.
- Foram criados `tests/`, `scripts/` e `docs/`.

## Pré-requisitos

GnuCOBOL 3.x (testado com 3.2).

```bash
brew install gnucobol          # macOS
sudo apt install gnucobol3     # Debian/Ubuntu (o nome do pacote varia por versão)
cobc --version
```

## Compilar

```bash
cd mainframe-banking
scripts/build.sh
```

O script:

- recusa fontes com código além da **coluna 72**;
- compila com `-std=ibm -Wall`;
- gera um módulo carregável por subprograma e o executável `BKBATDRV` em `build/bin/`.

Os módulos separados correspondem a uma load library com `DYNAM`.

## Executar

```bash
# processa um arquivo de requisições; a massa de trabalho fica em build/data
scripts/run.sh --reset tests/requests/functional.req build/out/RSPOUT.txt
echo "RC=$?"
```

- `--reset` copia `data/` para `build/data/`. A massa base nunca é alterada.
- Sem `--reset`, as execuções seguintes continuam da massa atual, o que permite ver a
  idempotência entre execuções.
- `run.sh` faz o papel do JCL: associa os nomes DD (`ACCTMAST`, `ACCTWORK`, `CUSTMAST`,
  `TRXJRNL`, `REQIN`, `RSPOUT`) a arquivos por meio de variáveis `DD_<nome>`.

Códigos de retorno do driver:

| RC | Significado |
|---:|---|
| 0 | Todas as requisições concluídas (`0000`/`0001`) |
| 4 | Pelo menos uma requisição rejeitada (`1xxx`/`2xxx`/`3xxx`) |
| 12 | Falha técnica (`9xxx`). O processamento **para** (fail-safe). |
| 16 | Erro nos arquivos de requisição ou resposta |

SYSOUT (a saída contém apenas contadores e eventos técnicos):

```text
BKBATDRV ---- PROCESSING SUMMARY ----
BKBATDRV REQUESTS READ .......:          42
BKBATDRV COMPLETED ...........:           9
BKBATDRV IDEMPOTENT REPLAYS ..:           2
BKBATDRV REJECTED ............:          31
BKBATDRV TECHNICAL FAILURES ..:           0
BKBATDRV RETURN CODE .........: +00004
```

## Testar

```bash
scripts/run-tests.sh
# PASS functional (rc=4)
# PASS failsafe (rc=12)
# ALL SUITES PASSED
```

São 42 cenários funcionais e 1 cenário fail-safe, com relógio fixo e comparação byte a byte
de respostas, log, contas e journal. O catálogo completo está em
[tests/README.md](tests/README.md). Ele cobre: conta existente e inexistente, conta ativa,
bloqueada e encerrada, cliente bloqueado, depósito e saque válidos e inválidos, saldo
insuficiente, saldo exato, valor zero, negativo, sem sinal ou não numérico, limites,
identificadores inválidos, transação inexistente, moeda divergente, operação duplicada
(replay `0001`), chave reutilizada com outro payload (`2007`), linha malformada e registro
corrompido.

## Exemplos de entrada e saída

Os registros têm largura fixa. As posições estão em [docs/CONTRACT.md](docs/CONTRACT.md).

**Depósito de 100,50** (requisição, 200 bytes):

```text
01ACCTDEP c0ffee00-0000-4000-8000-000000000006    1000000001+000000000010050BRL7f1c2a9e-5b3d-4c8e-9a01-000000000001
│ │       │                                       │         │               │  └ IDEMPOTENCY-KEY (80)
│ │       │                                       │         │               └ CURRENCY (77)
│ │       │                                       │         └ AMOUNT +100,50 (61)
│ │       │                                       └ ACCOUNT-ID (51)
│ │       └ CORRELATION-ID (11)
│ └ OPERATION-CODE (3)
└ LAYOUT-VERSION (1)
```

Resposta (300 bytes; os espaços à direita foram removidos pelo arquivo local):

```text
01ACCTDEP c0ffee00-0000-4000-8000-0000000000060000OPERATION COMPLETED SUCCESSFULLY                                      00000000000000031000000001DEP+000000000010050+000000000160050BRL2026-09-16-10.30.00.000000
                                              │   │                                                                     │               │         │  │               │               │  └ TRANSACTION-TS (185)
                                              │   │                                                                     │               │         │  │               │               └ CURRENCY (182)
                                              │   │                                                                     │               │         │  │               └ NEW-BALANCE 1.600,50 (166)
                                              │   │                                                                     │               │         │  └ AMOUNT (150)
                                              │   │                                                                     │               │         └ TRANSACTION-TYPE (147)
                                              │   │                                                                     │               └ ACCOUNT-ID (137)
                                              │   │                                                                     └ TRANSACTION-ID (121)
                                              │   └ RESPONSE-MESSAGE (51)
                                              └ RESPONSE-CODE (47)
```

**Mesma requisição reenviada** (retry com a mesma chave). O lançamento original é devolvido e
nenhum dinheiro é movimentado:

```text
01ACCTDEP c0ffee00-0000-4000-8000-0000000000070001DUPLICATE REQUEST - ORIGINAL RESULT RETURNED                          00000000000000031000000001DEP+000000000010050+000000000160050BRL2026-09-16-10.30.00.000000
```

**Saque acima do saldo** (em caso de erro, o corpo vem em branco):

```text
01ACCTWDR c0ffee00-0000-4000-8000-000000000025    1000000001+000000000500000BRL7f1c2a9e-5b3d-4c8e-9a01-000000000025
01ACCTWDR c0ffee00-0000-4000-8000-0000000000252003INSUFFICIENT FUNDS
```

**Consulta de conta:**

```text
01ACCTINQ c0ffee00-0000-4000-8000-000000000001    1000000001
01ACCTINQ c0ffee00-0000-4000-8000-0000000000010000OPERATION COMPLETED SUCCESSFULLY                                      10000000010000000001CHKA+000000000150000BRL2026-09-01-09.00.00.000000
```

**Registro corrompido** (suíte fail-safe). O log técnico não contém dados da conta:

```text
ACCTINQ  TECHNICAL EVENT RC=9002 TECH=BADREC   CORR=c0ffee00-0000-4000-8000-000000000002
```

## Documentação

| Documento | Conteúdo |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Camadas, decisões técnicas, fluxo do lançamento, idempotência, concorrência, atomicidade, segurança |
| [docs/CONTRACT.md](docs/CONTRACT.md) | Layouts campo a campo, tipos, obrigatoriedade, valores, códigos de erro, formatos de data e moeda, encoding |
| [docs/MQ-INTEGRATION.md](docs/MQ-INTEGRATION.md) | Canal Java → MQ → CICS → COBOL: adaptador `BKMQADP`, uma fila por operação, destino de cada mensagem, MQSC/CSD/RACF, requisitos do cliente JMS |
| [docs/ZOS-MIGRATION.md](docs/ZOS-MIGRATION.md) | Laboratório × z/OS, mudanças para CICS/DB2/MQ, DDL proposta, limitações do GnuCOBOL |
| [tests/README.md](tests/README.md) | Massa de dados e catálogo de cenários |

## Laboratório × z/OS, em resumo

| | Laboratório | z/OS |
|---|---|---|
| Dados | Arquivos *line sequential* (`ACCTDAO`/`CUSTDAO`/`TRXDAO`) | DB2 (mesma interface `DAOCTL`) |
| Atomicidade | Compensação best effort (`9003` se falhar) | Unidade de trabalho CICS/DB2 (`SYNCPOINT`) |
| Concorrência | Versão otimista, **sem locks**: rodar em série | Versão otimista + locks do DB2 |
| Idempotência | Varredura do journal | Índice único em `IDEMPOTENCY_KEY` |
| Transporte | `BKBATDRV` + arquivo | `BKMQADP`: MQ → CICS (online, código pronto, não compilado aqui) e JCL `BKDAILY` (batch) |
| Log técnico | `DISPLAY` | TD queue / serviço de log |
| Segurança de acesso | Nenhuma | RACF, TLS no MQ, autorização DB2 |

Os JCLs em `jcl/` descrevem o deployment **alvo**. Os de compilação servem hoje para os módulos
portáveis. Os de execução dependem dos DAOs DB2 (fase 2). Todo valor que depende da
instalação é um placeholder identificado no cabeçalho de cada job.

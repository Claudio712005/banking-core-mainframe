# Integração local Java ↔ IBM MQ ↔ COBOL

Este documento registra como o código COBOL do `mainframe-banking` roda **de verdade** na
máquina de desenvolvimento e como o `banking-svc` o consome pelo IBM MQ.

## Decisão

**O próprio COBOL consome o MQ.** Um container `mainframe-banking` roda o programa
[`BKMQLSN`](../mainframe-banking/programs/adapter/BKMQLSN.cbl). Ele é compilado com
GnuCOBOL 3.2 e chama a API do IBM MQ pela biblioteca de binding COBOL do client oficial da
IBM (`libmqicb`).

```text
banking-svc ──MQPUT──▶ BANKCORE.ACCTDEP.REQUEST ──MQGET──▶ BKMQLSN ──CALL──▶ ACCTDEP ▶ ACCTPOST ▶ DAOs
     ▲                                                          │
     └────────MQGET (CorrelId)── BANKCORE.REPLY.BANKSVC ◀─MQPUT1┘  MQCMIT
```

Alternativas avaliadas:

| Alternativa | Por que não |
|---|---|
| Ponte em Java lendo a fila e executando `BKBATDRV` por mensagem | Coloca Java onde deveria haver COBOL. Não exercita a API do MQ nem o tratamento de mensagens do lado mainframe. |
| Um programa CICS | Não existe CICS local. Simulá-lo seria um "fake mainframe". |
| Fila única para todas as operações | Perde a segurança por operação (RACF por fila) definida no desenho z/OS. |
| GnuCOBOL do Ubuntu (3.1.2) | Diverge da versão 3.2 usada nos testes: trata linhas longas de forma diferente. |

O `BKMQLSN` segue as regras de tratamento de mensagem descritas em
[ZOS-TARGET.md](../mainframe-banking/docs/ZOS-TARGET.md), com `MQCONNX`/`MQCMIT`/`MQBACK` e log em
stdout no lugar dos comandos CICS.

## Como foi validado

1. **Spike:** um programa COBOL fez `MQCONNX` com usuário e senha (MQCSP), `MQPUT1` e `MQGET`
   contra o queue manager do Compose, com sucesso.
2. **Regressão:** os 42 cenários funcionais e o cenário fail-safe rodam dentro do build da imagem
   (`RUN scripts/run-tests.sh`). A imagem não é gerada se algum falhar.
3. **Ponta a ponta pelo MQ** (`scripts/mq-request.sh`):

   | Cenário | Resultado |
   |---|---|
   | Depósito | `0000`, saldo 1.600,50, transação 3 |
   | Mesmo depósito com a mesma chave | `0001`, mesma transação 3 |
   | Mesma chave com outro valor | `2007` |
   | Valor zero | `1004` |
   | Consulta enviada na fila de depósito | `1001` (`TECH=WRONGOP`) |
   | Saque, consulta de transação, consulta de conta | `0000` |
   | Registro corrompido (`9002`) | 3 tentativas com rollback, desvio para `BANKCORE.BACKOUT`, resposta `9004` |
   | Mensagem sem fila de resposta | desviada para `BANKCORE.BACKOUT` (`TECH=NOREPLY`) |
   | Correlation ID com caracteres de controle | registrado como `INVALID` no log |

## Detalhes técnicos que fizeram diferença

| Tema | Decisão | Motivo |
|---|---|---|
| Client MQ | Redistribuível **completo** 9.4.5.1 para Linux x64, com checksum SHA-256 no `ADD`. Só o diretório `java/` é removido. | Com o pacote parcial (ou sem `lib/`), o client aborta (`SIGSEGV`/`SIGABRT`) antes de gravar diagnóstico. |
| Arquitetura | `linux/amd64` | A IBM não publica client nem servidor para arm64. No Apple Silicon os dois containers rodam emulados. |
| `BINARY` | Big-endian (padrão do GnuCOBOL) | Os copybooks IBM declaram `ENCODING 273`; a `libmqicb` espera inteiros big-endian e converte. Com `-fbinary-byteorder=native` os códigos de retorno saem corrompidos. |
| Compilação | `-std=ibm -fnotrunc -fstatic-call`, link `-lmqicb`, copybooks de `inc/cobcpy64` | `-fnotrunc` equivale ao `TRUNC(BIN)` exigido pela IBM. `-fstatic-call` liga as chamadas `CALL 'MQ...'` aos símbolos da biblioteca. `cobcpy64` traz o preenchimento de 64 bits. |
| Autenticação | `MQCONNX` com `MQCSP` (usuário e senha vindos do ambiente) | O canal `DEV.APP.SVRCONN` exige senha; a senha é apagada da memória depois da conexão. |
| Concorrência | **Um** processo atende as 4 filas, em sequência, com espera curta em cada (`BK_POLL_WAIT_MS`, padrão 250 ms) | Os DAOs de arquivo não aceitam dois gravadores. A latência ociosa fica em torno de 1 s. |
| Consistência | Arquivos atualizados antes do `MQCMIT` | Se o processo cair nesse intervalo, o MQ reentrega a mensagem e o `ACCTPOST` responde `0001` com o resultado original (a chave de idempotência está no journal). |
| Poison message | `BOTHRESH(3)` + `BOQNAME(BANKCORE.BACKOUT)` + `HARDENBO` | Sem essa política o listener não sobe (fail-safe). |
| Tamanho | `MAXMSGL(200)` nas filas de requisição | O próprio MQ recusa mensagens maiores, inclusive JMS com cabeçalho RFH2 (`MQRC 2030`). |
| Falha de conexão | O programa termina com RC 12 e o Compose reinicia | O queue manager desfaz o que não foi confirmado; na reconexão tudo recomeça limpo. |

## Como usar

```bash
docker compose up --build
```

Serviços:

| Serviço | Papel |
|---|---|
| `ibm-mq` | Queue manager `QM1`, filas `BANKCORE.*` ([20-banking.mqsc](../infrastructure/ibm-mq/20-banking.mqsc)) |
| `mainframe-banking` | `BKMQLSN` + programas COBOL; dados no volume `core-banking-data` |
| `banking-svc` | Microsserviço Java (casca; a implementação é sua) |

Enviar requisições ao COBOL sem o Java:

```bash
sed -n 6p mainframe-banking/tests/requests/functional.req \
  | mainframe-banking/scripts/mq-request.sh ACCTDEP
```

```text
REPLY 01ACCTDEP c0ffee00-0000-4000-8000-0000000000060000OPERATION COMPLETED SUCCESSFULLY ... 00000000000000031000000001DEP+000000000010050+000000000160050BRL2026-09-17-01.57.10.470000
```

Acompanhar o listener e as filas:

```bash
docker compose logs -f mainframe-banking
echo "DISPLAY QLOCAL('BANKCORE.*') CURDEPTH" | docker compose exec -T ibm-mq runmqsc QM1
```

Voltar os dados COBOL à massa inicial:

```bash
docker compose rm -sf mainframe-banking
docker volume rm banking-core-mainframe_core-banking-data
docker compose up -d mainframe-banking
```

## O que o `banking-svc` precisa fazer para conversar com o COBOL

Resumo (detalhes em [banking-svc/README.md](../banking-svc/README.md)):

1. Montar a requisição de **200 bytes** conforme
   [CONTRACT.md](../mainframe-banking/docs/CONTRACT.md); os golden files estão em
   `mainframe-banking/tests/requests/functional.req`.
2. Enviar para `queue:///BANKCORE.ACCTDEP.REQUEST?targetClient=1` (sem RFH2), como `TextMessage`
   persistente, com `JMSReplyTo = BANKCORE.REPLY.BANKSVC`.
3. Receber em `BANKCORE.REPLY.BANKSVC` com `JMSCorrelationID = '<JMSMessageID enviado>'` e timeout.
4. Ler a resposta de **300 bytes** e converter `RESPONSE-CODE` em HTTP.

## Limitações

- Emulação amd64 no Apple Silicon: a primeira build leva cerca de 9 minutos (download e compilação
  do GnuCOBOL); as seguintes usam cache.
- A persistência em arquivo não participa da transação do MQ; a consistência vem da idempotência,
  não de um commit coordenado (como seria com CICS e DB2).
- Um único processo serializa todas as operações; não é uma arquitetura de throughput.
- As credenciais (`app` e senha) são de desenvolvimento local; o canal não usa TLS.
- `BKMQREQ` e `scripts/mq-request.sh` são ferramentas de teste do laboratório.

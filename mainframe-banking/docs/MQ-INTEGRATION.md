# Integração Java → IBM MQ → COBOL

Este guia descreve o canal online: o que já está implementado (`BKMQADP`), o que
a infraestrutura precisa definir e como o `banking-service` (Java) deve se comportar.

> **Status**: [BKMQADP.cbl](../programs/adapter/BKMQADP.cbl) é código **alvo z/OS**.
> Ele não é compilado pelo `scripts/build.sh`, porque depende do tradutor CICS e dos
> copybooks do IBM MQ. A sintaxe COBOL foi checada no GnuCOBOL com stubs descartáveis;
> isso **não** substitui a compilação no Enterprise COBOL, nem um teste em CICS/MQ reais.
> Os nomes dos copybooks do MQ (`CMQV`, `CMQMDV`, `CMQODV`, `CMQGMOV`, `CMQPMOV`, `CMQTML`)
> devem ser conferidos na `SCSQCOBC` da versão instalada.

## 1. Fluxo

```text
banking-service (Java)                     z/OS
──────────────────────                     ─────────────────────────────────────────────
MQPUT  BANKCORE.ACCTDEP.REQUEST  ───────►  fila de requisição (TRIGTYPE FIRST)
       MsgType=REQUEST                          │ evento de trigger
       ReplyToQ=BANKCORE.REPLY.<app>            ▼
       Format=MQSTR, persistente           initiation queue ──► CKTI
       payload = 200 bytes (REQUEST)            │ EXEC CICS START TRANSID(BKDP) + MQTM
                                                ▼
                                           BKMQADP  (TRANSID BKDP, USERDATA 'ACCTDEP')
                                             loop até a fila esvaziar:
                                               MQGET  (syncpoint, convert)
                                               validação do envelope MQ
                                               CALL ACCTDEP ─► ACCTPOST ─► DAOs DB2
                                               MQPUT1 resposta (syncpoint)
                                               SYNCPOINT | SYNCPOINT ROLLBACK
MQGET  por CorrelId  ◄──────────────────── BANKCORE.REPLY.<app>
       payload = 300 bytes (RESPONSE)
```

Consumo da mensagem, alterações no DB2 e envio da resposta formam **uma unidade de
trabalho**: ou os três são confirmados, ou nenhum.

## 2. Uma fila por operação

| Operação | Fila de requisição | PROCESS | TRANSID | USERDATA |
|---|---|---|---|---|
| Consulta de conta | `BANKCORE.ACCTINQ.REQUEST` | `BANKCORE.ACCTINQ.PROCESS` | `BKAI` | `ACCTINQ` |
| Depósito | `BANKCORE.ACCTDEP.REQUEST` | `BANKCORE.ACCTDEP.PROCESS` | `BKDP` | `ACCTDEP` |
| Saque | `BANKCORE.ACCTWDR.REQUEST` | `BANKCORE.ACCTWDR.PROCESS` | `BKWD` | `ACCTWDR` |
| Consulta de transação | `BANKCORE.TRXINQ.REQUEST` | `BANKCORE.TRXINQ.PROCESS` | `BKTI` | `TRXINQ` |

Todos os nomes são **sugestões** e devem seguir o padrão de nomenclatura da instalação.

Motivos:

- **Segurança por operação.** Com uma fila única, o CKTI acionaria sempre a mesma transação,
  e depósito e saque ficariam sob o mesmo perfil. Com filas separadas, o RACF controla quem
  pode **gravar** em cada fila (classe `MQQUEUE`) e cada TRANSID tem seu próprio perfil
  (classe `TCICSTRN`).
- **Defesa em profundidade.** O `BKMQADP` lê a operação atendida do `USERDATA` do PROCESS e
  rejeita (`1001`) qualquer mensagem cujo `OPERATION-CODE` seja diferente. Uma mensagem de
  saque gravada na fila de consulta não é executada.
- **Isolamento operacional.** Cada operação tem seu próprio backlog, backout e monitoração.

> **Identidade**: tarefas iniciadas pelo CKTI rodam, por padrão, com o usuário do próprio
> CKTI, e não com o usuário que gravou a mensagem. A autorização por operação vem, portanto,
> da **permissão de gravação na fila**. Propagar a identidade do usuário final até o CICS
> (MQMD `UserIdentifier` + `EXEC CICS START USERID`, ou CICS-MQ bridge) é uma evolução
> separada, a combinar com a equipe de segurança.

## 3. Destino de cada mensagem

| Situação | Resposta | Unidade de trabalho | Mensagem |
|---|---|---|---|
| `BackoutCount >= BOTHRESH` | `9004` (se houver ReplyToQ) | commit | movida para `BOQNAME` com contexto original |
| Não é `MQMT_REQUEST` ou sem `ReplyToQ` | nenhuma | commit | movida para `BOQNAME` |
| `Format` diferente de `MQSTR` ou falha de conversão | `1001` (sem eco do payload) | commit | consumida |
| Tamanho diferente de 200 bytes (inclusive truncada) | `1001` | commit | consumida |
| `OPERATION-CODE` diferente da operação da fila | `1001` | commit | consumida |
| Resposta `0xxx` / `1xxx` / `2xxx` | a do programa | commit | consumida |
| Resposta `3xxx` / `9xxx`, módulo ausente ou abend | nenhuma **nesta tentativa** | **rollback** | volta para a fila (`BackoutCount + 1`) |
| Falha ao gravar a resposta | – | rollback | volta para a fila |
| Falha ao mover para o backout | – | rollback, e o adaptador encerra | fica na fila; alerta operacional |

Consequências para o cliente:

- Um `3001` ou `9001` **não chega** ao Java pelo MQ. O CICS/MQ reprocessa a mensagem
  automaticamente, até `BOTHRESH` tentativas.
- Esgotadas as tentativas, o Java recebe `9004`: nenhuma tentativa foi confirmada e não houve
  lançamento. É seguro reenviar depois com a **mesma** idempotency key.
- O `9003` não existe neste canal, porque só ocorre na compensação do laboratório.

## 4. Definições de infraestrutura (exemplos com placeholders)

### MQSC (queue manager do z/OS)

```text
* Fila de iniciação usada pelo CKTI da região CICS (nome da instalação)
DEFINE QLOCAL('CICSPROD.INITQ') LIKE('SYSTEM.DEFAULT.INITIATION.QUEUE')

DEFINE QLOCAL('BANKCORE.BACKOUT') DEFPSIST(YES) +
       DESCR('BANKCORE poison and unanswerable requests')

DEFINE PROCESS('BANKCORE.ACCTDEP.PROCESS') +
       APPLTYPE(CICS) APPLICID('BKDP') USERDATA('ACCTDEP')

DEFINE QLOCAL('BANKCORE.ACCTDEP.REQUEST') +
       DEFPSIST(YES) HARDENBO +
       BOTHRESH(3) BOQNAME('BANKCORE.BACKOUT') +
       TRIGGER TRIGTYPE(FIRST) +
       INITQ('CICSPROD.INITQ') PROCESS('BANKCORE.ACCTDEP.PROCESS') +
       MAXMSGL(200)

* Fila de resposta por aplicação cliente
DEFINE QLOCAL('BANKCORE.REPLY.BANKSVC') DEFPSIST(YES)
```

Repetir PROCESS e QLOCAL para `ACCTINQ`, `ACCTWDR` e `TRXINQ`.

Observações:

- `HARDENBO` grava o `BackoutCount` em disco. Sem ele, a contagem pode ser perdida em um
  restart e o limite de tentativas deixa de ser confiável.
- `BOTHRESH` e `BOQNAME` são **obrigatórios**: sem eles, o `BKMQADP` não processa a fila
  (fail-safe contra loop de poison message).
- `MAXMSGL(200)` faz o próprio queue manager recusar mensagens maiores.
  O adaptador valida o tamanho de qualquer forma.

### CICS (CSD)

```text
DEFINE PROGRAM(BKMQADP)  GROUP(BANKCORE) LANGUAGE(LE370) EXECKEY(USER)
DEFINE PROGRAM(ACCTDEP)  GROUP(BANKCORE) LANGUAGE(LE370)
*  ... ACCTINQ ACCTWDR TRXINQ ACCTPOST BKVALID BKRESP ACCTDAO CUSTDAO TRXDAO
DEFINE TRANSACTION(BKDP) GROUP(BANKCORE) PROGRAM(BKMQADP)
*  ... BKAI BKWD BKTI -> PROGRAM(BKMQADP)
DEFINE TDQUEUE(BKLG) GROUP(BANKCORE) TYPE(EXTRAPARTITION) ...
```

Também são necessários: um `DB2ENTRY` ou `DB2TRAN` para os quatro TRANSIDs, com o plan ou os
packages dos DAOs; a conexão CICS-MQ ativa; e o CKTI monitorando `CICSPROD.INITQ`. Os atributos
exatos (`CONCURRENCY`, `DATALOCATION`, destino do `BKLG` etc.) seguem o padrão da instalação.

### Build do BKMQADP

Os passos são diferentes dos do `BKCBLCL` (batch):

- opção de compilador `CICS` (coprocessador) ou tradutor `DFHECP1$`;
- `SYSLIB` com `SCSQCOBC` (copybooks MQ) e `SDFHCOB`;
- link-edit com o stub CICS do MQ (`CSQCSTUB`) e o stub da interface CICS;
- `RENT`, e AMODE/RMODE conforme o padrão da instalação.

### RACF (resumo)

| Classe | Recurso | Quem |
|---|---|---|
| `MQQUEUE` | `<qmgr>.BANKCORE.ACCTDEP.REQUEST` | UPDATE só para a identidade do serviço autorizado a depositar |
| `MQQUEUE` | `<qmgr>.BANKCORE.ACCTWDR.REQUEST` | UPDATE só para quem pode sacar |
| `MQQUEUE` | `<qmgr>.BANKCORE.REPLY.*` | cliente: GET; região CICS: PUT |
| `MQQUEUE` | `<qmgr>.BANKCORE.BACKOUT` | região CICS: PUT; operação: GET/BROWSE |
| `TCICSTRN` | `BKAI` `BKDP` `BKWD` `BKTI` | usuário do CKTI |
| `MQADMIN` / contexto | – | a região CICS precisa de autoridade para `PASS_ALL_CONTEXT` |

Nos canais cliente, usar TLS (`SSLCIPH`) e regras de `CHLAUTH`.

## 5. Requisitos para o `banking-service` (Java)

| Tema | Regra |
|---|---|
| Header JMS | **Obrigatório** enviar sem RFH2: `targetClient=1` na URI da fila, ou `WMQ_TARGET_CLIENT = WMQ_CLIENT_NONJMS_MQ`. Com RFH2, o `Format` vira `MQHRF2` e toda requisição recebe `1001`. |
| Tipo | `TextMessage` com **exatamente 200 caracteres**, completados com espaços, só com caracteres invariantes. |
| ReplyTo | Sempre informar (`JMSReplyTo`). Sem ReplyTo, a mensagem vai para o backout e não recebe resposta. |
| Correlação | Receber a resposta com o seletor `JMSCorrelationID = '<JMSMessageID da requisição>'`. O `CORRELATION-ID` de 36 caracteres do payload serve para rastreio, não para casar a resposta. |
| Persistência | `DeliveryMode.PERSISTENT` para depósito e saque. |
| Expiração | `timeToLive` igual ao timeout do cliente. A resposta herda o tempo restante. |
| Timeout sem resposta | Reenviar com a **mesma** idempotency key. Resultado: `0000` ou `0001`. |
| `9004` | Nenhuma tentativa foi confirmada. Pode reenviar com a mesma chave depois de um intervalo e alertar a operação. |
| Resposta | 300 caracteres. Validar `LAYOUT-VERSION = '01'` e tratar `RESPONSE-CODE` pela categoria (ver [CONTRACT.md](CONTRACT.md)). |

Exemplo (Jakarta JMS 2.0, IBM MQ classes for JMS):

```java
Queue request = ctx.createQueue("queue:///BANKCORE.ACCTDEP.REQUEST?targetClient=1");
Queue replyTo = ctx.createQueue("queue:///BANKCORE.REPLY.BANKSVC?targetClient=1");

String payload = RequestLayout.deposit(correlationId, accountId, amount, "BRL", idempotencyKey);
if (payload.length() != 200) throw new IllegalStateException("layout must be 200 chars");

TextMessage msg = ctx.createTextMessage(payload);
msg.setJMSReplyTo(replyTo);
ctx.createProducer()
   .setDeliveryMode(DeliveryMode.PERSISTENT)
   .setTimeToLive(timeout.toMillis())
   .send(request, msg);

String selector = "JMSCorrelationID = '" + msg.getJMSMessageID() + "'";
try (JMSConsumer consumer = ctx.createConsumer(replyTo, selector)) {
    Message reply = consumer.receive(timeout.toMillis());
    if (reply == null) {
        throw new BankCoreTimeoutException(idempotencyKey);   // chamador reenvia com a MESMA chave
    }
    String response = reply.getBody(String.class);           // 300 caracteres
}
```

`RequestLayout` é a classe do `banking-service` que monta o layout conforme o
[CONTRACT.md](CONTRACT.md). Ela ainda não existe.

## 6. Teste local

O `BKMQADP` não roda fora do CICS. No laboratório, o mesmo tratamento de mensagens é feito
pelo [`BKMQLSN`](../programs/adapter/BKMQLSN.cbl): GnuCOBOL 3.2 chamando a API do MQ pela
biblioteca COBOL do client oficial (`libmqicb`), com `MQCMIT`/`MQBACK` no lugar de
`SYNCPOINT`. Ver [docs/LOCAL-INTEGRATION.md](../../docs/LOCAL-INTEGRATION.md).

Diferenças em relação ao alvo z/OS:

- Filas com nomes `BANKCORE.*` e **um único processo** atendendo as quatro, em sequência
  (os DAOs de arquivo aceitam um só gravador). Não há trigger nem TRANSID por operação.
- Arquivos não participam da transação do MQ; a idempotência cobre a reentrega.
- Sem conversão EBCDIC (cliente e servidor em ASCII) e sem TLS.

O que continua exigindo um z/OS de desenvolvimento: `BKMQADP` em CICS, DB2 com `SYNCPOINT`
coordenado e conversão de code page real.

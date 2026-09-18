# O que mudaria no z/OS (CICS + DB2 + IBM MQ)

Este laboratório roda com GnuCOBOL, arquivos e IBM MQ em container. Este documento resume o que
seria diferente em um ambiente z/OS real, para que as diferenças fiquem explícitas em vez de
simuladas.

## Mapa de substituição

| Componente | Laboratório | z/OS |
|---|---|---|
| Transporte online | `BKMQLSN`: client MQ, um processo para as quatro filas, `MQCMIT`/`MQBACK` | Programa CICS acionado pelo trigger monitor (CKTI), `MQGET` sob syncpoint, `EXEC CICS LINK`/`CALL` para o programa de entrada e `SYNCPOINT` |
| Transporte batch | `BKBATDRV` com `ORGANIZATION LINE SEQUENTIAL` | `BKBATDRV` com `ORGANIZATION SEQUENTIAL` (RECFM=FB), acionado por JCL |
| ACCTDAO | Varredura de arquivo, cópia old/new master e rename | `SELECT` / `UPDATE ... WHERE VERSION_NUMBER = :v` |
| TRXDAO | Varredura, `MAX(ID)+1`, append | Sequence do DB2 e índice único em `IDEMPOTENCY_KEY` (SQLCODE -803 → duplicado) |
| Atomicidade | Compensação em `ACCTPOST 6300` (best effort, código 9003) | `SYNCPOINT` / `SYNCPOINT ROLLBACK`; a compensação deixa de existir |
| Timestamp | `FUNCTION CURRENT-DATE` | `CURRENT TIMESTAMP` do DB2, dentro da unidade de trabalho |
| Log técnico | `DISPLAY` em `BKRESP` | `WRITEQ TD` ou o serviço de log da instalação |
| Parâmetros (limite por transação, tamanho da chave) | Constantes em `BKVALID` | Tabela de parâmetros |
| Segurança | Nenhuma | RACF (transação e filas), TLS nos canais MQ, autorização do DB2 |

Os programas `ACCTINQ`, `ACCTDEP`, `ACCTWDR`, `TRXINQ`, `ACCTPOST`, `BKVALID` e `BKRESP` usam só
COBOL padrão aceito pelo Enterprise COBOL 6.x. O que **não** é portável: os DAOs de arquivo e o
`BKMQLSN` (usam `ACCEPT ... FROM ENVIRONMENT`, `CBL_RENAME_FILE`, `LINE SEQUENTIAL` e a API do
client MQ).

## CICS

1. **Interface:** os programas de entrada recebem dois parâmetros (`REQUEST`, `RESPONSE`). O
   `EXEC CICS LINK` passa uma única COMMAREA, então o acionador deve usar `CALL` (mesma tarefa e
   unidade de trabalho) ou um programa-casca com uma área única de 500 bytes.
2. **Unidade de trabalho:** decidida pelo `RESPONSE-CODE`. `0xxx`, `1xxx` e `2xxx` confirmam;
   `3xxx` e `9xxx` desfazem, e a mensagem é reentregue até o limite de backout.
3. **Segurança por operação:** uma fila e um TRANSID por operação, com perfis RACF distintos.
   Uma fila única não separaria depósito de saque.
4. **Working storage:** o CICS cria uma cópia por tarefa. Os programas já inicializam tudo em
   `1000-INITIALIZE`.

## DB2

DDL proposta (a revisar com o DBA):

```sql
CREATE TABLE ACCOUNT (
  ACCOUNT_ID       CHAR(10)      NOT NULL,
  CUSTOMER_ID      CHAR(10)      NOT NULL,
  ACCOUNT_TYPE     CHAR(3)       NOT NULL CHECK (ACCOUNT_TYPE IN ('CHK','SAV')),
  ACCOUNT_STATUS   CHAR(1)       NOT NULL CHECK (ACCOUNT_STATUS IN ('A','B','C')),
  CUSTOMER_STATUS  CHAR(1)       NOT NULL CHECK (CUSTOMER_STATUS IN ('A','B','I')),
  BALANCE          DECIMAL(15,2) NOT NULL CHECK (BALANCE >= 0),
  CURRENCY         CHAR(3)       NOT NULL,
  VERSION_NUMBER   INTEGER       NOT NULL,
  LAST_UPDATE_TS   TIMESTAMP     NOT NULL,
  PRIMARY KEY (ACCOUNT_ID)
);

CREATE TABLE ACCOUNT_TRANSACTION (
  TRANSACTION_ID     BIGINT        NOT NULL,
  ACCOUNT_ID         CHAR(10)      NOT NULL,
  TRANSACTION_TYPE   CHAR(3)       NOT NULL CHECK (TRANSACTION_TYPE IN ('DEP','WDR')),
  AMOUNT             DECIMAL(15,2) NOT NULL CHECK (AMOUNT > 0),
  CURRENCY           CHAR(3)       NOT NULL,
  TRANSACTION_STATUS CHAR(1)       NOT NULL CHECK (TRANSACTION_STATUS IN ('C','R')),
  TRANSACTION_TS     TIMESTAMP     NOT NULL,
  IDEMPOTENCY_KEY    VARCHAR(36)   NOT NULL,
  BALANCE_AFTER      DECIMAL(15,2) NOT NULL,
  PRIMARY KEY (TRANSACTION_ID),
  FOREIGN KEY (ACCOUNT_ID) REFERENCES ACCOUNT
);
CREATE UNIQUE INDEX XTRX_IDEMP ON ACCOUNT_TRANSACTION (IDEMPOTENCY_KEY);
```

`CUSTOMER_STATUS` fica na conta porque o cadastro de clientes é outro sistema
([mainframe-customer](../../mainframe-customer), consumido por SOAP). O core bancário guarda só o
estado que precisa para autorizar o lançamento.

Mapeamento SQLCODE → `DAOCTL-STATUS`: `0` OK, `+100` não encontrado (no `UPDATE`, conflito de
versão), `-803` duplicado, `-911`/`-913` transitório (código 3001), demais negativos erro de I/O.

## IBM MQ

| Tema | Alvo z/OS |
|---|---|
| Padrão | Request/reply, com `CorrelId` da resposta igual ao `MsgId` da requisição |
| Formato | `MQFMT_STRING`; o queue manager converte o CCSID (só há campos de texto no contrato) |
| Exactly-once efetivo | `MQGET` sob syncpoint na mesma unidade de trabalho do DB2, coordenada pelo CICS |
| Poison message | `BOTHRESH` + `BOQNAME` + `HARDENBO`; esgotadas as tentativas, resposta `9004` |
| Filas | Uma por operação, com `MAXMSGL(200)` e autorização RACF por fila |

## Limitações do laboratório

| Limitação | Efeito |
|---|---|
| Sem gerenciador de transações | Arquivo e fila não confirmam juntos; a idempotência cobre a reentrega |
| Sem gerenciador de locks | Um único processo grava; executar em série |
| Acesso sequencial | Toda leitura varre o arquivo |
| ASCII, não EBCDIC | Nenhuma comparação depende da ordem de caracteres |
| Sem RACF nem TLS | Segurança é responsabilidade documentada, não implementada |

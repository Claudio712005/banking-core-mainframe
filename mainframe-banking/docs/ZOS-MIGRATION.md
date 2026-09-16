# Do laboratório ao z/OS (CICS + DB2 + IBM MQ)

Este documento separa o que é **implementação de laboratório** do que seria a
**implementação em z/OS**, e lista cada ponto que muda na migração.

## 1. Mapa de substituição

| Componente | Laboratório (hoje) | z/OS (alvo) | Muda o contrato? |
|---|---|---|:-:|
| Transporte online | – (`BKMQADP` existe, mas não roda no lab) | `BKMQADP`, acionado pelo CKTI, uma fila e um TRANSID por operação: `MQGET` sob syncpoint → `CALL` do programa de entrada → `MQPUT1` da resposta → `SYNCPOINT` / `ROLLBACK`. Ver [MQ-INTEGRATION.md](MQ-INTEGRATION.md). | Não (código `9004` acrescentado) |
| Transporte batch | `BKBATDRV` com `ORGANIZATION LINE SEQUENTIAL` | `BKBATDRV` com `ORGANIZATION SEQUENTIAL` (RECFM=FB), executado por `BKRUN` / `BKDAILY` | Não |
| ACCTDAO | Varredura de arquivo + cópia old/new master + rename | `SELECT` / `UPDATE ... WHERE VERSION_NUMBER = :v` | Não |
| CUSTDAO | Varredura de arquivo | `SELECT` | Não |
| TRXDAO | Varredura, `MAX(ID)+1`, append | `NEXT VALUE FOR` sequence, índice único em `IDEMPOTENCY_KEY` (-803 → DUPLICATE) | Não |
| Atomicidade | Compensação `ACCTPOST 6300` (best effort, 9003) | `EXEC CICS SYNCPOINT` / `SYNCPOINT ROLLBACK`; 6300 é removido | Não (9003 deixa de ocorrer) |
| Timestamp | `FUNCTION CURRENT-DATE` (centésimos) | `CURRENT TIMESTAMP` do DB2 dentro da UOW | Não |
| Log técnico | `DISPLAY` em `BKRESP` | `EXEC CICS WRITEQ TD` ou serviço de log da instalação | Não |
| Parâmetros (limite por transação, tamanho mínimo da chave) | Constantes em `BKVALID` | Tabela de parâmetros (DB2) com cache | Não |
| Ligação de arquivos | Variáveis `DD_<nome>` (GnuCOBOL) | Cartões DD (batch) ou nenhum (DB2) | – |
| Relógio de teste | `COB_CURRENT_DATE` | Não se aplica | – |
| Localização de módulos | `COB_LIBRARY_PATH` | `STEPLIB` / `DFHRPL` | – |

Os programas `ACCTINQ`, `ACCTDEP`, `ACCTWDR`, `TRXINQ`, `ACCTPOST`, `BKVALID`, `BKRESP` e todos
os copybooks usam só COBOL padrão aceito pelo Enterprise COBOL 6.x. Os três DAOs do laboratório
**não são portáveis**: usam `ACCEPT ... FROM ENVIRONMENT`, `CBL_RENAME_FILE` e `LINE SEQUENTIAL`.

## 2. Mudanças para CICS

1. **Interface**: os programas de entrada recebem **dois** parâmetros (`REQUEST`, `RESPONSE`).
   `EXEC CICS LINK` passa **uma** COMMAREA, então não serve para eles sem mudança. Decisão
   (D16): o `BKMQADP` usa `CALL`, na mesma tarefa e unidade de trabalho, e os programas ficam
   como estão. Se algum dia for preciso `LINK` (ex.: execução em outra região), as opções são
   um programa-casca com uma área única (`REQUEST` + `RESPONSE`, 500 bytes) ou
   channel/containers.
2. **Retorno**: só o `BKMQADP` emite `EXEC CICS RETURN`. Os programas chamados usam `GOBACK`.
3. **Chamadas**: todas as chamadas internas continuam `CALL` dinâmicas, com `DYNAM`/`RENT`.
   Os DAOs DB2 rodam na thread DB2 da tarefa CICS.
4. **Unidade de trabalho**: o `BKMQADP` decide pelo `RESPONSE-CODE`:
   `0xxx`/`1xxx`/`2xxx` → resposta + `SYNCPOINT`;
   `3xxx`/`9xxx`/sem resposta → `SYNCPOINT ROLLBACK`, e a mensagem é reentregue até `BOTHRESH`.
5. **Log**: substituir o `DISPLAY` de `BKRESP 9000-WRITE-TECHNICAL-LOG`.
6. **Abend**: um abend na tarefa faz o CICS desfazer a unidade de trabalho, e a mensagem volta
   para a fila com `BackoutCount + 1`. O limite (`BOTHRESH`) garante que ela termine na fila
   de backout. `HANDLE ABEND` não é necessário para isso.
7. **Working storage**: o CICS cria WS nova por tarefa. Os programas já inicializam tudo em
   `1000-INITIALIZE`, sem depender de estado de chamadas anteriores.
8. **Segurança**: uma fila e um TRANSID por operação (D15). O RACF controla quem grava em cada
   fila (`MQQUEUE`) e cada transação (`TCICSTRN`). Uma fila única com um único TRANSID **não**
   separaria depósito de saque. Tarefas do CKTI rodam com o usuário do CKTI; propagar a
   identidade do usuário final é uma evolução à parte.

## 3. Mudanças para DB2

DDL **proposta** (a revisar com o DBA: tablespace, bufferpool, particionamento, auditoria):

```sql
CREATE TABLE CUSTOMER (
  CUSTOMER_ID      CHAR(10)       NOT NULL,
  CUSTOMER_NAME    VARCHAR(40)    NOT NULL,
  CUSTOMER_STATUS  CHAR(1)        NOT NULL
                   CHECK (CUSTOMER_STATUS IN ('A','B','I')),
  PRIMARY KEY (CUSTOMER_ID)
);

CREATE TABLE ACCOUNT (
  ACCOUNT_ID       CHAR(10)       NOT NULL,
  CUSTOMER_ID      CHAR(10)       NOT NULL,
  ACCOUNT_TYPE     CHAR(3)        NOT NULL CHECK (ACCOUNT_TYPE IN ('CHK','SAV')),
  ACCOUNT_STATUS   CHAR(1)        NOT NULL CHECK (ACCOUNT_STATUS IN ('A','B','C')),
  BALANCE          DECIMAL(15,2)  NOT NULL CHECK (BALANCE >= 0),
  CURRENCY         CHAR(3)        NOT NULL,
  VERSION_NUMBER   INTEGER        NOT NULL,
  LAST_UPDATE_TS   TIMESTAMP      NOT NULL,
  PRIMARY KEY (ACCOUNT_ID),
  FOREIGN KEY (CUSTOMER_ID) REFERENCES CUSTOMER
);

CREATE SEQUENCE TRANSACTION_SEQ AS BIGINT START WITH 1 NO CYCLE;

CREATE TABLE ACCOUNT_TRANSACTION (
  TRANSACTION_ID     BIGINT         NOT NULL,
  ACCOUNT_ID         CHAR(10)       NOT NULL,
  TRANSACTION_TYPE   CHAR(3)        NOT NULL CHECK (TRANSACTION_TYPE IN ('DEP','WDR')),
  AMOUNT             DECIMAL(15,2)  NOT NULL CHECK (AMOUNT > 0),
  CURRENCY           CHAR(3)        NOT NULL,
  TRANSACTION_STATUS CHAR(1)        NOT NULL CHECK (TRANSACTION_STATUS IN ('C','R')),
  TRANSACTION_TS     TIMESTAMP      NOT NULL,
  IDEMPOTENCY_KEY    VARCHAR(36)    NOT NULL,
  BALANCE_AFTER      DECIMAL(15,2)  NOT NULL,
  PRIMARY KEY (TRANSACTION_ID),
  FOREIGN KEY (ACCOUNT_ID) REFERENCES ACCOUNT
);
CREATE UNIQUE INDEX XTRX_IDEMP ON ACCOUNT_TRANSACTION (IDEMPOTENCY_KEY);
CREATE INDEX XTRX_ACCT ON ACCOUNT_TRANSACTION (ACCOUNT_ID, TRANSACTION_TS);
```

Observações:

- No DB2 for z/OS, a chave primária exige índice único explícito conforme o modo da tabela
  (o DBA define isso).
- Host variables: `DECIMAL(15,2)` ↔ `PIC S9(13)V99 COMP-3`. Os registros dos copybooks de
  entidade continuam DISPLAY; o DAO DB2 converte entre host variable e registro.
- `TRANSACTION_ID BIGINT` ↔ `PIC 9(16)` no registro: o DAO formata com zeros à esquerda.
- Mapeamento SQLCODE → `DAOCTL-STATUS`: `0` OK, `+100` NOT-FOUND (no UPDATE: VERSION-CONFLICT),
  `-803` DUPLICATE, `-911`/`-913` (deadlock/timeout) → novo status transitório mapeado para
  `3001`, demais negativos → IO-ERROR. O SQLCODE vai para `TECH-CODE`.
- Build: coprocessador DB2 (`SQL` compiler option) ou precompilador, mais `BIND PACKAGE` e
  `BIND PLAN`. Nenhum dos dois está em `BKCBLCL`.
- Isolamento: `CS` com `UPDATE` direto é suficiente para o padrão otimista. O TRXINQ pode usar
  `WITH UR` se leitura suja for aceitável (decisão de negócio).

## 4. Mudanças para IBM MQ

Implementadas no `BKMQADP`. Definições de filas, CSD, RACF e requisitos do Java estão em
[MQ-INTEGRATION.md](MQ-INTEGRATION.md).

| Tema | Recomendação |
|---|---|
| Padrão | Request/reply. Java define `ReplyToQ` e usa `CorrelId` para casar a resposta. O COBOL copia `MsgId` da requisição para `CorrelId` da resposta. |
| Formato | `MQFMT_STRING`, CCSID declarado pelo Java. O queue manager converte para EBCDIC. |
| Persistência | Mensagens persistentes para operações financeiras. |
| Exactly-once efetivo | `MQGET` com `MQGMO_SYNCPOINT` na mesma UOW do DB2 (CICS coordena). A idempotency key cobre o retry do lado Java. |
| Poison message | `BOTHRESH` + `BOQNAME` + `HARDENBO` na fila. O `BKMQADP` verifica `BackoutCount`, move a mensagem para o backout e responde `9004`. Sem política de backout, ele não processa a fila. |
| Header JMS | O Java deve enviar sem RFH2 (`targetClient=1`). Caso contrário, `Format = MQHRF2` e a resposta é `1001`. |
| Expiração | `Expiry` na requisição; o Java trata timeout repetindo com a mesma chave. |
| Tamanho | Mensagem de 200 bytes e resposta de 300 bytes. Mensagem com tamanho diferente → `1001`. |
| Segurança | TLS nos canais, autorização de fila (RACF/`setmqaut`), identidade propagada para o CICS. |

## 5. Limitações do ambiente local (GnuCOBOL)

| Limitação | Consequência | Mitigação no lab |
|---|---|---|
| Sem gerenciador de transações | Atualizar a conta e inserir no journal não é atômico | Compensação + código 9003; testes executados em série |
| Sem gerenciador de locks | Execuções simultâneas podem perder atualizações | Versão otimista detecta parte dos casos; **rodar serialmente** |
| Sem `fsync` explícito | Queda de energia pode perder a última escrita | Nenhuma (aceito no laboratório) |
| Acesso sequencial O(n) | Toda leitura varre o arquivo | Volume pequeno de laboratório |
| `CURRENT-DATE` com centésimos | Microssegundos sempre `0000` | Documentado no contrato |
| Arquivo *line sequential* remove espaços à direita | Linhas têm menos de 200/300 bytes | Leitura completa com espaços; o consumidor completa a linha |
| ASCII, não EBCDIC | Ordenação (collating sequence) diferente | Nenhuma comparação depende de ordem entre letras e dígitos; classes de caracteres portáveis |
| `-std=ibm` do GnuCOBOL não é o Enterprise COBOL | Diferenças sutis de compilador (ex.: `TRUNC`, `NUMPROC`) | Aritmética crítica em COMP-3 com `ON SIZE ERROR` |
| Nenhuma segurança de plataforma | Não há RACF, TLS nem auditoria | Documentado; não é simulado |

## 6. Roteiro sugerido

1. **Fase 2 — DB2**: DAOs DB2 com a mesma interface, DDL, BIND, `BKRUN`/`BKDAILY` executáveis
   e driver com `ORGANIZATION SEQUENTIAL`. A suíte funcional vira massa DB2.
2. **Fase 3 — CICS + MQ**: compilar e instalar o `BKMQADP`, definir filas/PROCESS/CSD/RACF
   ([MQ-INTEGRATION.md](MQ-INTEGRATION.md)), trocar o `DISPLAY` do `BKRESP` por TD queue e
   testar o comportamento de rollback e backout.
3. **Fase 4 — banking-service**: cliente JMS em Java com os mesmos layouts de
   `docs/CONTRACT.md`.

# Arquitetura — mainframe-banking

## 1. Visão em camadas

```text
 TRANSPORTE          BKBATDRV            batch: arquivo sequencial (roda no lab)
 (substituível)      BKMQLSN             online: listener MQ local (GnuCOBOL + client IBM MQ)
        │  CALL por whitelist, USING REQUEST RESPONSE
        ▼
 ENTRADA             ACCTINQ  ACCTDEP  ACCTWDR  TRXINQ
 (1 por operação)        │        └───┬───┘       │
        │                │            ▼           │
 NEGÓCIO                 │        ACCTPOST        │   (motor de lançamento)
        │                │            │           │
        ├──── BKVALID  (validação sintática, sem I/O)
        ├──── BKRESP   (cabeçalho, mensagens, log técnico)
        ▼                ▼            ▼           ▼
 ACESSO A DADOS      ACCTDAO                   TRXDAO
 (substituível)      └── lab: arquivos   │   futuro: DB2 (mesma interface)
```

| Camada | Programas | Conhece | Não conhece |
|---|---|---|---|
| Transporte | BKBATDRV, BKMQLSN | origem/destino das mensagens, RC do job, envelope MQ, unidade de trabalho | regras de negócio, persistência |
| Entrada | ACCTINQ, ACCTDEP, ACCTWDR, TRXINQ | contrato REQUEST/RESPONSE | arquivos, DB2, MQ |
| Negócio | ACCTPOST | regras de lançamento, idempotência, unidade de trabalho | onde os dados estão |
| Serviços comuns | BKVALID, BKRESP | formato dos campos, códigos e mensagens | regras de negócio |
| Dados | ACCTDAO, TRXDAO | armazenamento físico | regras de negócio |

Toda dependência aponta para baixo. Trocar a camada de transporte (arquivo → MQ/CICS) ou a de
dados (arquivo → DB2) **não altera** as camadas do meio, porque as interfaces
(`REQUEST`, `RESPONSE`, `DAOCTL` + registros de entidade) são mantidas.

## 2. Por que cada decisão

| # | Decisão | Motivo |
|---|---|---|
| D1 | Um programa de entrada por operação, lógica de lançamento única em `ACCTPOST` | Evita duplicar depósito/saque. Mantém pontos de entrada separados, com contrato e monitoração próprios. Os programas de entrada, sozinhos, **não** dão segurança por operação: no canal MQ ela vem de D15. |
| D2 | DAOs com interface `DAOCTL` (função, status semântico, tech-code) | O chamador reage a `NOT-FOUND` e `VERSION-CONFLICT`, nunca a file status ou SQLCODE. A troca por DB2 fica restrita a 3 módulos. |
| D3 | Contrato só com caracteres | A conversão de code page (EBCDIC ↔ ASCII) no MQ corrompe binário e COMP-3. Com texto é segura. |
| D4 | COMP-3 só na aritmética interna (`WS-MONETARY-WORK`) | Decimal exato, com `ON SIZE ERROR` para overflow. Corresponde ao `DECIMAL(15,2)` do DB2. |
| D5 | Copybooks de entidade com `:TAG:` + `REPLACING` | O mesmo layout aparece várias vezes no mesmo programa (imagem atual e anterior, registro do arquivo e do chamador) sem nomes ambíguos. |
| D6 | Códigos de resposta em um copybook (`RSPCODE`) e mensagens em um único módulo (`BKRESP`) | Uma fonte de verdade. `BKRESP` troca qualquer código não documentado por `9999` (fail-safe). |
| D7 | `CALL identificador` (dinâmico) com nomes em `WS-PROGRAM-NAMES` | Sem literais espalhados. Corresponde a `DYNAM` no z/OS: um DAO pode ser trocado sem relinkar quem chama. `ON EXCEPTION` trata módulo ausente. |
| D8 | Dispatch por whitelist no driver | O código de operação que vem de fora nunca é usado como nome de programa. |
| D9 | Validação numérica **antes** de qualquer aritmética | Dado inválido em campo zonado causa S0C7 (data exception) no z/OS. |
| D10 | DAOs validam a integridade do registro na leitura e na escrita | Equivale a CHECK constraints. Registro corrompido gera `9002` e o processamento para. |
| D11 | Driver para no primeiro erro técnico (RC 12) | Fail-safe: em falha de infraestrutura, continuar pode ampliar o dano. O reprocessamento é seguro por causa da idempotência. |
| D12 | Log técnico só com programa, códigos e correlation-id | Nenhum dado bancário ou pessoal em SYSOUT. |
| D13 | Sem `GO TO`; parágrafos numerados por fase (1000 init, 2000 validação … 9000 finalização) | Fluxo estruturado, com leitura de cima para baixo. |
| D14 | `INITIALIZE ... WITH FILLER` nos registros | FILLER não inicializado pode conter low-values. Isso vira lixo em arquivo (no GnuCOBOL, file status 71) ou em mensagem MQ. |
| D15 | Canal MQ com **uma fila por operação**; o adaptador rejeita mensagem cuja operação não seja a da fila | Permite controlar por fila quem pode depositar e quem pode sacar. Uma fila única não separaria as operações. |
| D16 | O adaptador chama os programas de entrada com `CALL` | Mantém a interface de dois parâmetros (`REQUEST`, `RESPONSE`) e os programas livres de qualquer comando de transporte. |
| D17 | Canal MQ: `3xxx`/`9xxx` fazem rollback sem resposta, e o limite de tentativas vem do backout (`BOTHRESH`) | A resposta só sai se os dados forem confirmados. Falhas transitórias são repetidas pelo próprio MQ, e poison messages terminam na fila de backout com resposta `9004`. |

## 3. Fluxo de um lançamento (ACCTPOST)

```text
1000 INITIALIZE            timestamp único do lançamento; cabeçalho da resposta
2000 VALIDATE-INPUT        layout 01; operação combina com o tipo de lançamento;
                           conta, valor (>0, <= limite), moeda, chave
3000 CHECK-IDEMPOTENCY     chave existe?  mesmo payload -> 0001 (replay, fim)
                                          outro payload -> 2007 (fim)
4000 LOAD-ACCOUNT          existe (2001)? ativa (2002)? mesma moeda (2008)?
4500 VERIFY-CUSTOMER       cliente ativo (2006)? cliente ausente -> 9002
5000 APPLY-BUSINESS-RULE   DEP: saldo + valor (overflow -> 2004)
                           WDR: valor > saldo -> 2003
                           novo saldo < 0 -> 9002 (invariante)
6000 PERSIST-POSTING       6100 UPDATE conta (versão divergente -> 3001)
                           6200 INSERT journal (chave duplicada -> 3001)
                           6300 [lab] compensação se 6200 falhar
8000 BUILD-RESPONSE        corpo a partir do registro de transação (novo ou original)
9000 FINALIZE              código + mensagem + log técnico (3xxx/9xxx)
```

Cada fase só executa enquanto o código ainda é `0000`. Não existe desvio de fluxo.

## 4. Idempotência

- O journal guarda `IDEMPOTENCY-KEY` e `BALANCE-AFTER` em cada lançamento.
- A verificação (3000) compara conta, tipo, valor e moeda. Replay devolve o lançamento
  original e **não movimenta dinheiro**.
- Condição de corrida (duas requisições com a mesma chave ao mesmo tempo): ambas passam pela
  verificação, mas só uma consegue inserir. No z/OS, o índice único gera SQLCODE -803; no
  laboratório, `TRXDAO` recusa a duplicata. A perdedora desfaz a alteração da conta e
  responde `3001`. O retry recebe `0001`.

## 5. Concorrência

- **Otimista**: `ACCOUNT.VERSION-NUMBER`. O `UPDATE` só é aplicado se a versão gravada for a
  mesma que foi lida, e incrementa a versão.
- No laboratório **não existe gerenciador de locks**. O rename atômico protege o arquivo contra
  escrita parcial, mas duas execuções simultâneas podem perder atualizações entre si.
  **Execute o laboratório serialmente.**
- No z/OS: `UPDATE ... WHERE ACCOUNT_ID = :id AND VERSION_NUMBER = :v`. O DB2 aplica lock de
  linha até o syncpoint. SQLCODE +100 na atualização é conflito de versão (3001).

## 6. Atomicidade

| Ambiente | Garantia |
|---|---|
| z/OS (alvo) | 6100 e 6200 ficam na **mesma unidade de trabalho** do CICS/DB2. O `BKMQADP` emite `EXEC CICS SYNCPOINT ROLLBACK` para `3xxx`/`9xxx`. O `MQGET` e o `MQPUT1` da resposta, ambos sob syncpoint, participam da mesma UOW: mensagem consumida, conta, journal e resposta são confirmados juntos ou nenhum é. |
| Laboratório | Não há transação. Se 6200 falha depois de 6100, o parágrafo 6300 restaura o saldo anterior (com nova versão). Se a compensação também falha, a resposta é **9003**: estado incerto, reconciliação manual. Um crash do processo entre 6100 e 6200 deixa conta e journal inconsistentes. **O arquivo local não tem as garantias do DB2.** |

## 7. Segurança: o que está no COBOL e o que não está

| Medida | Onde |
|---|---|
| Validação de todo campo externo (formato, faixa, conjunto de caracteres) | BKVALID, ACCTPOST 2000 |
| Classes de caracteres portáveis ASCII/EBCDIC (faixas explícitas `A-I`, `J-R`, `S-Z`) | BKVALID |
| Overflow monetário e de sequência (`ON SIZE ERROR`) | ACCTPOST 5100, ACCTDAO 3100, TRXDAO 3200 |
| Rejeição de valor zero, negativo ou sem sinal | BKVALID 3000 |
| Saldo nunca negativo (validado na leitura, no cálculo e na escrita) | ACCTDAO 8300, ACCTPOST 5000 |
| Estado inválido de conta/cliente bloqueia a operação | ACCTPOST 4100/4500 |
| Mensagens genéricas, sem dados; log sem PII | BKRESP |
| Whitelist de programas | BKBATDRV 2100 |
| Linha maior que o registro rejeitada, sem gerar registro "extra" | BKBATDRV + `COB_LS_SPLIT=FALSE` |
| **Autenticação/autorização do chamador** | **Infraestrutura**: RACF (transação CICS), segurança de filas MQ, autorização DB2 de plan/package, TLS nos canais MQ. Não é implementada em COBOL. |
| **Autorização por conta (o chamador pode ver esta conta?)** | Camada de serviço (Java) e/ou regra de entitlement futura. Não implementada. |
| **Criptografia** | Infraestrutura (TLS, dataset encryption, DB2 encryption). Não implementada em COBOL. |

## 8. Estrutura do repositório

```text
mainframe-banking/
├── programs/
│   ├── account/        ACCTINQ ACCTDEP ACCTWDR       (entrada)
│   ├── transaction/    TRXINQ                        (entrada)
│   ├── common/         ACCTPOST BKVALID BKRESP       (negócio / serviços)
│   │                   ACCTDAO TRXDAO                (dados - LAB)
│   ├── driver/         BKBATDRV                      (transporte batch)
│   └── adapter/        BKMQLSN BKMQREQ               (transporte MQ local e ferramenta de teste)
├── copybooks/          REQUEST RESPONSE RSPCODE      (contrato)
│                       ACCOUNT CUSTOMER TRANSACT     (entidades)
│                       DAOCTL VALCTL RSPCTL PSTCTL   (interfaces internas)
├── jcl/compile/        BKCBLCL (PROC) BKBUILD
├── data/               massa base (nunca alterada pelos scripts)
├── tests/              requisições, massa corrompida, respostas esperadas
├── scripts/            build.sh run.sh run-tests.sh
└── docs/               CONTRACT.md ARCHITECTURE.md ZOS-TARGET.md
```

Desvios em relação à estrutura original proposta:

- `TRANSACTION.cpy` passou a se chamar **`TRANSACT.cpy`**, porque nome de membro de PDS tem no
  máximo 8 caracteres. Todos os programas e copybooks respeitam esse limite.
- Foram criados `programs/common` (reuso), `programs/driver` e `programs/adapter`
  (transportes isolados).
- Foram criados `data/customers`, `tests/`, `scripts/` e `docs/`.
- As pastas existem só no Git. No z/OS os fontes ficam em uma única PDS (`BANKCORE.COBOL`) e os
  copybooks em outra (`BANKCORE.COPYLIB`).

# Contrato de mensagens — layout 01

Este documento é a referência dos layouts trocados entre a camada Java
(`banking-service`) e o COBOL. As fontes de verdade são os copybooks
[REQUEST.cpy](../copybooks/REQUEST.cpy), [RESPONSE.cpy](../copybooks/RESPONSE.cpy)
e [RSPCODE.cpy](../copybooks/RSPCODE.cpy). Se este documento e um copybook
divergirem, vale o copybook, e o documento deve ser corrigido.

## Regras gerais

| Tema | Regra |
|---|---|
| Tamanho | Requisição: **200 bytes** fixos. Resposta: **300 bytes** fixos. |
| Tipo de dado | **Somente caracteres** (`PIC X` e numérico `DISPLAY`). Não há `COMP`, `COMP-3` nem binário no contrato. |
| Alinhamento | Alfanuméricos alinhados à esquerda e completados com espaços. Numéricos com zeros à esquerda. |
| Encoding | Só caracteres invariantes: `A-Z a-z 0-9 + - . espaço`. No laboratório o arquivo é ASCII (UTF-8 sem acentos). No z/OS é EBCDIC, no CCSID da instalação (**confirmar** com a equipe de infraestrutura, por exemplo 037, 1047 ou 500). Com MQ, usar `MQMD.Format = MQFMT_STRING` para o queue manager converter o CCSID. Isso só é seguro porque o contrato não tem campos binários. |
| Monetário | 16 bytes: sinal explícito (`+` ou `-`) + 15 dígitos, **2 casas decimais implícitas** (`S9(13)V99 SIGN LEADING SEPARATE`). Faixa: ±9.999.999.999.999,99. |
| Timestamp | 26 bytes, formato DB2 `YYYY-MM-DD-HH.MM.SS.NNNNNN`, hora local do sistema, sem fuso. No laboratório, só os centésimos são reais; os 4 últimos dígitos são `0000`. |
| Identificadores | Somente dígitos, largura fixa, não podem ser todos zeros. |
| Versionamento | `LAYOUT-VERSION = '01'`. Campo novo só pode ocupar `FILLER`. Qualquer mudança incompatível cria o layout `02`. |
| Corpo em erro | O corpo só é válido com `RESPONSE-CODE` `0000` ou `0001`. Nos demais casos vem com espaços. |
| Bytes finais | O arquivo *line sequential* do laboratório remove espaços à direita. O consumidor deve completar a linha até 300 bytes antes de ler. No MQ/z/OS a mensagem tem tamanho fixo. |

### Exemplos monetários

| Valor | Campo (16 bytes) |
|---|---|
| 100,50 | `+000000000010050` |
| 0,01 | `+000000000000001` |
| -50,00 (rejeitado) | `-000000000005000` |
| sem sinal (rejeitado, 1003) | `0000000000010000` |

Em Java:

```java
// parse
BigDecimal amount = new BigDecimal(field).movePointLeft(2);          // "+000000000010050" -> 100.50
// format (ArithmeticException se houver mais de 2 casas decimais)
String digits = amount.movePointRight(2).setScale(0, RoundingMode.UNNECESSARY)
        .abs().toPlainString();
if (digits.length() > 15) throw new IllegalArgumentException("amount out of range");
String field = (amount.signum() < 0 ? "-" : "+") + "0".repeat(15 - digits.length()) + digits;
// timestamp
DateTimeFormatter DB2_TS = DateTimeFormatter.ofPattern("yyyy-MM-dd-HH.mm.ss.SSSSSS");
```

`RoundingMode.UNNECESSARY` impede o arredondamento silencioso: um valor com mais de 2 casas
precisa ser rejeitado no Java, nunca truncado.

---

## Requisição (200 bytes)

### Cabeçalho (comum a todas as operações)

| Campo | Pos | Tam | Tipo | Obrig. | Valores / regra |
|---|---:|---:|---|:-:|---|
| LAYOUT-VERSION | 1 | 2 | X | S | `01` |
| OPERATION-CODE | 3 | 8 | X | S | `ACCTINQ `, `ACCTDEP `, `ACCTWDR `, `TRXINQ  ` (maiúsculas, completado com espaços) |
| CORRELATION-ID | 11 | 36 | X | N | Opaco (UUID recomendado). Devolvido sem alteração e usado no log técnico. **Não** colocar dados de cliente. |
| FILLER | 47 | 4 | X | – | Espaços |
| BODY | 51 | 150 | X | S | Conforme a operação |

### Corpo ACCTINQ: consulta de conta

| Campo | Pos | Tam | Tipo | Obrig. | Regra |
|---|---:|---:|---|:-:|---|
| ACCOUNT-ID | 51 | 10 | 9 (texto) | S | 10 dígitos, diferente de `0000000000` |

### Corpo ACCTDEP / ACCTWDR: depósito e saque

| Campo | Pos | Tam | Tipo | Obrig. | Regra |
|---|---:|---:|---|:-:|---|
| ACCOUNT-ID | 51 | 10 | 9 (texto) | S | 10 dígitos, diferente de zeros |
| AMOUNT | 61 | 16 | S9(13)V99 SLS | S | Sinal + 15 dígitos; `> 0`; `<= 1.000.000,00` (limite por transação) |
| CURRENCY | 77 | 3 | X | S | 3 letras maiúsculas (ISO 4217); deve ser igual à moeda da conta |
| IDEMPOTENCY-KEY | 80 | 36 | X | S | 16 a 36 caracteres `[A-Za-z0-9-]`, alinhado à esquerda, sem espaços internos. **Globalmente único por intenção financeira** (UUID v4 recomendado). |

### Corpo TRXINQ: consulta de transação

| Campo | Pos | Tam | Tipo | Obrig. | Regra |
|---|---:|---:|---|:-:|---|
| TRANSACTION-ID | 51 | 16 | 9 (texto) | S | 16 dígitos, diferente de zeros |

---

## Resposta (300 bytes)

### Cabeçalho

| Campo | Pos | Tam | Tipo | Conteúdo |
|---|---:|---:|---|---|
| LAYOUT-VERSION | 1 | 2 | X | `01` |
| OPERATION-CODE | 3 | 8 | X | Eco da requisição |
| CORRELATION-ID | 11 | 36 | X | Eco da requisição |
| RESPONSE-CODE | 47 | 4 | 9 (texto) | Ver tabela de códigos |
| RESPONSE-MESSAGE | 51 | 60 | X | Mensagem padronizada (sem dados sensíveis) |
| FILLER | 111 | 10 | X | Espaços |
| BODY | 121 | 180 | X | Conforme a operação |

### Corpo ACCTINQ

| Campo | Pos | Tam | Tipo | Conteúdo |
|---|---:|---:|---|---|
| ACCOUNT-ID | 121 | 10 | 9 | |
| CUSTOMER-ID | 131 | 10 | 9 | |
| ACCOUNT-TYPE | 141 | 3 | X | `CHK` corrente, `SAV` poupança |
| ACCOUNT-STATUS | 144 | 1 | X | `A` ativa, `B` bloqueada, `C` encerrada |
| BALANCE | 145 | 16 | S9(13)V99 SLS | Saldo atual |
| CURRENCY | 161 | 3 | X | ISO 4217 |
| LAST-UPDATE-TS | 164 | 26 | TS | Última alteração da conta |

A consulta devolve contas em qualquer status. O número de versão interno não é exposto.

### Corpo ACCTDEP / ACCTWDR

| Campo | Pos | Tam | Tipo | Conteúdo |
|---|---:|---:|---|---|
| TRANSACTION-ID | 121 | 16 | 9 | ID atribuído ao lançamento |
| ACCOUNT-ID | 137 | 10 | 9 | |
| TRANSACTION-TYPE | 147 | 3 | X | `DEP` / `WDR` |
| AMOUNT | 150 | 16 | S9(13)V99 SLS | Valor lançado |
| NEW-BALANCE | 166 | 16 | S9(13)V99 SLS | Saldo **imediatamente após** este lançamento |
| CURRENCY | 182 | 3 | X | |
| TRANSACTION-TS | 185 | 26 | TS | Momento do lançamento |

Na resposta `0001` (replay idempotente), todos os campos são os do lançamento **original**.
`NEW-BALANCE` é o saldo daquele momento, não o saldo atual.

### Corpo TRXINQ

| Campo | Pos | Tam | Tipo | Conteúdo |
|---|---:|---:|---|---|
| TRANSACTION-ID | 121 | 16 | 9 | |
| ACCOUNT-ID | 137 | 10 | 9 | |
| TRANSACTION-TYPE | 147 | 3 | X | `DEP` / `WDR` |
| AMOUNT | 150 | 16 | S9(13)V99 SLS | |
| CURRENCY | 166 | 3 | X | |
| TRANSACTION-STATUS | 169 | 1 | X | `C` concluída (`R` estornada: reservado, ainda não produzido) |
| TRANSACTION-TS | 170 | 26 | TS | |

A chave de idempotência e o saldo pós-lançamento ficam gravados, mas **não** são devolvidos.

---

## Códigos de resposta

O primeiro dígito indica a categoria e define como o cliente deve reagir.

| Código | Categoria | Mensagem | Ação do cliente |
|---|---|---|---|
| 0000 | Sucesso | OPERATION COMPLETED SUCCESSFULLY | – |
| 0001 | Sucesso | DUPLICATE REQUEST - ORIGINAL RESULT RETURNED | Tratar como sucesso. Nenhum dinheiro foi movimentado agora. |
| 1001 | Validação | INVALID REQUEST LAYOUT OR OPERATION | Corrigir a requisição. Não repetir igual. |
| 1002 | Validação | INVALID ACCOUNT IDENTIFIER | idem |
| 1003 | Validação | INVALID AMOUNT FORMAT | idem |
| 1004 | Validação | AMOUNT MUST BE GREATER THAN ZERO | idem |
| 1005 | Validação | AMOUNT EXCEEDS TRANSACTION LIMIT | idem |
| 1006 | Validação | INVALID IDEMPOTENCY KEY | idem |
| 1007 | Validação | INVALID TRANSACTION IDENTIFIER | idem |
| 1008 | Validação | INVALID CURRENCY CODE | idem |
| 2001 | Negócio | ACCOUNT NOT FOUND | Não repetir. |
| 2002 | Negócio | ACCOUNT IS NOT ACTIVE | Não repetir. |
| 2003 | Negócio | INSUFFICIENT FUNDS | Pode repetir com **nova** chave depois de mudança de saldo. |
| 2004 | Negócio | OPERATION WOULD EXCEED BALANCE LIMIT | Não repetir. |
| 2005 | Negócio | TRANSACTION NOT FOUND | Não repetir. |
| 2006 | Negócio | CUSTOMER IS NOT ACTIVE | Não repetir. |
| 2007 | Negócio | IDEMPOTENCY KEY ALREADY USED FOR A DIFFERENT OPERATION | Erro do cliente: a chave foi reaproveitada. Investigar. |
| 2008 | Negócio | CURRENCY DOES NOT MATCH ACCOUNT CURRENCY | Não repetir. |
| 3001 | Transitório | CONCURRENT UPDATE DETECTED - RETRY WITH SAME KEY | Repetir com a **mesma** chave (backoff). |
| 9001 | Técnico | DATA ACCESS FAILURE - OPERATION NOT COMPLETED | Operação não concluída. Pode repetir com a mesma chave depois da correção. |
| 9002 | Técnico | DATA INTEGRITY FAILURE - OPERATION NOT COMPLETED | Não repetir. Acionar suporte (dado corrompido). |
| 9003 | Técnico | POSTING STATE UNCERTAIN - DO NOT RETRY - CALL SUPPORT | **Não repetir.** Reconciliação manual (só ocorre no laboratório, ver arquitetura). |
| 9004 | Técnico | RETRIES EXHAUSTED - OPERATION NOT COMPLETED | Só no canal MQ. Todas as tentativas foram desfeitas e nenhum lançamento ocorreu. Pode reenviar com a **mesma** chave depois de um intervalo; alertar a operação. |
| 9999 | Técnico | UNEXPECTED ERROR - OPERATION NOT COMPLETED | Acionar suporte. |

### Diferenças no canal MQ

- `3xxx` e `9001`/`9002`/`9999` **não** são enviados ao cliente. A mensagem é desfeita e
  reprocessada pelo MQ. Esgotadas as tentativas, a resposta é `9004`.
- `9003` só existe no laboratório (arquivo local).
- A mensagem precisa ter `Format = MQSTR` (sem cabeçalho RFH2 do JMS) e exatamente 200 bytes;
  caso contrário, a resposta é `1001`.
- Detalhes em [ZOS-TARGET.md](ZOS-TARGET.md) e em [../../docs/LOCAL-INTEGRATION.md](../../docs/LOCAL-INTEGRATION.md).

### Uso correto da idempotency key

- Uma chave representa **uma intenção financeira**. Todo retry (timeout, 3001, 9001)
  usa a **mesma** chave.
- A mesma chave com outro payload (conta, tipo, valor ou moeda) gera `2007`. Isso protege
  contra reuso acidental.
- A chave é global, não é por conta.
- Timeout sem resposta: repetir com a mesma chave. A resposta será `0000` (não tinha sido
  processada) ou `0001` (já tinha sido).

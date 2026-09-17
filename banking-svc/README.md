# banking-svc

Casca do microsserviço Java que expõe operações bancárias por HTTP/JSON e as executa no core
bancário COBOL ([`mainframe-banking`](../mainframe-banking)) via IBM MQ, no modelo request/reply.

**Estado:** esta pasta contém só contratos e configuração. Controller, casos de uso, domínio e o
adapter MQ ainda precisam ser implementados (veja [O que implementar](#o-que-implementar)).

## Fluxo alvo

```text
Client
  │  POST /api/v1/accounts/{accountId}/deposits      (JSON)
  ▼
banking-svc
  │  MQPUT  BANKCORE.ACCTDEP.REQUEST                 (200 bytes, layout REQUEST.cpy, MQSTR)
  │         ReplyToQ = BANKCORE.REPLY.BANKSVC
  ▼
IBM MQ (QM1)
  ▼
BKMQLSN (COBOL, GnuCOBOL + IBM MQ client)        container mainframe-banking
  │  MQGET → CALL ACCTDEP → ACCTPOST → DAOs → MQPUT1 resposta → MQCMIT
  ▼
IBM MQ  BANKCORE.REPLY.BANKSVC                    (300 bytes, layout RESPONSE.cpy, CorrelId = MsgId)
  ▼
banking-svc  aguarda a resposta pelo CorrelId (timeout = MQ_REPLY_TIMEOUT)
  │  RESPONSE-CODE → HTTP
  ▼
Client  200 / 4xx / 5xx
```

A decisão e o runtime COBOL estão descritos em
[docs/LOCAL-INTEGRATION.md](../docs/LOCAL-INTEGRATION.md).

## O que já existe

| Arquivo | Conteúdo |
|---|---|
| [DepositApi](src/main/java/com/clau/banking/svc/adapter/in/web/api/DepositApi.java) | Contrato HTTP: rota, headers, validação e documentação OpenAPI de todas as respostas |
| [DepositRequest](src/main/java/com/clau/banking/svc/adapter/in/web/dto/DepositRequest.java) | Body da requisição (`amount`, `currency`) |
| [DepositResponse](src/main/java/com/clau/banking/svc/adapter/in/web/dto/DepositResponse.java) | Resultado do lançamento |
| [ErrorResponse](src/main/java/com/clau/banking/svc/adapter/in/web/dto/ErrorResponse.java) | Contrato de erro e códigos permitidos |
| [MqProperties](src/main/java/com/clau/banking/svc/adapter/out/mq/config/MqProperties.java) | Filas e timeout de resposta (validados na inicialização) |
| [OpenApiConfiguration](src/main/java/com/clau/banking/svc/config/OpenApiConfiguration.java) | Metadados do OpenAPI |
| [application.yaml](src/main/resources/application.yaml) | Toda a configuração, externalizada por variáveis de ambiente |
| [Dockerfile](Dockerfile) | Imagem multi-stage, não-root, com healthcheck de readiness |

Pacotes previstos: `domain`, `application.port.in`, `application.port.out`, `application.service`,
`adapter.in.web` (controller, mapper, handler, correlation) e `adapter.out.mq` (encoder de layout,
publisher/requestor).

## Contrato HTTP

```http
POST /api/v1/accounts/1000000001/deposits
Content-Type: application/json
Idempotency-Key: 7f1c2a9e-5b3d-4c8e-9a01-000000000001
X-Correlation-Id: c0ffee00-0000-4000-8000-000000000001

{"amount": "100.50", "currency": "BRL"}
```

```json
{
  "transactionId": "0000000000000003",
  "status": "POSTED",
  "idempotentReplay": false,
  "accountId": "1000000001",
  "amount": "100.50",
  "newBalance": "1600.50",
  "currency": "BRL",
  "postedAt": "2026-09-16T10:30:00.000000",
  "correlationId": "c0ffee00-0000-4000-8000-000000000001"
}
```

| Elemento | Regra |
|---|---|
| `accountId` (path) | 10 dígitos, diferente de `0000000000`, tratado como **string** |
| `Idempotency-Key` (header) | Obrigatório, 16 a 36 caracteres `[A-Za-z0-9-]` |
| `X-Correlation-Id` (header) | Opcional, até 36 caracteres `[A-Za-z0-9-]`; gerar UUID quando ausente e sempre devolver |
| `amount` | `BigDecimal` > 0, até 13 inteiros e 2 decimais |
| `currency` | ISO 4217 maiúsculo |

### Tradução dos códigos COBOL para HTTP

| `RESPONSE-CODE` | HTTP | `code` |
|---|---|---|
| `0000` | 200 | – (`idempotentReplay = false`) |
| `0001` | 200 | – (`idempotentReplay = true`) |
| `1001`–`1008` | 400 | `INVALID_REQUEST` (o serviço deve validar antes; chegar aqui indica defeito) |
| `2001` | 404 | `ACCOUNT_NOT_FOUND` |
| `2002` | 422 | `ACCOUNT_NOT_ACTIVE` |
| `2004` | 422 | `BALANCE_LIMIT_EXCEEDED` |
| `2006` | 422 | `CUSTOMER_NOT_ACTIVE` |
| `2007` | 409 | `IDEMPOTENCY_KEY_CONFLICT` |
| `2008` | 422 | `CURRENCY_MISMATCH` |
| `9001`, `9002`, `9004`, `9999` | 503 | `CORE_BANKING_UNAVAILABLE` |
| sem resposta no timeout | 504 | `CORE_BANKING_TIMEOUT` |
| falha ao conectar/publicar no MQ | 503 | `CORE_BANKING_UNAVAILABLE` |

Códigos `2003` (saldo insuficiente) e `2005` só ocorrem em saque e consulta de transação.

## O que implementar

1. **Controller** `implements DepositApi` (as anotações de rota, header e validação são herdadas da interface).
2. **Correlation ID**: filtro que resolve `X-Correlation-Id`, coloca no MDC e devolve no header.
3. **Handler global** que produz `ErrorResponse` para validação, erros do core e falhas de infraestrutura,
   sem stack trace nem detalhes do MQ.
4. **Domínio e casos de uso** (`AccountId`, `Money`, `IdempotencyKey`, porta de entrada, porta de saída).
5. **Encoder/decoder de layout fixo**: `REQUEST.cpy` (200 bytes) e `RESPONSE.cpy` (300 bytes). Referência
   campo a campo: [mainframe-banking/docs/CONTRACT.md](../mainframe-banking/docs/CONTRACT.md).
   - Valor: sinal + 15 dígitos com 2 decimais implícitos (`+000000000010050`).
   - Timestamp da resposta: `YYYY-MM-DD-HH.MM.SS.NNNNNN`.
   - Completar com espaços até o tamanho exato; só caracteres invariantes.
6. **Adapter MQ request/reply** (único ponto que usa JMS):
   - destino com `targetClient=1`, por exemplo `queue:///BANKCORE.ACCTDEP.REQUEST?targetClient=1`, para
     enviar `MQSTR` sem cabeçalho RFH2. A fila tem `MAXMSGL(200)`, então mensagens com RFH2 são
     recusadas pelo próprio MQ (`MQRC 2030`);
   - `TextMessage` de exatamente 200 caracteres, `JMSReplyTo = BANKCORE.REPLY.BANKSVC`, entrega persistente,
     `timeToLive` = `MQ_REPLY_TIMEOUT`;
   - receber em `BANKCORE.REPLY.BANKSVC` com seletor `JMSCorrelationID = '<JMSMessageID da requisição>'`
     e timeout `MQ_REPLY_TIMEOUT`.
7. **Testes** de controller, casos de uso, encoder/decoder (use os arquivos de
   `mainframe-banking/tests/requests` e `tests/expected` como golden files) e adapter.

## Configuração

| Variável | Padrão | Uso |
|---|---|---|
| `SERVER_PORT` | `8080` | Porta HTTP |
| `MQ_HOST` / `MQ_PORT` | `localhost` / `1414` | Listener do queue manager |
| `MQ_QUEUE_MANAGER` | `QM1` | Queue manager |
| `MQ_CHANNEL` | `DEV.APP.SVRCONN` | Canal SVRCONN |
| `MQ_USERNAME` / `MQ_PASSWORD` | `app` / *(vazio)* | Credenciais; a senha nunca tem padrão |
| `MQ_DEPOSIT_REQUEST_QUEUE` | `BANKCORE.ACCTDEP.REQUEST` | Fila de requisições de depósito |
| `MQ_REPLY_QUEUE` | `BANKCORE.REPLY.BANKSVC` | Fila de respostas deste serviço |
| `MQ_REPLY_TIMEOUT` | `10s` | Tempo máximo de espera pela resposta do COBOL |
| `MQ_SESSION_CACHE_SIZE` | `10` | Sessões JMS em cache |
| `API_DOCS_ENABLED` | `true` | Swagger UI e `/v3/api-docs` |
| `LOGGING_STRUCTURED_FORMAT_CONSOLE` | *(texto)* | `ecs`, `logstash` ou `gelf` |

## Executar

```bash
./mvnw clean verify           # build + testes
docker compose up --build     # na raiz: IBM MQ + mainframe-banking + banking-svc
```

Swagger UI: http://localhost:8080/swagger-ui/index.html. O endpoint só aparece depois que o
controller for implementado.

## Decisões mantidas

- **Spring MVC, sem virtual threads** (`spring.threads.virtual.enabled=false`):
  - o fluxo request/reply é bloqueante;
  - o gargalo é a sessão MQ;
  - no Java 21, threads virtuais travam em blocos `synchronized` durante I/O (corrigido no Java 24).
- **Sem Lombok:** records bastam.
- **Actuator:** readiness inclui o health do JMS; só `health` e `info` são expostos.
- **Contrato HTTP separado do layout MQ:** a API em JSON evolui de forma independente do layout fixo
  do mainframe.

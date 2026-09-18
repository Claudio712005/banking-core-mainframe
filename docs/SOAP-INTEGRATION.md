# Integração microsserviço ↔ SOAP ↔ COBOL (mainframe-customer)

Guia do canal síncrono: o que já roda, o contrato e o que o futuro microsserviço precisa fazer.

## O que já está no ar

```text
cliente HTTP ──POST /customer-service──▶ Apache httpd (container mainframe-customer)
                                             │ CGI
                                             ▼
                                        CSTSOAP (COBOL)
                                             │ CALL
                                        CUSTINQ / CRDINQ ──▶ arquivos
                                             │
cliente HTTP ◀────── XML (200 ou Fault 500) ─┘
```

- Endpoint: `http://localhost:8081/customer-service`
- Contrato: `http://localhost:8081/customer-service.wsdl`
- Namespace: `http://bankcore.example/customer/v1`
- `SOAPAction` é **obrigatória** e escolhe a operação: `GetCustomer` ou `GetCreditLimit`.

Diferente do `mainframe-banking`, aqui não há fila, idempotência nem unidade de trabalho: são
duas consultas, sem efeito colateral.

## Requisição

```http
POST /customer-service HTTP/1.1
Content-Type: text/xml; charset=utf-8
SOAPAction: "GetCustomer"
X-Correlation-Id: c0ffee00-0000-4000-8000-000000000001

<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
  <soapenv:Body>
    <GetCustomer xmlns="http://bankcore.example/customer/v1">
      <customerId>0000000001</customerId>
    </GetCustomer>
  </soapenv:Body>
</soapenv:Envelope>
```

| Elemento | Regra |
|---|---|
| Método | Somente `POST`; qualquer outro recebe 403 |
| `SOAPAction` | Obrigatória, com ou sem aspas; fora da lista gera Fault 1001 |
| Corpo | Até 8 KB; acima disso o servidor responde 413 |
| `customerId` | 10 dígitos, diferente de zeros; aceita prefixo de namespace (`<cus:customerId>`) |
| `X-Correlation-Id` | Opcional, só caracteres `[A-Za-z0-9-.* ]`; usado no log, descartado se inválido |

## Respostas

`GetCustomer` (HTTP 200):

```xml
<GetCustomerResponse xmlns="http://bankcore.example/customer/v1">
  <customerId>0000000001</customerId>
  <name>MARIA OLIVEIRA SANTOS</name>
  <status>A</status>
  <documentMasked>***.***.***-25</documentMasked>
  <registeredDate>2019-03-14</registeredDate>
</GetCustomerResponse>
```

`GetCreditLimit` (HTTP 200):

```xml
<GetCreditLimitResponse xmlns="http://bankcore.example/customer/v1">
  <customerId>0000000005</customerId>
  <currency>USD</currency>
  <approvedLimit>2000.00</approvedLimit>
  <usedLimit>750.25</usedLimit>
  <availableLimit>1249.75</availableLimit>
</GetCreditLimitResponse>
```

Fault (HTTP 500):

```xml
<soapenv:Fault>
  <faultcode>soapenv:Client</faultcode>
  <faultstring>CUSTOMER NOT FOUND</faultstring>
  <detail>
    <error xmlns="http://bankcore.example/customer/v1">
      <code>2001</code>
    </error>
  </detail>
</soapenv:Fault>
```

## Tradução sugerida para HTTP no microsserviço

| Código | `faultcode` | HTTP sugerido | Observação |
|---|---|---|---|
| 0000 | – | 200 | – |
| 1001 | Client | 400 | Defeito do cliente: envelope, ação ou tamanho |
| 1002 | Client | 400 | Identificador fora do formato |
| 2001 | Client | 404 | Cliente não encontrado |
| 2002 | Client | 422 | Cliente não está ativo |
| 2003 | Client | 404 ou 422 | Cliente sem linha de crédito; depende do produto |
| 9001 / 9002 / 9999 | Server | 502 ou 503 | Falha do legado; pode repetir |
| sem resposta no timeout | – | 504 | Consulta sem efeito colateral: repetir é seguro |

Valores monetários chegam como decimal com 2 casas: use `BigDecimal`, nunca `double`.
`registeredDate` é `YYYY-MM-DD`.

## Recomendações para o cliente

| Tema | Recomendação |
|---|---|
| Cliente SOAP | Gerar a partir do WSDL (JAX-WS/`wsimport`, Spring WS ou CXF), ou montar o envelope à mão: o contrato é pequeno e plano |
| Timeouts | Conexão e leitura curtos (por exemplo 2 s e 5 s); é uma consulta, não um lançamento |
| Retry | Seguro para 9xxx e timeout, porque as operações são de leitura; use backoff |
| Circuit breaker | Recomendado: uma consulta lenta não pode travar o fluxo do chamador |
| Cache | Cadastro muda pouco; limite muda com frequência. Se cachear, faça por operação, com TTL curto |
| Log | Não registre `name` nem `documentMasked`; propague o `X-Correlation-Id` |
| Erros | Trate pelo `<code>` do `detail`, não pelo `faultstring` |

## Diferenças em relação ao canal MQ

| Tema | `mainframe-banking` (MQ) | `mainframe-customer` (SOAP) |
|---|---|---|
| Natureza | Assíncrona, request/reply por fila | Síncrona, requisição e resposta na mesma conexão |
| Acoplamento temporal | Baixo: o core pode estar fora do ar e a mensagem espera | Alto: o core fora do ar derruba a chamada |
| Efeito colateral | Movimenta dinheiro; exige idempotência | Só leitura; repetir não muda nada |
| Entrega | Garantida, com backout e reentrega | Nenhuma: falhou, perdeu-se |
| Contrato | Layout fixo de 200/300 bytes | XML com WSDL |
| Erro | Código no layout, mais fila de backout | SOAP Fault com HTTP 500 |
| Custo por requisição | Fila, syncpoint e correlação | Uma conexão HTTP e um processo CGI |
| Quando preferir | Operação que altera estado e não pode se perder | Consulta que precisa de resposta imediata |

O laboratório tem os dois de propósito: o mesmo estilo de núcleo COBOL, com duas naturezas de
integração, para comparar o efeito de cada escolha no microsserviço que consome.

## Limitações

- Ambiente local: sem TLS, sem autenticação e sem CICS ou DB2.
- Um processo CGI por requisição e leitura sequencial dos arquivos.
- Só leitura: não há operação de alteração.
- O WSDL declara `http://localhost:8081`; ajuste o endereço ao publicar em outro host.

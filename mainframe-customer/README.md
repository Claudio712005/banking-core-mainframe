# mainframe-customer

Sistema legado de **cadastro de clientes e limite de crédito**, escrito em COBOL e exposto por
**SOAP sobre HTTP**. É o segundo mainframe do laboratório: o contraponto síncrono do
[mainframe-banking](../mainframe-banking), que integra por IBM MQ.

```text
microsserviço ──SOAP/HTTP──▶ Apache httpd ──CGI──▶ CSTSOAP (COBOL)
                                                      │ CALL
                                                      ▼
                                              CUSTINQ / CRDINQ
                                                      │
                                                      ▼
                                          CUSTDAO / CREDDAO → arquivos
```

O COBOL monta e lê o XML; não há tradutor em outra linguagem no meio. No z/OS o equivalente seria
CICS Web Support ou z/OS Connect publicando o mesmo WSDL.

## Operações

| SOAPAction | Entrada | Saída |
|---|---|---|
| `GetCustomer` | `customerId` (10 dígitos) | `customerId`, `name`, `status`, `documentMasked`, `registeredDate` |
| `GetCreditLimit` | `customerId` | `customerId`, `currency`, `approvedLimit`, `usedLimit`, `availableLimit` |

Contrato publicado: [www/customer-service.wsdl](www/customer-service.wsdl), servido em
`/customer-service.wsdl`.

## Estrutura

```text
mainframe-customer/
├── programs/
│   ├── customer/       CUSTINQ.cbl      consulta cadastral
│   ├── credit/         CRDINQ.cbl       consulta de limite
│   ├── common/         CSTVAL.cbl       validação de entrada
│   │                   CSTRESP.cbl      códigos, mensagens e log técnico
│   │                   CUSTDAO.cbl CREDDAO.cbl   acesso a dados (LAB)
│   ├── driver/         CUSTDRV.cbl      driver batch usado nos testes
│   └── adapter/        CSTSOAP.cbl      adaptador SOAP (CGI)
├── copybooks/          CUSTREQ CUSTRSP CSTCODE     contrato interno
│                       CUSTREC CREDREC             entidades
│                       CSTDAO CSTCTL               interfaces internas
├── data/               CUSTMAST.dat CREDMAST.dat   massa base
├── tests/              requests/ expected/ soap/   regressão e testes HTTP
├── runtime/            httpd.conf entrypoint.sh
├── www/                customer-service.wsdl
├── scripts/            build.sh run.sh run-tests.sh
│                       soap-request.sh run-soap-tests.sh
└── Dockerfile
```

Camadas: o transporte (`CSTSOAP`, `CUSTDRV`) conhece XML ou arquivos; os programas de entrada
conhecem só os layouts de 100/300 bytes; os DAOs conhecem só os arquivos. Trocar SOAP por outra
coisa não afeta o núcleo.

## Executar

Na raiz do repositório:

```bash
docker compose up --build mainframe-customer
```

```bash
curl -sS -H 'SOAPAction: "GetCustomer"' -H 'Content-Type: text/xml; charset=utf-8' \
  --data-binary @mainframe-customer/tests/soap/envelopes/customer-active.xml \
  http://localhost:8081/customer-service
```

```xml
<GetCustomerResponse xmlns="http://bankcore.example/customer/v1">
  <customerId>0000000001</customerId>
  <name>MARIA OLIVEIRA SANTOS</name>
  <status>A</status>
  <documentMasked>***.***.***-25</documentMasked>
  <registeredDate>2019-03-14</registeredDate>
</GetCustomerResponse>
```

Atalho equivalente: `scripts/soap-request.sh GetCustomer <envelope>`.

## Testes

```bash
scripts/run-tests.sh        # regressão COBOL, sem rede (16 + 3 cenários)
scripts/run-soap-tests.sh   # 12 casos SOAP + 2 regras de transporte (container no ar)
```

A regressão COBOL roda também dentro do build da imagem: se falhar, a imagem não é gerada.

| Cenário | Resultado |
|---|---|
| Cliente ativo / bloqueado | 200 com `status` A ou B |
| Cliente inexistente | Fault `Client`, código 2001 |
| Identificador inválido | Fault `Client`, código 1002 |
| Limite disponível, esgotado, em USD | 200 com `availableLimit` |
| Cliente bloqueado consultando limite | Fault `Client`, código 2002 |
| Cliente sem linha de crédito | Fault `Client`, código 2003 |
| `SOAPAction` desconhecida, corpo sem `customerId` | Fault `Client`, código 1001 |
| Registro corrompido (uso > aprovado) | Fault `Server`, código 9002 |
| `GET` no endpoint | 403 |
| Corpo acima de 8 KB | 413 |

## Códigos e Faults

| Código | Fault | Significado |
|---|---|---|
| 0000 | – | Sucesso |
| 1001 | Client | Requisição inválida: método, `SOAPAction`, tamanho ou corpo sem `customerId` |
| 1002 | Client | Identificador fora do formato (10 dígitos, diferente de zeros) |
| 2001 | Client | Cliente não encontrado |
| 2002 | Client | Cliente não está ativo |
| 2003 | Client | Cliente sem linha de crédito |
| 9001 / 9002 / 9999 | Server | Falha de acesso a dados, dado corrompido ou erro inesperado |

Todo Fault viaja com HTTP 500, como manda o SOAP 1.1. O `faultstring` traz a mensagem padronizada
e o `detail` traz o código. Nada de caminho de arquivo, file status ou dado pessoal.

## Configuração

| Variável | Padrão | Uso |
|---|---|---|
| `SERVICE_PORT` | `8081` | Porta HTTP do container |
| `CUSTCORE_DATA_DIR` | `/var/lib/custcore` | Diretório dos arquivos de dados (volume) |
| `DD_CUSTMAST` / `DD_CREDMAST` | derivados do diretório acima | Arquivos de cadastro e de crédito |
| `CUSTOMER_SERVICE_URL` | `http://localhost:8081/customer-service` | Usado pelos scripts de teste |

Para voltar os dados à massa inicial:

```bash
docker compose rm -sf mainframe-customer
docker volume rm banking-core-mainframe_customer-core-data
docker compose up -d mainframe-customer
```

O entrypoint só copia a massa base quando o arquivo ainda não existe, então alterar `data/` sem
recriar o volume não muda o que o container enxerga.

## Segurança

- O corpo **não é interpretado como XML**: só o valor entre as tags `customerId` é extraído, então
  `DOCTYPE` e entidades externas não têm efeito (não há XXE por construção).
- Todo valor devolvido passa por um filtro de caracteres seguros, então o dado não consegue quebrar
  o XML da resposta.
- O documento do cliente só sai mascarado (`***.***.***-NN`).
- `LimitRequestBody` de 8 KB no servidor e verificação do `Content-Length` no COBOL.
- Só `POST` é aceito no endpoint; listagem de diretório e execução de CGI fora do diretório do
  serviço estão desativadas.
- Container como usuário não-root (uid 10002), sistema de arquivos somente leitura, sem
  capabilities, porta publicada só em `127.0.0.1`.

**Fora do escopo:** autenticação (WS-Security ou mTLS), TLS e autorização por cliente. São
necessários antes de qualquer uso real.

## Limitações

- Laboratório: sem CICS, sem DB2, sem EBCDIC e sem RACF.
- Leitura sequencial dos arquivos a cada requisição, e um processo CGI por requisição.
- Operações apenas de leitura; não há alteração de cadastro nem de limite.
- `availableLimit` é calculado na hora (`aprovado - usado`), nunca armazenado.
- O runtime do GnuCOBOL roda com avisos desligados no CGI, porque a entrada padrão é um pipe e
  geraria um aviso por requisição. Erros reais continuam aparecendo pelos códigos de resposta.

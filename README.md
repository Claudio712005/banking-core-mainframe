# banking-core-mainframe

Laboratório de integração entre microsserviços modernos e **dois** sistemas legados em COBOL, cada
um com uma natureza de integração diferente.

```text
Client ──HTTP/JSON──▶ banking-svc   ──IBM MQ (assíncrono)──▶ mainframe-banking  (contas e lançamentos)
Client ──HTTP/JSON──▶ customer-svc  ──SOAP/HTTP (síncrono)──▶ mainframe-customer (cadastro e crédito)
```

| Módulo | Conteúdo |
|---|---|
| [mainframe-banking](mainframe-banking) | Core de contas em COBOL, consumindo IBM MQ (`BKMQLSN`) |
| [mainframe-customer](mainframe-customer) | Cadastro e limite de crédito em COBOL, exposto por SOAP |
| [banking-svc](banking-svc) | Microsserviço Java 21 / Spring Boot 4: contratos e configuração (implementação em andamento) |
| [infrastructure](infrastructure) | Definições do IBM MQ local (MQSC) |
| [docs](docs) | Guias de integração e decisões |
| [docker-compose.yaml](docker-compose.yaml) | `ibm-mq` + `mainframe-banking` + `mainframe-customer` + `banking-svc` |

## Início rápido

```bash
docker compose up --build
```

Depósito direto no core bancário, pelo MQ:

```bash
sed -n 6p mainframe-banking/tests/requests/functional.req \
  | mainframe-banking/scripts/mq-request.sh ACCTDEP
```

Consulta de cliente, por SOAP:

```bash
curl -sS -H 'SOAPAction: "GetCustomer"' -H 'Content-Type: text/xml; charset=utf-8' \
  --data-binary @mainframe-customer/tests/soap/envelopes/customer-active.xml \
  http://localhost:8081/customer-service
```

| Serviço | Porta | Observação |
|---|---|---|
| `ibm-mq` | 1414, 9443 | Imagem IBM, só amd64: emulada no Apple Silicon |
| `mainframe-banking` | – | Consome as filas `BANKCORE.*` |
| `mainframe-customer` | 8081 | Imagem nativa, build rápida |
| `banking-svc` | 8080 | Casca: contratos e configuração |

Notas:

- A primeira build do `mainframe-banking` leva alguns minutos (GnuCOBOL 3.2 e client IBM MQ).
- As credenciais do `docker-compose.yaml` são **só para desenvolvimento local** (`.env.example`).
- Subir o ambiente aceita as licenças de desenvolvimento do IBM MQ (servidor e client).

## Documentação

| Documento | Conteúdo |
|---|---|
| [docs/LOCAL-INTEGRATION.md](docs/LOCAL-INTEGRATION.md) | Como o COBOL consome o IBM MQ localmente e por que essa abordagem |
| [docs/SOAP-INTEGRATION.md](docs/SOAP-INTEGRATION.md) | Canal SOAP, contrato, Faults e comparação entre os dois estilos de integração |
| [mainframe-banking/README.md](mainframe-banking/README.md) | Core bancário: arquitetura, contrato de 200/300 bytes, testes |
| [mainframe-customer/README.md](mainframe-customer/README.md) | Cadastro e crédito: operações, WSDL, testes |
| [banking-svc/README.md](banking-svc/README.md) | Contratos da API e o que falta implementar |

## Estado atual

| Parte | Estado |
|---|---|
| `mainframe-banking` consumindo MQ | Funcionando e validado ponta a ponta |
| `mainframe-customer` em SOAP | Funcionando e validado ponta a ponta |
| `banking-svc` | Casca: `DepositApi`, DTOs e configuração |
| `customer-svc` | Não existe ainda: é o próximo microsserviço, consumindo o SOAP |

# banking-core-mainframe

Laboratório de integração entre um microsserviço Java/Spring Boot e um core bancário legado
em COBOL, usando IBM MQ.

```text
Client ──HTTP/JSON──▶ banking-svc ──IBM MQ (request/reply)──▶ BKMQLSN ──▶ programas COBOL
```

| Módulo | Conteúdo |
|---|---|
| [banking-svc](banking-svc) | Microsserviço Java 21 / Spring Boot 4: contratos da API e configuração (implementação em andamento) |
| [mainframe-banking](mainframe-banking) | Programas COBOL, copybooks, JCL, testes e o container que consome o IBM MQ |
| [infrastructure](infrastructure) | Definições do IBM MQ local (MQSC) |
| [docs](docs) | [LOCAL-INTEGRATION.md](docs/LOCAL-INTEGRATION.md): como o COBOL roda localmente consumindo o MQ |
| [docker-compose.yaml](docker-compose.yaml) | `ibm-mq` + `mainframe-banking` + `banking-svc` |

## Início rápido

```bash
docker compose up --build
```

Enviar um depósito direto ao COBOL pelo MQ (sem o Java):

```bash
sed -n 6p mainframe-banking/tests/requests/functional.req \
  | mainframe-banking/scripts/mq-request.sh ACCTDEP
```

- A primeira build do `mainframe-banking` leva alguns minutos: compila o GnuCOBOL 3.2, baixa o
  client IBM MQ e roda a regressão COBOL.
- As imagens IBM MQ são só amd64; no Apple Silicon rodam emuladas.
- As credenciais do `docker-compose.yaml` servem **só para desenvolvimento local**
  (veja `.env.example`).
- Ao subir o ambiente você aceita a licença do IBM MQ Advanced for Developers e a do
  IBM MQ redistributable client.

## Estado atual

| Parte | Estado |
|---|---|
| COBOL consumindo o MQ (`BKMQLSN`) | Funcionando e validado ponta a ponta |
| Filas `BANKCORE.*`, backout e autorização | Funcionando |
| `banking-svc` | Casca: contratos (`DepositApi` e DTOs), configuração e Dockerfile. Controller, domínio, casos de uso e adapter MQ a implementar ([README](banking-svc/README.md)) |

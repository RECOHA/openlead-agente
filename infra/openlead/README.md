# OpenLead no Coolify (VPS-01)

O passo a passo completo é o do próprio OpenLead (`openlead/infra/runbooks/`: `coolify.md`,
`deploy.md`, `restauracao.md`). Aqui fica só o que muda na infra nova e o estado atual.

## O que muda em relação aos runbooks do OpenLead

| Runbook diz | Infra nova |
|---|---|
| VPS `contabo-openleads`, Coolify do Curion (`server.curion.com.br`) | VPS-01 (Hostinger), Coolify da VPS-00 (`https://server.openlead.app`) |
| Segredos no gerenciador de senhas do Renan | `.env.openlead.enc` neste repo (SOPS) |
| Backup no R2, compose oficial com `PGBACKREST_*` obrigatórias | Backup vai para o S3 da Contabo, **ainda não ligado**. Até lá o banco sobe com `openlead-db.coolify.yml` (gerado por `render-db.sh`): `archive_mode = off` e `PGBACKREST_*` opcionais |
| Base da Receita trazida do spike | Import do zero na VPS-01 (decisão do Renan, 2026-11-07), para não sobrar nada do spike |

Recursos: VPS-01 tem 4 CPUs e 15 GB. Os limites dos composes do OpenLead (banco 4 CPUs / 6 GB,
`web` 2 / 2,5 GB, `worker` 2 / 1,5 GB) cabem como estão. Disco: 193 GB; o pico medido no spike foi
94 GB.

## Arquivos

| Arquivo | O que é |
|---|---|
| `render-db.sh` | Gera `openlead-db.coolify.yml` a partir do repo do OpenLead (variante sem backup) |
| `openlead-db.coolify.yml` | O compose que vai para o recurso `openlead-db` |
| `../../.env.openlead.enc` | Segredos do app (GHCR, Better Auth, Turnstile, Resend, S3 da exportação) |

## Ordem do deploy

1. Coolify: projeto `OpenLead`, ambiente `production`, servidor VPS-01; registry `ghcr.io` (token do `.env.openlead`).
2. `openlead-db` com `openlead-db.coolify.yml`; rede `coolify`; start; copiar as `SERVICE_PASSWORD_*` para `.env.openlead`.
3. `openlead-ops` e `openlead-app` com os composes do OpenLead como estão; variáveis; domínio `https://openlead.app:3000` no `web`.
4. GitHub (`recoha/openlead`, environment `production`): `COOLIFY_URL`, `COOLIFY_TOKEN` (só `read` + `deploy`), `COOLIFY_OPS_UUID`, `COOLIFY_APP_UUID`; variável `DEPLOY_ENABLED=true`; rodar o workflow `deploy`.
5. `node apps/worker/src/registry-cli.ts start` no terminal do `worker` e acompanhar com `status` (~6 h ou mais).

## Pendências

- [ ] Token da API do Coolify (o Renan cria no painel: Keys & Tokens). A API está desligada.
- [ ] Preencher no `.env.openlead`: `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY`, `RESEND_API_KEY`, `ALERT_EMAIL`, `EXPORTS_S3_*`.
- [ ] Backup no S3 da Contabo (depois).

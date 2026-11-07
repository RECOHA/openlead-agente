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

## No Coolify (VPS-00)

| O quê | UUID |
|---|---|
| Projeto `OpenLead` | `sxrbnltosxl5fts86pkolkfk` (ambiente `production`) |
| Servidor VPS-01 | `j712k7ybasymkytynpnt001k` (registry `ghcr.io` logado como `RECOHA`) |
| `openlead-db` | `ywco8vhh6fnefyedbaqw2ak5` (container `postgres-ywco8vhh6fnefyedbaqw2ak5`) |
| `openlead-ops` | `vadwerrxhzbfdlm7znomjeq9` |
| `openlead-app` | `v47eozls3yfsq7f8cvng3wlf` (domínio `https://openlead.app` no `web`; a porta 3000 vem do `EXPOSE` da imagem) |

Tokens da API (`.env.coolify`): `COOLIFY_API_TOKEN` (id 1, `root`, só aqui) e `COOLIFY_CI_TOKEN`
(id 2, `read` + `deploy`, segredo `COOLIFY_TOKEN` do GitHub).

## Pendências

- [x] Token da API do Coolify.
- [x] `openlead-db` no ar; senhas em `.env.openlead`.
- [x] `openlead-ops` e `openlead-app` criados; URLs de banco, Better Auth e `ACCOUNT_EMAIL_FROM` preenchidas.
- [x] Segredos do environment `production` no GitHub apontando para o Coolify novo.
- [x] Turnstile, Resend e `EXPORTS_S3_*` (Contabo `usc1`, bucket `openlead-exports`) copiados dos containers do spike na VPS-10.
- [ ] `ALERT_EMAIL` + `EMAIL_FROM` (juntos; vazios também no spike). Sem eles os alertas ficam só no painel, sem e-mail.
- [x] Primeiro deploy (2026-11-07, SHA `df09892`): `https://openlead.app/api/health` ok, vindo da VPS-01.
- [ ] Import da Receita (202610) começou às 15:31 UTC de 2026-11-07; download a ~87 Mbit/s.
- [ ] Backup no S3 da Contabo (depois).

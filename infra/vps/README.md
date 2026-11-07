# VPSs do openlead

## Ecossistema

| Projeto | O que é | Onde roda |
|---|---|---|
| OpenLead | O SaaS: `web` (landing + app + admin + backend, um Next.js só), `worker` (bastidor: import da Receita, exportação, e-mail, pagamentos) e `db` (Postgres com tudo, inclusive a base CNPJ) | VPS-01 |
| OpenLead Scout | `scout`: workers que consultam o Google Maps 24 h por dia | VPS-10 (depois VPS-11, 12…) |
| OpenLead Agent | Este repo: servidores, segurança, backups, segredos | — |

Futuro: `web` + `worker` numa VPS e `db` em outra; mais VPS de Scout em paralelo. Scout e OpenLead
vão conversar por uma rede privada entre as VPS (WireGuard), sem abrir a porta do banco.

## Servidores

| Nome | IP | Provedor | Papel | Config local |
|---|---|---|---|---|
| VPS-00 | 5.253.233.219 | Contabo | Só o Coolify (painel https://server.openlead.app), que gerencia as outras | `.env.coolify.enc` |
| VPS-01 | 179.197.231.251 | Hostinger | OpenLead (`web`, `worker`, `db`), gerenciado pelo Coolify da VPS-00 | `.env.vps-01.enc` |
| VPS-10 | 164.68.96.72 | Contabo | Scout (6 vCPU, 11 GB). Formatada em 2026-11-07, montada como a VPS-01, no Coolify sem proxy (não recebe tráfego da internet; só a 22 aberta) | `.env.vps-10.enc` (tem a senha de root, para o console da Contabo) |

As chaves de host ficam em `known_hosts` (nesta pasta); o `scripts/vps.sh` recusa uma VPS cuja
chave mudou. Depois de formatar uma VPS, grave a chave nova: `ssh-keyscan -t ed25519 <ip>`.

O deploy do OpenLead no Coolify está em [`../openlead/README.md`](../openlead/README.md).

Todas usam Ubuntu 26.04 e Docker 29.9.3, e recebem os mesmos arquivos abaixo.

| Arquivo | Destino na VPS | Função |
|---|---|---|
| `openlead-firewall.sh` | `/usr/local/sbin/` | Bloqueia de fora as portas 8000, 6001, 6002 e 8080 (IPv4 e IPv6) |
| `openlead-firewall.service` | `/etc/systemd/system/` | Reaplica o firewall no boot e quando o Docker reinicia |
| `00-openlead-hardening.conf` | `/etc/ssh/sshd_config.d/` | SSH só por chave (senha desativada) |

Portas abertas: 22 (SSH por chave), 80 e 443 (Traefik/Coolify).
Painel: https://server.openlead.app (credenciais em `.env.coolify.enc`).

## Acesso SSH

```bash
scripts/secrets.sh decrypt        # se os segredos ainda não estiverem abertos
scripts/vps.sh                    # shell na VPS-00
scripts/vps.sh vps-01 'docker ps' # comando na VPS-01 (vale para qualquer vps-NN)
```

`root` de cada VPS aceita duas chaves:

- `openlead-agente@server.openlead.app`: chave do projeto (`secrets/openlead_vps_ssh.enc`)
- `coolify`: chave "localhost's key" do Coolify, usada pelo painel para gerenciar o servidor

## Como a VPS-01 foi montada

1. Chaves acima em `/root/.ssh/authorized_keys`.
2. `/etc/docker/daemon.json` igual ao da VPS-00 e Docker pelo `get.docker.com`.
3. `curl wget git jq` (pré-requisitos do Coolify).
4. Os três arquivos da tabela, `systemctl enable --now openlead-firewall` e `systemctl reload ssh`.
5. No Coolify: servidor `VPS-01` (root@179.197.231.251:22, chave "localhost's key"), validado; proxy Traefik e Sentinel iniciados pelo Coolify.

## Foto das VPSs

`snapshot/` (VPS-00) e `snapshot-vps-01/` (VPS-01) são cópias, só para leitura, de como as VPSs estão agora. Para atualizar:

```bash
scripts/secrets.sh decrypt       # se os segredos ainda não estiverem abertos
scripts/vps-snapshot.sh          # VPS-00 -> snapshot/
scripts/vps-snapshot.sh vps-01   # VPS-01 -> snapshot-vps-01/
git diff infra/vps               # mostra o que mudou desde a última foto
```

O script também avisa se os arquivos acima, ou o `.env` do Coolify, estão diferentes do que temos no repo.

| Pasta | O que tem |
|---|---|
| `system/` | SO, pacotes, serviços, portas, firewall, SSH, sysctl, cron, usuários, containers |
| `coolify/` | Só na VPS-00: docker-compose da instalação, **nomes** das variáveis do `.env`, e o que está cadastrado no painel (servidores, projetos, apps, bancos) |
| `proxy/` | docker-compose do Traefik, rotas (`dynamic/`) e domínios com certificado |

Nunca entram na foto: valores do `.env`, `acme.json` (chaves dos certificados) e chaves SSH.
Os valores do `.env` do Coolify ficam em `.env.coolify-instance.enc`.

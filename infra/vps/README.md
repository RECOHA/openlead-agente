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
| VPS-10 | 164.68.96.72 | Contabo | Scout (6 vCPU, 11 GB). Formatada em 2026-11-07, montada como a VPS-01. O Coolify subiu o proxy (80/443), mas nenhum domínio aponta para ela | `.env.vps-10.enc` (tem a senha de root, para o console da Contabo) |

As chaves de host ficam em `known_hosts` (nesta pasta); o `scripts/vps.sh` recusa uma VPS cuja
chave mudou. Depois de formatar uma VPS, grave a chave nova: `ssh-keyscan -t ed25519 <ip>`.

O deploy do OpenLead no Coolify está em [`../openlead/README.md`](../openlead/README.md).

Todas usam Ubuntu 26.04 e Docker 29.9.3, e recebem os mesmos arquivos abaixo.

| Arquivo | Destino na VPS | Função |
|---|---|---|
| `00-openlead-hardening.conf` | `/etc/ssh/sshd_config.d/` | SSH só por chave, sem X11, no máximo 3 tentativas por conexão |
| `openlead-firewall.sh` | `/usr/local/sbin/` | Bloqueia de fora as portas 8000, 6001, 6002 e 8080 (IPv4 e IPv6). O Docker passa por cima do ufw, por isso esta regra fica na chain `DOCKER-USER` |
| `openlead-firewall.service` | `/etc/systemd/system/` | Reaplica o firewall no boot e quando o Docker reinicia |
| `openlead.local` | `/etc/fail2ban/jail.d/` | fail2ban no SSH: 5 erros em 10 min = 1 h de bloqueio. Nunca bloqueia as redes Docker nem a VPS-00 |
| `daemon.json` | `/etc/docker/` | Logs com limite (10 MB × 3) e `live-restore` (o Docker reinicia sem derrubar os contêineres) |
| `security-headers.yaml` | `/data/coolify/proxy/dynamic/` | Cabeçalhos de segurança em todo site HTTPS (HSTS de 1 ano, `nosniff`, `Referrer-Policy`) |
| `docker-compose.custom.yml` | `/data/coolify/source/` (só VPS-00) | Portas do Coolify (8000, 6001, 6002) só em `127.0.0.1`. O `upgrade.sh` do Coolify usa este arquivo sozinho |

Além dos arquivos: **ufw** ligado (entra só 22, 80 e 443 tcp, e 443 udp) e **sem o usuário `ubuntu`**
(só `root`, por chave).

Tudo isso se aplica com um comando (pode rodar de novo; só muda o que falta):

```bash
scripts/vps-apply.sh vps-NN
```

Antes de ligar o ufw, o script agenda um `ufw disable` para 5 min depois e só cancela se uma conexão
SSH **nova** entrar. Se o SSH cair, o ufw se desliga sozinho.

O `docker-compose.custom.yml` da VPS-00 não está no script (precisa recriar o contêiner do Coolify,
~30 s de painel fora):

```bash
scripts/vps.sh vps-00 'cat > /data/coolify/source/docker-compose.custom.yml' < infra/vps/docker-compose.custom.yml
scripts/vps.sh vps-00 'cd /data/coolify/source && docker compose --env-file .env -f docker-compose.yml \
  -f docker-compose.prod.yml -f docker-compose.custom.yml up -d --no-deps --wait coolify'
```

Acesso de emergência ao painel (se o domínio cair): `ssh -L 8000:127.0.0.1:8000 root@5.253.233.219`
e abrir http://localhost:8000.

### Proxy (Traefik)

O compose do proxy fica no **banco do Coolify** (ele regrava o disco com essa versão em todo restart).
Por isso a mudança é pela API, nunca editando o arquivo na VPS:

1. `GET /api/v1/servers/<uuid>/proxy` (campo `configuration`).
2. `PUT /api/v1/servers/<uuid>/proxy/configuration` com `{"configuration": "<yaml>"}`.
3. `POST /api/v1/servers/<uuid>/proxy/restart` (o site fica fora ~5 s).

Padrão nas 3 VPS: `traefik:v3.7.17` (versão fixa, nunca tag solta), sem a porta `8080` (o dashboard do
Traefik não abre de fora) e `--entrypoints.https.http.middlewares=security-headers@file`. Crie o
`security-headers.yaml` **antes** de pôr essa linha: sem o arquivo, todos os sites dão erro.

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
2. `/etc/docker/daemon.json` (o desta pasta) e Docker pelo `get.docker.com`.
3. `curl wget git jq` (pré-requisitos do Coolify).
4. `scripts/vps-apply.sh vps-NN` (SSH, firewall, fail2ban, ufw, Docker, cabeçalhos, sem `ubuntu`).
5. No Coolify: servidor `VPS-01` (root@179.197.231.251:22, chave "localhost's key"), validado; proxy Traefik e Sentinel iniciados pelo Coolify.
6. Proxy no padrão (seção "Proxy" acima), pela API do Coolify.

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

## Travas do Claude (hooks)

Configuradas em `.claude/settings.json` (copiadas do agent-global e adaptadas):

| Hook | Quando | O que faz |
|---|---|---|
| `scripts/hooks/claude_gate.py` | Antes de cada comando | Pede a sua liberação para SSH (`vps.sh`, `vps-apply.sh`, `ssh`...), escrita na API do Coolify ou por HTTP, cofre (`secrets.sh`, `sops`, `age -d`), `git push` e escrita pelo `gh`. No modo auto ele não pergunta (quem decide é o classificador do modo auto) |
| `scripts/hooks/claude_drift.py mark` | Depois de cada comando | Anota quais VPS foram tocadas (em `.claude/drift/`, fora do git) |
| `scripts/hooks/claude_drift.py stop` | No fim de cada resposta | Tira a foto das VPS tocadas. Se um arquivo instalado não bate com `infra/vps/` ou se a foto mudou sem ir para o git, não deixa o Claude terminar (uma vez) até trazer a mudança para o repo |

## Histórico

- **2026-11-08 03:05–03:16 UTC** (pedido do Renan, depois do estudo com o agent-global), nas 3 VPS:
  SSH com `X11Forwarding no` e `MaxAuthTries 3`; fail2ban no SSH; ufw ligado (22, 80, 443); Docker com
  `live-restore` (recarregado, nenhum contêiner parou); usuário `ubuntu` apagado (VPS-00 e VPS-10; a VPS-01
  já não tinha). VPS-00: Coolify só em `127.0.0.1` (painel fora ~30 s). Proxy das 3 pela API do Coolify:
  `traefik:v3.7.17` fixo, sem a 8080, com `security-headers` (openlead.app fora ~5 s; painel e VPS-10 idem).
  Conferido: openlead.app 200 com HSTS, `nosniff` e `Referrer-Policy`; http → https; 8000, 6001, 6002 e
  8080 fechadas de fora; contêineres saudáveis e com saída para a internet; Coolify alcança as 3 VPS;
  `vps-snapshot.sh` com todos os arquivos `OK`.
  Atenção: com `MaxAuthTries 3`, um `ssh` à mão com muitas chaves no agente pode ser recusado antes de
  chegar na certa. Use `-o IdentitiesOnly=yes -i <chave>` (o `scripts/vps.sh` já faz isso).
- **2026-11-08 ~03:40 UTC**: travas do Claude (hooks `claude_gate.py` e `claude_drift.py`, ver acima). Hooks
  do bmad-loop com o caminho certo (`bmad-loop`, do PATH; antes apontavam para `C:/Users/renan.hagiwara/`, que
  não existe neste PC, e falhavam calados). A foto do fail2ban guarda só a config (sem contadores). Visto no
  teste: o fail2ban da VPS-10 já tinha banido 5 IPs na primeira meia hora.

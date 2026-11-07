# VPSs do openlead

| Nome | IP | Provedor | Papel | Config local |
|---|---|---|---|---|
| VPS-00 | 5.253.233.219 | Contabo | Roda o Coolify (painel https://server.openlead.app) | `.env.coolify.enc` |
| VPS-01 | 179.197.231.251 | Hostinger | Servidor gerenciado pelo Coolify da VPS-00 (sem Coolify próprio) | `.env.vps-01.enc` |

As duas usam Ubuntu 26.04 e Docker 29.9.3, e recebem os mesmos arquivos abaixo.

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
scripts/vps.sh vps-01 'docker ps' # comando na VPS-01
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

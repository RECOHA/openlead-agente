# VPS server.openlead.app

Cópia do que está instalado na VPS (5.253.233.219, Ubuntu 26.04, Contabo).

| Arquivo | Destino na VPS | Função |
|---|---|---|
| `openlead-firewall.sh` | `/usr/local/sbin/` | Bloqueia de fora as portas 8000, 6001, 6002 e 8080 (IPv4 e IPv6) |
| `openlead-firewall.service` | `/etc/systemd/system/` | Reaplica o firewall no boot e quando o Docker reinicia |
| `00-openlead-hardening.conf` | `/etc/ssh/sshd_config.d/` | SSH só por chave (senha desativada) |

Portas abertas: 22 (SSH por chave), 80 e 443 (Traefik/Coolify).
Painel: https://server.openlead.app (credenciais em `.env.coolify.enc`).

## Foto da VPS (`snapshot/`)

`snapshot/` é uma cópia, só para leitura, de como a VPS está agora. Para atualizar:

```bash
scripts/secrets.sh decrypt      # se os segredos ainda não estiverem abertos
scripts/vps-snapshot.sh         # lê a VPS e regrava snapshot/ (não muda nada na VPS)
git diff infra/vps/snapshot     # mostra o que mudou desde a última foto
```

O script também avisa se os arquivos acima, ou o `.env` do Coolify, estão diferentes do que temos no repo.

| Pasta | O que tem |
|---|---|
| `snapshot/system/` | SO, pacotes, serviços, portas, firewall, SSH, sysctl, cron, usuários, containers |
| `snapshot/coolify/` | docker-compose da instalação, **nomes** das variáveis do `.env`, e o que está cadastrado no painel (servidores, projetos, apps, bancos) |
| `snapshot/proxy/` | docker-compose do Traefik, rotas (`dynamic/`) e domínios com certificado |

Nunca entram na foto: valores do `.env`, `acme.json` (chaves dos certificados) e chaves SSH.
Os valores do `.env` do Coolify ficam em `.env.coolify-instance.enc`.

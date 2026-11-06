# VPS server.openlead.app

Cópia do que está instalado na VPS (5.253.233.219, Ubuntu 26.04, Contabo).

| Arquivo | Destino na VPS | Função |
|---|---|---|
| `openlead-firewall.sh` | `/usr/local/sbin/` | Bloqueia de fora as portas 8000, 6001, 6002 e 8080 (IPv4 e IPv6) |
| `openlead-firewall.service` | `/etc/systemd/system/` | Reaplica o firewall no boot e quando o Docker reinicia |
| `00-openlead-hardening.conf` | `/etc/ssh/sshd_config.d/` | SSH só por chave (senha desativada) |

Portas abertas: 22 (SSH por chave), 80 e 443 (Traefik/Coolify).
Painel: https://server.openlead.app (credenciais em `.env.coolify.enc`).

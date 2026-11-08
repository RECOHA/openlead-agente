#!/usr/bin/env bash
# Aplica numa VPS o padrão de segurança de infra/vps/ (pode rodar de novo: só muda o que falta).
#   scripts/vps-apply.sh vps-NN        ex.: vps-00, vps-01, vps-10
#
# O que faz lá:
#   1. SSH: 00-openlead-hardening.conf (só chave, sem X11, 3 tentativas), confere com `sshd -t` e recarrega.
#   2. Firewall do Docker: openlead-firewall.sh + .service (portas internas do Coolify fechadas de fora).
#   3. Docker: daemon.json (logs com limite, live-restore). Recarrega sem parar contêiner.
#   4. Proxy: security-headers.yaml em /data/coolify/proxy/dynamic/ (o compose do proxy é pela API do Coolify,
#      ver infra/vps/README.md).
#   5. fail2ban no SSH (openlead.local).
#   6. ufw: entra só 22, 80, 443 (tcp) e 443 (udp).
#      Trava: antes de ligar, agenda `ufw disable` para daqui a 5 min. Este script abre uma conexão SSH NOVA
#      depois; só se ela entrar a trava é cancelada. Se o SSH cair, o ufw se desliga sozinho.
#   7. Apaga o usuário `ubuntu` do cloud-init (regra: só root, por chave).
# Requer os segredos abertos: scripts/secrets.sh decrypt
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

T="${1:?uso: scripts/vps-apply.sh vps-NN}"
[[ "$T" =~ ^vps-[0-9]+$ ]] || { echo "uso: scripts/vps-apply.sh vps-NN" >&2; exit 1; }

FILES=(00-openlead-hardening.conf openlead-firewall.sh openlead-firewall.service daemon.json security-headers.yaml openlead.local)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ─── Parte que roda na VPS (vai dentro do tar, junto com os arquivos) ─────
cat > "$TMP/apply.sh" <<'REMOTE'
set -euo pipefail
D="$1"; trap 'rm -rf "$D"' EXIT
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l   # o apt só lista o que precisaria reiniciar; nunca reinicia o Docker sozinho
changed() { ! cmp -s "$1" "$2"; }

echo "== 1. SSH"
install -m 644 "$D/00-openlead-hardening.conf" /etc/ssh/sshd_config.d/
sshd -t
systemctl reload ssh
sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin|x11forwarding|maxauthtries) ' | sed 's/^/   /'

echo "== 2. Firewall do Docker"
install -m 755 "$D/openlead-firewall.sh" /usr/local/sbin/
install -m 644 "$D/openlead-firewall.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable openlead-firewall >/dev/null 2>&1
systemctl restart openlead-firewall
echo "   $(systemctl is-active openlead-firewall)"

echo "== 3. Docker"
if changed "$D/daemon.json" /etc/docker/daemon.json; then
  cp -a /etc/docker/daemon.json "/etc/docker/daemon.json.bak-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  install -m 644 "$D/daemon.json" /etc/docker/daemon.json
  systemctl reload docker
  sleep 2
fi
echo "   live-restore=$(docker info --format '{{.LiveRestoreEnabled}}')"

echo "== 4. Proxy (cabeçalhos de segurança)"
if [ -d /data/coolify/proxy/dynamic ]; then
  install -m 644 "$D/security-headers.yaml" /data/coolify/proxy/dynamic/
  echo "   ok"
else
  echo "   sem /data/coolify/proxy/dynamic (VPS sem proxy?)"
fi

echo "== 5. fail2ban"
dpkg -s fail2ban >/dev/null 2>&1 || { apt-get update -qq; apt-get install -y -qq fail2ban >/dev/null; }
install -m 644 "$D/openlead.local" /etc/fail2ban/jail.d/
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban
sleep 2
fail2ban-client status sshd | sed 's/^/   /' || echo "   fail2ban ainda subindo"

echo "== 6. ufw"
systemctl stop openlead-ufw-rollback.timer 2>/dev/null || true
systemctl reset-failed openlead-ufw-rollback.service openlead-ufw-rollback.timer 2>/dev/null || true
systemd-run --quiet --unit=openlead-ufw-rollback --on-active=300 /usr/sbin/ufw --force disable
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw default deny routed >/dev/null
for r in 22/tcp 80/tcp 443/tcp 443/udp; do ufw allow "$r" >/dev/null; done
ufw logging low >/dev/null
ufw --force enable >/dev/null
systemctl enable ufw >/dev/null 2>&1
ufw status verbose | sed 's/^/   /'
echo "   trava armada: ufw desliga sozinho em 5 min se ninguém cancelar"

echo "== 7. Usuário ubuntu"
if id ubuntu >/dev/null 2>&1; then
  pkill -u ubuntu 2>/dev/null || true
  userdel -r ubuntu 2>/dev/null || userdel ubuntu
  echo "   apagado"
else
  echo "   não existe"
fi
# A regra de sudo do cloud-init só sai se for do ubuntu (na VPS-01 ela é do root).
if [ -f /etc/sudoers.d/90-cloud-init-users ] && grep -q '^ubuntu ' /etc/sudoers.d/90-cloud-init-users \
   && ! grep -qvE '^(#|$|ubuntu )' /etc/sudoers.d/90-cloud-init-users; then
  rm -f /etc/sudoers.d/90-cloud-init-users
  echo "   sudoers do ubuntu apagado"
fi
REMOTE

tar -czf - -C infra/vps "${FILES[@]}" -C "$TMP" apply.sh |
  scripts/vps.sh "$T" 'D="$(mktemp -d)"; tar -xzf - -C "$D" && bash "$D/apply.sh" "$D"'

# Conexão nova: se ela entra, o SSH segue aberto com o ufw ligado, e a trava é cancelada.
echo "== Conferindo com uma conexão SSH nova"
if scripts/vps.sh "$T" 'systemctl stop openlead-ufw-rollback.timer && ufw status | head -1'; then
  echo "OK: SSH entra com o ufw ligado; trava cancelada."
else
  echo "ERRO: a conexão nova não entrou. O ufw se desliga sozinho em até 5 min." >&2
  exit 1
fi

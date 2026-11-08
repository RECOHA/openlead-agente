#!/usr/bin/env bash
# Tira uma "foto" da VPS e salva em infra/vps/ (só LEITURA: não muda nada lá).
#   scripts/vps-snapshot.sh          VPS-00 (Coolify)  -> infra/vps/snapshot/
#   scripts/vps-snapshot.sh vps-NN   VPS-NN (servidor) -> infra/vps/snapshot-vps-NN/  (ex.: vps-01, vps-10)
# Depois veja o que mudou com: git diff infra/vps
# Segredos NUNCA vêm em texto puro: dos .env só vêm os nomes das variáveis;
# acme.json (certificados) e chaves SSH não são copiados.
# Requer os segredos abertos: scripts/secrets.sh decrypt
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TARGET="${1:-vps-00}"
case "$TARGET" in
  vps-00) OUT=infra/vps/snapshot ;;
  vps-[0-9]*) OUT=infra/vps/snapshot-$TARGET ;;
  *) echo "uso: $0 [vps-00|vps-NN]" >&2; exit 1 ;;
esac
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ─── Parte que roda na VPS ─────────────────────────────────────────
# Monta tudo numa pasta temporária lá e devolve como .tar.gz pelo stdout.
scripts/vps.sh "$TARGET" 'bash -s' > "$TMP/snap.tgz" <<'REMOTE'
set -uo pipefail
S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
mkdir -p "$S/system" "$S/coolify" "$S/proxy/dynamic" "$S/deployed"
keys() { sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)=.*/\1=<segredo>/p' "$1"; }   # só nomes das variáveis
psql() { docker exec coolify-db psql -U coolify -d coolify -AF $'\t' --pset footer=off -c "$1" 2>&1; }

# Sistema
{ grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release; echo "kernel=$(uname -r)"
  echo "hostname=$(hostname)"; echo "cpus=$(nproc)"
  echo "mem_total=$(free -h | awk '/^Mem:/{print $2}')"; echo "swap_total=$(free -h | awk '/^Swap:/{print $2}')"
  echo "disk_root=$(df -h / | awk 'NR==2{print $2}')"; echo "timezone=$(timedatectl show -p Timezone --value)"
  echo "docker=$(docker version --format '{{.Server.Version}}')"; } > "$S/system/os.txt"
apt-mark showmanual | sort > "$S/system/packages-manual.txt"
systemctl list-unit-files --state=enabled --no-legend | awk '{print $1}' | sort > "$S/system/systemd-enabled.txt"
ss -H -tulpn | awk '{split($7,p,"\""); print $1, $5, p[2]}' | sort -u > "$S/system/listening-ports.txt"
{ echo "# iptables (IPv4)"; iptables -S; echo; echo "# ip6tables (IPv6)"; ip6tables -S; } > "$S/system/firewall.txt"
ufw status verbose > "$S/system/ufw.txt" 2>&1
{ echo "fail2ban: $(systemctl is-active fail2ban 2>&1)"; fail2ban-client status sshd 2>&1 | grep -E 'Journal|Total'; } > "$S/system/fail2ban.txt"
sshd -T 2>/dev/null | sort > "$S/system/sshd-effective.txt"
for f in /etc/ssh/sshd_config.d/*.conf; do echo "### $f"; cat "$f"; echo; done > "$S/system/sshd_config.d.txt"
for f in /etc/sysctl.d/*.conf; do echo "### $f"; grep -vE '^\s*(#|$)' "$f"; echo; done > "$S/system/sysctl.d.txt"
{ echo "# crontab root"; crontab -l 2>&1; echo; echo "# /etc/cron.d"; ls /etc/cron.d; } > "$S/system/cron.txt"
awk -F: '$7 !~ /(nologin|false|sync)$/ {print $1":"$3":"$6":"$7}' /etc/passwd > "$S/system/users-with-shell.txt"
for u in /root /home/*; do
  [ -f "$u/.ssh/authorized_keys" ] && { echo "### $u"; ssh-keygen -lf "$u/.ssh/authorized_keys"; }
done > "$S/system/authorized-keys-fingerprints.txt" 2>&1

# Docker
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.State}}' | sort > "$S/system/containers.txt"
docker network ls --format '{{.Name}}\t{{.Driver}}' | sort > "$S/system/docker-networks.txt"
docker volume ls --format '{{.Name}}' | sort > "$S/system/docker-volumes.txt"
cat /etc/docker/daemon.json > "$S/system/docker-daemon.json" 2>/dev/null || echo "(não existe)" > "$S/system/docker-daemon.json"

# Coolify (instalação): só na VPS onde o Coolify roda
if [ -d /data/coolify/source ]; then
cp /data/coolify/source/docker-compose.yml /data/coolify/source/docker-compose.prod.yml "$S/coolify/"
keys /data/coolify/source/.env            > "$S/coolify/env-keys.txt"
keys /data/coolify/source/.env.production > "$S/coolify/env.production-keys.txt"
# hash do .env (sem linhas em branco) para conferir com .env.coolify-instance local
sed -e '/^[[:space:]]*$/d' /data/coolify/source/.env | sha256sum | cut -d' ' -f1 > "$S/coolify/.env.sha256"

# Coolify (o que está cadastrado no painel: só nomes e domínios, nada de segredo)
{ echo "## servers";      psql 'select id, name, ip, "user", port from servers order by id'
  echo; echo "## projects";     psql 'select id, name from projects order by id'
  echo; echo "## environments"; psql 'select id, name, project_id from environments order by id'
  echo; echo "## applications"; psql 'select uuid, name, fqdn, git_repository, git_branch, build_pack, environment_id from applications order by id'
  echo; echo "## services";     psql 'select uuid, name, environment_id from services order by id'
  echo; echo "## databases";    for t in standalone_postgresqls standalone_redis standalone_mysqls standalone_mariadbs standalone_mongodbs standalone_keydbs standalone_dragonflies standalone_clickhouses; do
                                  psql "select '$t' as type, uuid, name, image, environment_id from $t order by id" | tail -n +2; done
  echo; echo "## scheduled_database_backups"; psql 'select id, frequency, enabled from scheduled_database_backups order by id'
} > "$S/coolify/resources.tsv"
fi

# Proxy (Traefik)
cp /data/coolify/proxy/docker-compose.yml "$S/proxy/"
cp /data/coolify/proxy/dynamic/* "$S/proxy/dynamic/" 2>/dev/null
# acme.json tem as chaves privadas dos certificados: só lemos os domínios.
python3 - > "$S/proxy/certificates.txt" 2>&1 <<'PY'
import json
import os
p = "/data/coolify/proxy/acme.json"
d = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
doms = sorted(" ".join([c["domain"]["main"], *c["domain"].get("sans", [])])
              for r in d.values() for c in (r.get("Certificates") or []))
print("\n".join(doms) or "(nenhum)")
PY

# Hash dos arquivos que nós instalamos (para comparar com infra/vps/)
sha256sum /usr/local/sbin/openlead-firewall.sh /etc/systemd/system/openlead-firewall.service \
  /etc/ssh/sshd_config.d/00-openlead-hardening.conf /etc/fail2ban/jail.d/openlead.local \
  /etc/docker/daemon.json /data/coolify/proxy/dynamic/security-headers.yaml \
  /data/coolify/source/docker-compose.custom.yml > "$S/deployed/sha256.txt" 2>/dev/null

find "$S" -mindepth 1 -type d -empty -delete
tar -C "$S" -czf - .
REMOTE

# ─── Parte local ───────────────────────────────────────────────────
mkdir -p "$TMP/x"
tar -C "$TMP/x" -xzf "$TMP/snap.tgz"

# 1) Arquivos instalados batem com infra/vps/?
echo "== Arquivos instalados x infra/vps/"
while read -r hash path; do
  local_file="infra/vps/$(basename "$path")"
  if [[ ! -f "$local_file" ]]; then echo "  ?? $path (sem cópia em infra/vps/)"
  elif [[ "$(sha256sum < "$local_file" | cut -d' ' -f1)" == "$hash" ]]; then echo "  OK $path"
  else echo "  DIFERENTE $path  <- VPS e repo não batem"; fi
done < "$TMP/x/deployed/sha256.txt"

# 2) .env do Coolify bate com .env.coolify-instance?
if [[ -f "$TMP/x/coolify/.env.sha256" ]]; then
echo "== .env do Coolify x .env.coolify-instance"
if [[ -f .env.coolify-instance ]]; then
  if [[ "$(tr -d '\r' < .env.coolify-instance | sed -e '/^[[:space:]]*$/d' | sha256sum | cut -d' ' -f1)" == "$(cat "$TMP/x/coolify/.env.sha256")" ]]
  then echo "  OK valores iguais"
  else echo "  DIFERENTE  <- copie o .env da VPS para .env.coolify-instance e rode scripts/secrets.sh encrypt"; fi
else echo "  ?? .env.coolify-instance não está aberto (rode scripts/secrets.sh decrypt)"; fi
fi
rm -rf "$TMP/x/deployed" "$TMP/x/coolify/.env.sha256"

# 3) Troca a foto antiga pela nova
rm -rf "$OUT"
mkdir -p "$OUT"
cp -r "$TMP/x/." "$OUT/"
echo "== Foto salva em $OUT/"
git status --short -- "$OUT" | sed 's/^/  /' || true

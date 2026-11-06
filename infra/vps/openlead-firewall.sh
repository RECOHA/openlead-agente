#!/bin/sh
# Gerenciado pelo openlead-agente.
# Bloqueia acesso externo (eth0) às portas internas do Coolify.
# O painel fica acessível só via https://server.openlead.app (portas 80/443).
#   8000 painel HTTP | 6001 realtime | 6002 terminal | 8080 dashboard do Traefik
# Docker ignora o INPUT para portas publicadas (usa FORWARD/DOCKER-USER), por isso as duas regras.
PORTS="8000,6001,6002,8080"
IFACE="eth0"
for ipt in iptables ip6tables; do
  $ipt -N DOCKER-USER 2>/dev/null || true
  for p in $(echo $PORTS | tr , " "); do
    $ipt -C DOCKER-USER -i $IFACE -p tcp -m conntrack --ctorigdstport $p --ctdir ORIGINAL -j DROP 2>/dev/null \
      || $ipt -I DOCKER-USER -i $IFACE -p tcp -m conntrack --ctorigdstport $p --ctdir ORIGINAL -j DROP
  done
  $ipt -C INPUT -i $IFACE -p tcp -m multiport --dports $PORTS -j DROP 2>/dev/null \
    || $ipt -I INPUT -i $IFACE -p tcp -m multiport --dports $PORTS -j DROP
done

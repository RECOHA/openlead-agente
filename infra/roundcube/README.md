# Roundcube na VPS-00

Webmail das contas da DreamHost em https://email.openlead.app. Os e-mails continuam na DreamHost
(IMAP `imap.dreamhost.com:993`, SMTP `smtp.dreamhost.com:587`); aqui ficam só preferências, contatos e
assinaturas. Cada conta entra com o próprio login, sem senha extra na frente.

## Arquivos

| Arquivo | O que é |
|---|---|
| `roundcube.coolify.yml` | O compose do serviço (imagem, rotas do Traefik, `zz-openlead.php`) |
| `../../.env.roundcube.enc` | `ROUNDCUBEMAIL_DES_KEY`, também gravada no Coolify como variável do serviço |

## No Coolify (VPS-00)

| O quê | UUID |
|---|---|
| Projeto `Pessoal` | `88x1fnddyu2k6iwunva8p1c4` (ambiente `production`) |
| Servidor VPS-00 | `87pglkbb8lcv6qivibkcyoof` |
| Serviço `roundcube` | `0jpqdwhvfa5vdheffsdxlwn6` (contêiner `roundcube-0jpqdwhvfa5vdheffsdxlwn6`) |

O Coolify ligou sozinho o `coolify-proxy` à rede do serviço (`0jpqdwhvfa5vdheffsdxlwn6`). O contrário
nunca: o Roundcube não entra na rede `coolify`, e `connect_to_docker_network` fica desligado.

## Atualizar a tag

A tag é fixa, então cada release de segurança do Roundcube pede esta troca à mão:

1. Trocar a tag em `roundcube.coolify.yml`.
2. `PATCH /api/v1/services/<uuid>` com `{"docker_compose_raw": "<yml em base64>"}`.
3. `POST /api/v1/services/<uuid>/restart?latest=true`.
4. Refazer as provas abaixo. Nessa troca o código novo vem da imagem, porque `/var/www/html` não é volume.

## Provas depois de cada deploy

```bash
curl -sI https://email.openlead.app/    # 200 e strict-transport-security
scripts/vps.sh vps-00 'docker inspect roundcube-0jpqdwhvfa5vdheffsdxlwn6 --format "{{json .NetworkSettings.Networks}} {{json .Mounts}}"'
# sem a rede coolify e sem docker.sock
scripts/vps.sh vps-00 'for a in coolify:8080 coolify-db:5432 coolify-redis:6379; do docker exec roundcube-0jpqdwhvfa5vdheffsdxlwn6 php -r "var_dump(@fsockopen(explode(\":\",\"$a\")[0],(int)explode(\":\",\"$a\")[1],\$e,\$s,3));"; done'
# bool(false) três vezes
```

## O que não tem backup

O volume `0jpqdwhvfa5vdheffsdxlwn6_roundcube-db` (SQLite) fica sem backup, de propósito: perder só custa
refazer contatos e assinaturas. Os e-mails estão na DreamHost.

A `des_key` precisa continuar a mesma: trocar derruba as sessões abertas.

## Problemas

| Sintoma | O que é |
|---|---|
| Login falha em todas as contas ao mesmo tempo | A DreamHost pode ter bloqueado o IP da VPS-00 (`5.253.233.219`). O `login_rate_limit` (3 falhas por minuto) é a única barreira contra robôs |
| 504 no endereço | O Traefik não alcança o contêiner: `docker network connect 0jpqdwhvfa5vdheffsdxlwn6 coolify-proxy`. Nunca o inverso |

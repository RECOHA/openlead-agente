# Roundcube na VPS-00

Webmail das contas da DreamHost em https://email.openlead.app. Os e-mails continuam na DreamHost
(IMAP `imap.dreamhost.com:993`, SMTP `smtp.dreamhost.com:587`); aqui ficam só preferências, contatos e
assinaturas. Cada conta entra com o próprio login, sem senha extra na frente.

## Arquivos

| Arquivo | O que é |
|---|---|
| `roundcube.coolify.yml` | O compose do serviço (imagem, rotas do Traefik, `zz-openlead.php`) |
| `skins/openlead/` | O skin próprio, tema padrão (ver "Temas") |
| `../../.env.roundcube.enc` | `ROUNDCUBEMAIL_DES_KEY`, também gravada no Coolify como variável do serviço |

## No Coolify (VPS-00)

| O quê | UUID |
|---|---|
| Projeto `RoundCube` | `88x1fnddyu2k6iwunva8p1c4` (ambiente `production`) |
| Servidor VPS-00 | `87pglkbb8lcv6qivibkcyoof` |
| Serviço `roundcube` | `0jpqdwhvfa5vdheffsdxlwn6` (contêiner `roundcube-0jpqdwhvfa5vdheffsdxlwn6`) |

O Coolify ligou sozinho o `coolify-proxy` à rede do serviço (`0jpqdwhvfa5vdheffsdxlwn6`). O contrário
nunca: o Roundcube não entra na rede `coolify`, e `connect_to_docker_network` fica desligado.

## Atualizar a tag

A tag é fixa, então cada release de segurança do Roundcube pede esta troca à mão. Para saber das
releases, acompanhe https://github.com/roundcube/roundcubemail/releases (Watch > Custom > Releases).

1. Copiar o banco (a imagem nova pode migrar o SQLite, que não tem backup):
   `docker exec roundcube-0jpqdwhvfa5vdheffsdxlwn6 cp -p /var/roundcube/db/sqlite.db /var/roundcube/db/sqlite.db.antes-da-troca`
2. Trocar a tag em `roundcube.coolify.yml`.
3. `PATCH /api/v1/services/<uuid>` com `{"docker_compose_raw": "<yml em base64>"}`.
4. `POST /api/v1/services/<uuid>/restart?latest=true`.
5. Refazer as provas abaixo. Nessa troca o código novo vem da imagem, porque `/var/www/html` não é volume.
   Deu certo: apagar `sqlite.db.antes-da-troca` (ela é tão sensível quanto o banco).

Deu errado: volte a tag antiga no arquivo, repita os passos 3 e 4, e só com o contêiner da tag antiga no ar
restaure o banco:

```bash
scripts/vps.sh vps-00 'C=roundcube-0jpqdwhvfa5vdheffsdxlwn6; docker exec $C cp -p /var/roundcube/db/sqlite.db.antes-da-troca /var/roundcube/db/sqlite.db && docker restart $C'
```

## Mudar a configuração

O Coolify só grava o `content:` de um arquivo na primeira vez. Depois disso, o `PATCH` do compose não regrava o
arquivo, e a API recusa editar (`422`, `read_only_fields: content`). Por isso, config nova vai em um arquivo novo
em `/var/roundcube/config/` (como `zz-openlead-idioma.php`), e o deploy segue os passos 3 e 4 acima. Confira
depois se a linha chegou ao contêiner.

## Temas

O padrão é o `openlead` (`ROUNDCUBEMAIL_SKIN`), o skin próprio, filho do `elastic`. Os extras estão em
`ROUNDCUBEMAIL_COMPOSER_PLUGINS`, com versão fixa: `roundcube/larry` e `johndoh/stretchedelastic`. Cada conta
escolhe o seu em Configurações > Preferências > Interface do usuário; quem já escolheu um mantém o dele.

### Skin `openlead`

É feito no clone local do Roundcube (`roundcubemail/skins/openlead`, com `make css-openlead`) e copiado para
`skins/openlead/` aqui. Na VPS-00 fica em `/srv/roundcube/skins/openlead` (dono `root`, só leitura para o
resto), montado só leitura em `/var/www/html/skins/openlead`. Vai com o CSS já compilado (`*.min.css`): o
servidor não compila nada. Ao trocar a tag do Roundcube, confira se `templates/login.html` e
`templates/includes/menu.html` ainda batem com os do `elastic` da versão nova.

Para mandar uma versão nova:

```bash
cp -r ../roundcubemail/skins/openlead infra/roundcube/skins/    # do clone local para cá (apague antes o que saiu)
tar -C infra/roundcube/skins -cf - openlead | scripts/vps.sh 'set -e; rm -rf /srv/roundcube/skins/openlead.new; mkdir /srv/roundcube/skins/openlead.new; tar --no-same-owner --no-same-permissions -xf - -C /srv/roundcube/skins/openlead.new --strip-components=1; chmod -R u=rwX,go=rX /srv/roundcube/skins/openlead.new; rm -rf /srv/roundcube/skins/openlead.old; mv /srv/roundcube/skins/openlead /srv/roundcube/skins/openlead.old; mv /srv/roundcube/skins/openlead.new /srv/roundcube/skins/openlead; docker restart roundcube-0jpqdwhvfa5vdheffsdxlwn6'
```

O `docker restart` é obrigatório: a montagem segura a pasta antiga até o contêiner reiniciar. Deu errado: troque
`openlead.old` de volta e reinicie. A pasta do host não passa pelo Coolify, então o `PATCH` não é preciso.
Os arquivos dos temas ficam em `/static.php/skins/...`; o caminho `/skins/...` responde 404 até no `elastic`.

A imagem baixa esses pacotes do Packagist toda vez que o contêiner inicia. Para tirar um tema, apague o pacote da
variável e siga os passos 3 e 4 de "Atualizar a tag".

## Provas depois de cada deploy

```bash
curl -sI https://email.openlead.app/    # 200, strict-transport-security e Set-Cookie com `secure`
curl -sI http://email.openlead.app/     # 3xx (hoje 307) com Location: https://email.openlead.app/
curl -s -o /dev/null -w '%{http_code}\n' https://email.openlead.app/installer/    # 404: o instalador não abre
curl -s https://email.openlead.app/ | grep -c 'name="_host"'    # 0: login sem campo de servidor

scripts/vps.sh vps-00 'docker inspect roundcube-0jpqdwhvfa5vdheffsdxlwn6 --format "{{json .NetworkSettings.Networks}} {{json .Mounts}}"'
# sem a rede coolify, sem docker.sock e com um volume em /var/roundcube/db
scripts/vps.sh vps-00 'docker exec roundcube-0jpqdwhvfa5vdheffsdxlwn6 ls -l /var/roundcube/db/sqlite.db'
# o arquivo existe
```

Isolamento. Nome de contêiner não resolve entre redes Docker, então a prova por nome sozinha não diz nada:
vale a por IP, junto com o controle positivo, que mostra que a sonda consegue abrir conexão.

```bash
scripts/vps.sh vps-00 'C=roundcube-0jpqdwhvfa5vdheffsdxlwn6; for a in coolify:8080 coolify-db:5432 coolify-redis:6379; do ip=$(docker inspect "${a%:*}" --format "{{(index .NetworkSettings.Networks \"coolify\").IPAddress}}"); echo -n "$a $ip "; docker exec $C php -r "var_dump(is_resource(@fsockopen(\"$ip\",${a#*:},\$e,\$s,3)));"; done'
# bool(false) três vezes
scripts/vps.sh vps-00 'C=roundcube-0jpqdwhvfa5vdheffsdxlwn6; for a in imap.dreamhost.com:993 smtp.dreamhost.com:587; do echo -n "$a "; docker exec $C php -r "var_dump(is_resource(@fsockopen(\"${a%:*}\",${a#*:},\$e,\$s,8)));"; done'
# bool(true) duas vezes
```

## O que não tem backup

O volume `0jpqdwhvfa5vdheffsdxlwn6_roundcube-db` (SQLite) fica sem backup, de propósito: perder só custa
refazer contatos e assinaturas. Os e-mails estão na DreamHost. Mesmo assim o volume é sensível: o mesmo
SQLite guarda as sessões abertas, com a senha IMAP cifrada pela `des_key`.

A `des_key` precisa continuar a mesma: trocar derruba as sessões abertas.

## Problemas

| Sintoma | O que é |
|---|---|
| Login falha em todas as contas ao mesmo tempo | A DreamHost pode ter bloqueado o IP da VPS-00 (`5.253.233.219`). Veja "Bloqueio da DreamHost" abaixo |
| 504 no endereço | O Traefik não alcança o contêiner: `docker network connect 0jpqdwhvfa5vdheffsdxlwn6 coolify-proxy`. Nunca o inverso |

### Bloqueio da DreamHost

O `login_rate_limit` (3 falhas por minuto) conta por conta e só existe para quem já tem linha na tabela
`users`, ou seja, já entrou aqui alguma vez. Endereço que nunca entrou vai direto à DreamHost, sem limite
nenhum: robôs testando endereços novos podem fazer a DreamHost bloquear o IP.

Para confirmar:

1. Rode o controle positivo de "Provas depois de cada deploy": `bool(false)` em `imap.dreamhost.com:993` ou
   `smtp.dreamhost.com:587` indica bloqueio de rede.
2. Veja o log de erros do Roundcube, que vai para a saída do contêiner:
   `scripts/vps.sh vps-00 'docker logs --since 1h roundcube-0jpqdwhvfa5vdheffsdxlwn6 2>&1 | grep -iE "imap|smtp|login failed"'`

Para resolver: abra um chamado no suporte da DreamHost informando o IP `5.253.233.219` e peça a liberação.

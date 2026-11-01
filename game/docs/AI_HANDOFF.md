# Manual de continuidade para IA — Andre 3D

Este documento explica como continuar o projeto sem depender do histórico da conversa. Leia também o manual do servidor no repositório `brechoda/andre3d-multiplayer-server`.

## Identidade dos repositórios

- Jogo Godot: `https://github.com/brechoda/Andre3D-GTA3`
- Servidor multiplayer e distribuição: `https://github.com/brechoda/andre3d-multiplayer-server`
- Branch de produção dos dois repositórios: `main`
- Build multiplayer esperado: `andre3d-mp-v4`
- Pacote Android principal a partir da 2.0.6: `com.manus.andre3d.next`
- Pacote legado 2.0.5: `com.manus.andre3d`; a chave antiga foi perdida, então não pode ser atualizado no mesmo pacote.
- Versão atualmente preparada: `2.0.6`
- Código Android atualmente preparado: `8`
- Release principal: `https://github.com/brechoda/Andre3D-GTA3/releases/tag/v2.0.6`

## Objetivo do projeto

Andre 3D é um jogo Godot em terceira pessoa para Android, com modo offline e modo online. O menu inicial permite escolher offline/online e o personagem André, Gorece ou DG. O multiplayer usa um servidor WebSocket separado. O servidor é a autoridade para presença, estados retransmitidos, pulo, posse de veículos e algumas restrições de personagem.

Não substituir o projeto por um template novo. O projeto já tem mapa, veículos, personagens, controles, cenas, testes e histórico de conversão; alterações devem ser incrementais.

## Arquitetura importante

- `project.godot`: versão, cena inicial e autoloads. A cena inicial é `res://scenes/session_menu.tscn`.
- `scenes/session_menu.tscn` e `scripts/session_menu.gd`: menu inicial, escolha de modo/personagem, espera da checagem remota, bloqueio do online quando o APK é antigo e opção de baixar APKs automaticamente.
- `scenes/third_person.tscn` e `scripts/third_person.gd`: gameplay principal em terceira pessoa.
- `scripts/net/multiplayer_client.gd`: cliente WebSocket. Ao entrar, envia `build`, `app_version`, sala, nome e personagem. Não remova `app_version`, pois o servidor bloqueia versões antigas.
- `autoload/remote_updater.gd`: consulta o manifesto, valida arquivos por tamanho/SHA-256, grava conteúdo em `user://updates`, verifica a versão do APK, baixa o APK novo e abre o instalador Android através do botão do menu.
- `autoload/tuning_store.gd`: lê `config/tuning.json` remoto validado e usa o arquivo local como fallback.
- `config/updates.json`: endpoint do manifesto e flag de checagem no início.
- `config/multiplayer.json`: endpoint WebSocket/HTTP do servidor.
- `scripts/manus/preview/tuning_adapter.gd`: ponte de ajustes usada pelo template; preservar ao editar tuning.
- `server/`: cópia histórica/auxiliar do servidor dentro do projeto do jogo. O deploy de produção é feito pelo repositório separado do servidor.
- `tests/multiplayer_two_clients.gd`: teste Godot de duas cenas contra servidor local.
- `test/` e `tests/`: testes de scripts, veículos, personagens, mapa e multiplayer.

## Atualização de conteúdo sem trocar APK

O APK consulta:

`https://andre3d-multiplayer-server.onrender.com/updates/manifest.json`

O manifesto atual tem:

- `files`: arquivos de conteúdo, como `config/tuning.json`;
- `min_app_version`: versão mínima do aplicativo que pode interpretar o manifesto;
- `min_online_version`: versão mínima permitida para online;
- `client`: metadados do APK mais novo, incluindo URL, tamanho e SHA-256.

Arquivos `kind: "file"` são baixados para o cache do usuário e usados pelo código que os solicita. Um APK já instalado não consegue substituir código GDScript nativo. Alterações de código, cenas empacotadas ou lógica necessitam de uma nova versão do APK. Conteúdo externo/PCK só deve ser usado se o carregamento correspondente estiver implementado e validado.

Se a rede falhar, o jogo continua usando o cache local/conteúdo instalado. Nunca faça o menu travar indefinidamente por causa de uma atualização remota.

## Atualização do próprio APK

A opção `BAIXAR ATUALIZAÇÕES DO APK AUTOMATICAMENTE` é salva em `user://andre3d_update_preferences.json`. Quando o manifesto informa um `client.version` maior que `application/config/version`, o atualizador baixa o APK para `user://updates/apk/` e valida tamanho/SHA-256. O botão `INSTALAR APK BAIXADO` abre o instalador Android; a confirmação do usuário é normal e não deve ser contornada.

Para forçar atualização online, o cliente verifica `min_online_version` e o servidor também valida `app_version` no evento `join`. Portanto, não basta alterar somente a mensagem do menu: cliente, servidor e manifesto precisam permanecer compatíveis.

## Como gerar uma nova versão Android

1. Alterar `config/version` em `project.godot`.
2. Alterar `version/code`, `version/name` e `export_path` no preset Android em `export_presets.cfg`.
3. Usar um código Android maior que o anterior. O Android não aceita instalar uma versão com código menor/igual sobre a anterior.
4. Validar o projeto:

```bash
cd /home/ubuntu/repo-review/game
git diff --check
godot --headless --path . --editor --quit --check-only
```

5. Exportar com o SDK configurado. Em outro computador, ajuste os caminhos do Java/SDK conforme o ambiente:

```bash
export HOME=/home/ubuntu
export ANDROID_HOME=/home/ubuntu/android-sdk
export ANDROID_SDK_ROOT=/home/ubuntu/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
godot --headless --path . --export-release "Android" dist/Andre3D-X.Y.Z.apk
```

6. Testar `npm test` no servidor quando o protocolo for alterado e testar o APK em um aparelho Android.
7. Fazer commit/push do código do jogo.
8. Criar um GitHub Release com o APK:

```bash
gh release create vX.Y.Z dist/Andre3D-X.Y.Z.apk \
  --repo brechoda/Andre3D-GTA3 \
  --title "Andre 3D X.Y.Z" \
  --notes "Resumo das alterações"
```

Para substituir um asset já publicado, usar `gh release upload ... --clobber`, mas depois recalcular o hash.

9. Atualizar `updates/manifest.json` no repositório do servidor com a URL do release, tamanho em bytes e SHA-256 do APK. Se a versão for obrigatória para online, atualizar `min_online_version` e o `MIN_CLIENT_VERSION` do servidor.
10. Fazer commit/push do servidor e confirmar o manifesto público e `/health`.

## Regras de versionamento e compatibilidade

- Toda versão do APK deve aumentar `config/version` e o `version/code` Android.
- O manifesto deve apontar para o asset final, não para um arquivo local ou para um commit.
- O SHA-256 do manifesto deve ser calculado sobre exatamente o APK publicado no release.
- Mudanças em mensagens WebSocket exigem alteração coordenada no cliente e no servidor.
- Mantenha `build: "andre3d-mp-v4"` até haver uma migração de protocolo planejada.
- O servidor reconhece `andre`, `gorece` e `dg`; o DG pode usar as motos, mas não a Hilux.
- A assinatura principal usa uma chave de release permanente fora do repositório; preservar cópias seguras. O preset usa `/home/ubuntu/.local/share/godot/keystores/andre3d-main.jks`, alias `key1` e a variável de ambiente `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`; nunca commitar a senha ou a keystore.

## Testes e higiene do repositório

- Servidor: `cd server && npm ci && npm test`.
- Sintaxe/recursos Godot: `godot --headless --path . --editor --quit --check-only`.
- Não adicionar arquivos `.import` gerados automaticamente em massa. Depois de abrir/importar o projeto, remova `.import` não versionados; restaure `.import` que já eram versionados.
- Não adicionar APKs de build ao Git comum se o objetivo for apenas distribuição; use GitHub Releases. O arquivo em `dist/` pode ser ignorado conforme o `.gitignore`.
- Não apagar assets ou arquivos de proveniência para “limpar” o projeto.
- Ao alterar o mapa, veículos ou controles, testar também o carregamento e o modo touch Android.

## Estado conhecido entregue

- Código do jogo com atualizador remoto e gate de versão: commit `aa4ae5f`.
- Servidor com gate online, manifesto e hash do APK: commit `64f9239`.
- Release Android principal: `v2.0.6` (package `com.manus.andre3d.next`, código `8`).
- Manifesto atual público: `https://andre3d-multiplayer-server.onrender.com/updates/manifest.json`.
- O servidor público deve responder `{"ok":true,"build":"andre3d-mp-v4"}` em `/health`.

Antes de começar uma alteração, leia este arquivo, `docs/game-multiplayer.md`, `autoload/remote_updater.gd`, `scripts/net/multiplayer_client.gd` e o README do servidor. Depois de alterar, valide, atualize a documentação se o fluxo mudar e faça push somente dos arquivos intencionais.

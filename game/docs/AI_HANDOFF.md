# Manual de continuidade para IA — Andre 3D

Este documento explica como continuar o projeto sem depender do histórico da conversa. Leia também o manual do servidor no repositório `brechoda/andre3d-multiplayer-server`.

## Identidade dos repositórios

- Jogo Godot: `https://github.com/brechoda/Andre3D-game`
- Servidor multiplayer e distribuição: `https://github.com/brechoda/andre3d-multiplayer-server`
- Branch de produção dos dois repositórios: `main`
- Build multiplayer esperado: `andre3d-mp-v4`
- Pacote Android principal a partir da 2.0.6: `com.manus.andre3d.next`
- Pacote legado 2.0.5: `com.manus.andre3d`; a chave antiga foi perdida, então não pode ser atualizado no mesmo pacote.
- A fonte atual em `main` é `3.0.6`, variante Andre 3D Pistola (`com.manus.andre3d.pistol`, version code `7`).
- O `config/updates.json` dessa variante consulta `/updates/pistol/manifest.json`, ativo como `2026.11.09.4`; ele serve o cliente `3.0.5` por CDN (131.086.654 bytes; SHA-256 `49f2b8df27c151c57b7516fc9348ec2882d0c1475c6dd7c6cf03102a6a167558`). O tamanho e o hash foram conferidos na auditoria de 10 de novembro de 2026. Esse APK não tem GitHub Release `apk-v3.0.5`.
- O repositório do jogo tem também a release [`pistol-v3.0.0`](https://github.com/brechoda/Andre3D-game/releases/tag/pistol-v3.0.0), mas seu asset é `Andre3D-3.0.0-debug.apk`, baseado no código antigo que ainda mostrava Level 2. Como o manifesto anuncia 3.0.5, o updater da 3.0.0 bloqueia `_start_game()` até a atualização ser instalada; orientar usuários a completar o update antes de jogar.
- O endpoint principal `/updates/manifest.json` permanece como distribuição anterior: cliente `2.2.13`, código `45`, release `https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/apk-v2.2.13`.
- O workflow `Build Android APK` cria artefatos debug com chave temporária; o run `42758706238` do fonte `3.0.6` passou e gerou `Andre3D-3.0.6-debug`, não uma release de produção. Qualquer nova publicação exige uma estratégia de assinatura segura; consulte o alerta de segurança abaixo.
- SHA-256 do APK público 2.2.13: `8805400706d04e6a02a9375ef254c2ed6b62e0645ae8d48ee16306668c737da2`.

## Objetivo do projeto

Andre 3D é um jogo Godot em terceira pessoa para Android, com modo offline e modo online. O menu inicial permite escolher offline/online e o personagem André, Gorece ou DG. O multiplayer usa um servidor WebSocket separado. O servidor é a autoridade para presença, estados retransmitidos, pulo, posse de veículos e algumas restrições de personagem.

Não substituir o projeto por um template novo. O projeto já tem mapa, veículos, personagens, controles, cenas, testes e histórico de conversão; alterações devem ser incrementais.

## Arquitetura importante

- `project.godot`: versão, cena inicial e autoloads. A cena inicial é `res://scenes/session_menu.tscn`.
- `scenes/session_menu.tscn` e `scripts/session_menu.gd`: menu inicial, escolha de modo/personagem, espera da checagem remota e bloqueio de entrada quando há atualização obrigatória do APK. No Android, solicita apenas `POST_NOTIFICATIONS` ao iniciar, depois da checagem e se ainda não estiver concedida; não bloqueia o jogo nem solicita o microfone no menu.
- `scenes/third_person.tscn` e `scripts/third_person.gd`: gameplay principal em terceira pessoa; mantém a tela de carregamento até o streamer confirmar geometria visual e colisão na área inicial, e por mais cinco segundos. O `WorldEnvironment` usa `PanoramaSkyMaterial` com o panorama de nuvens CODA. A orientação do modelo é aplicada em coordenadas globais; sprint começa na faixa externa do analógico com histerese, e o botão `CORRER` alterna sprint contínuo até novo toque. A HUD também tem `PUXAR VEÍCULO`, que abre a lista dos veículos da cena e traz o escolhido para cerca de 4,8 m à frente do personagem. Se o personagem cair no vazio, o streamer o recupera no último ponto seguro ou no spawn da região.
- `scripts/gta3_map_streamer.gd`: a versão atual suporta somente `center`, mantém apenas os tiles dessa região e não usa proximidade para habilitar tiles de outra região. Uma sessão antiga com região não suportada volta ao Centro. Agora seleciona tiles pela distância às bordas reais, processa colisões antes dos visuais e cria uma barreira física invisível na região ativa.
- `scripts/map_boundary_mountains.gd`: cria quatro paredes de colisão invisíveis ao redor da região ativa, evitando que o personagem saia da área jogável sem renderizar montanhas.
- `scripts/net/multiplayer_client.gd`: cliente WebSocket. Ao entrar, envia `build`, `app_version`, sala, nome e personagem. Não remova `app_version`, pois o servidor bloqueia versões antigas. No evento `vehicle_pull`, espera a confirmação do servidor e aplica a posição/rotação do broadcast `vehicle_pulled` em todos os clientes.
- `autoload/voice_chat.gd`: mantém o recebimento de vozes remoto e inicia a captura do microfone somente quando o botão `MICROFONE` na HUD é ligado; tocar novamente para o desligar interrompe a captura sem mutar outros jogadores.
- `autoload/remote_updater.gd`: consulta o manifesto, valida arquivos por tamanho/SHA-256, grava conteúdo em `user://updates`, baixa o APK obrigatório pelo fluxo do menu e mantém os PCKs regionais em cache.
- `autoload/external_content.gd`: baixa/monta apenas a região selecionada antes de iniciar o gameplay; o Centro não é embutido no APK. Depois de montar uma região, não aceita carregar outra até o jogo ser reaberto.
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

Se a rede falhar ao baixar conteúdo normal, o jogo continua usando o cache local/conteúdo instalado. Se o manifesto já identificou uma versão do APK mais nova e obrigatória, mantenha o gameplay bloqueado até validar, instalar e reabrir o app atualizado; ofereça uma nova tentativa de download, sem ignorar o requisito.

## Atualização do próprio APK

Quando o manifesto informa um `client.version` maior que `application/config/version`, o jogo bloqueia a entrada no gameplay e baixa o APK automaticamente para `user://updates/apk/`, validando tamanho e SHA-256. Depois do download, `INSTALAR ATUALIZAÇÃO` abre o instalador Android; a confirmação do usuário é obrigatória e não deve ser contornada. O jogador precisa reabrir o app atualizado para continuar. Se o download falhar, o jogo permanece bloqueado e oferece nova tentativa. O jogo desativa o serviço Android legado para evitar uma segunda cópia do APK sem validação.

Para forçar atualização online, o cliente verifica `min_online_version` e o servidor também valida `app_version` no evento `join`. Portanto, não basta alterar somente a mensagem do menu: cliente, servidor e manifesto precisam permanecer compatíveis.

## HUD e menu configuráveis remotamente

O autoload `RemoteUIConfig` lê primeiro `config/remote_ui.json` embarcado no APK e, após o `RemoteUpdater` verificar o manifesto, aplica `config/remote_ui.json` do cache remoto. O arquivo usa `schema_version: 1` e IDs de elementos registrados pelo código do APK. São aceitos apenas ajustes JSON limitados — visibilidade de elementos autorizados, rótulos estáticos, itens já existentes de seletores, cores, tamanho de fonte, escala, posição e tamanho. Caminhos de nós, métodos e scripts não são aceitos. O botão de entrada e a ação de atualização obrigatória não podem ser ocultados pela configuração.

Para mudar a interface sem republicar o APK, edite `updates/files/config/remote_ui.json` no repositório `andre3d-multiplayer-server`, atualize `path`, `url`, `size` e `sha256` do arquivo em `updates/manifest.json`, aumente `version`, faça commit/push e aguarde o deploy. O APK aplica a nova versão na próxima inicialização depois da validação de tamanho/hash. Mudanças de comportamento, novos elementos ou novos IDs ainda exigem uma versão do APK.

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
gh release create apk-vX.Y.Z dist/Andre3D-X.Y.Z.apk \
  --repo brechoda/andre3d-multiplayer-server \
  --title "Andre3D X.Y.Z" \
  --notes "Resumo das alterações"
```

Para substituir um asset já publicado, usar `gh release upload ... --clobber`, mas depois recalcular o hash.

9. Atualizar `updates/manifest.json` no repositório do servidor com a URL do release, tamanho em bytes e SHA-256 do APK. Se a versão mínima aceita pelo multiplayer também precisar mudar, atualizar `min_online_version` e o `MIN_CLIENT_VERSION` do servidor.
10. Fazer commit/push do servidor e confirmar o manifesto público e `/health`.

## Regras de versionamento e compatibilidade

- Toda versão do APK deve aumentar `config/version` e o `version/code` Android.
- O manifesto deve apontar para o asset final, não para um arquivo local ou para um commit.
- O SHA-256 do manifesto deve ser calculado sobre exatamente o APK publicado no release.
- Mudanças em mensagens WebSocket exigem alteração coordenada no cliente e no servidor.
- Mantenha `build: "andre3d-mp-v4"` até haver uma migração de protocolo planejada.
- O servidor reconhece `andre`, `gorece` e `dg`; o DG pode usar as motos, mas não a Hilux.
- Nunca commitar a keystore, senha ou credenciais de assinatura. A keystore principal foi exposta no histórico público do repositório de distribuição (commit `f8f69b8`); o arquivo foi removido do `main` no commit `e9ae5b7`, mas permanece acessível em commits antigos. A 2.2.13 foi assinada com essa chave. Trate-a como comprometida e planeje uma migração segura antes de futuros releases.

## Testes e higiene do repositório

- Servidor: `cd server && npm ci && npm test`.
- Sintaxe/recursos Godot: `godot --headless --path . --editor --quit --check-only`.
- Não adicionar arquivos `.import` gerados automaticamente em massa. Depois de abrir/importar o projeto, remova `.import` não versionados; restaure `.import` que já eram versionados.
- Não adicionar APKs de build ao Git comum se o objetivo for apenas distribuição; use GitHub Releases. O arquivo em `dist/` pode ser ignorado conforme o `.gitignore`.
- Não apagar assets ou arquivos de proveniência para “limpar” o projeto.
- Ao alterar o mapa, veículos ou controles, testar também o carregamento e o modo touch Android.

## Estado conhecido entregue

- A fonte `main` está na versão `3.0.6` da variante Pistola; o último workflow antes da auditoria concluiu com sucesso e o artefato gerado é debug. O atualizador da variante anuncia 3.0.5 por CDN; o APK foi baixado e tamanho/hash conferidos. O endpoint principal legado continua no cliente 2.2.13.
- O cliente atual e ambos os manifests servidos pelo Render oferecem somente CENTRO. Level2 foi desativado para evitar que uma área não validada apareça como jogável; `map_regions.json` conserva metadados históricos, e código de colisão experimental não o torna uma opção ativa.
- Liberty City permanece parcial: CENTRO contém quatro de 12 tiles-base; faltam oito. PCK ativo [`map-v2.2.2-spawn-fix`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/map-v2.2.2-spawn-fix), 62.720.388 bytes, SHA-256 `fc38ae751ea53c8795c222436ff7f332916a79eae5086521ced0ba7037cab26e`.
- O manifesto Pistola `2026.11.09.4` aponta ao PCK CENTRO e APK 3.0.5; o manifesto legado `2026.11.07.1` mantém APK 2.2.13 e o mesmo CENTRO. `spawn.json` usa `global-13`, 1.830 bytes, SHA-256 `9b839af0a1b967a482cb7a5b4d55bfd0b6da322d8a2c311e3b42d7c37ec0253b`. Health e manifests ativos foram verificados.
- Testes desta auditoria: suíte Python 16 (15 passaram, 1 skip porque o relatório de conversão foi excluído); parse Godot 4.7.2, isolamento, streamer e teste do PCK CENTRO passaram. Foram carregadas 50 partes visuais e 12 spawns locais/remotos, com gap máximo `0.000 m`. `npm test` e hashes dos manifests também passaram. O workflow foi atualizado para executar a suíte Python em cada push.
- Pendências: playtest visual/jogável no desktop; teste em Android físico para download, streaming, vidro, FPS, memória e controles touch; integrar os oito tiles restantes se o objetivo for Liberty City completa. Publicação de uma nova versão 3.0.6 de produção é opcional para levar as mudanças da fonte ao APK e exige resolver a assinatura comprometida antes. Assets de conversão excluídos do checkout público não devem ser confundidos com os OBJ/MTL runtime editáveis.

Antes de começar uma alteração, leia este arquivo, `docs/game-multiplayer.md`, `autoload/remote_updater.gd`, `scripts/net/multiplayer_client.gd` e o README do servidor. Depois de alterar, valide, atualize a documentação se o fluxo mudar e faça push somente dos arquivos intencionais.

# Manual de continuidade para IA — Andre 3D

Este documento explica como continuar o projeto sem depender do histórico da conversa. Leia também o manual do servidor no repositório `brechoda/andre3d-multiplayer-server`.

## Identidade dos repositórios

- Jogo Godot: `https://github.com/brechoda/Andre3D-game`
- Servidor multiplayer e distribuição: `https://github.com/brechoda/andre3d-multiplayer-server`
- Branch de produção dos dois repositórios: `main`
- Build multiplayer esperado: `andre3d-mp-v4`
- Pacote Android principal a partir da 2.0.6: `com.manus.andre3d.next`
- Pacote legado 2.0.5: `com.manus.andre3d`; a chave antiga foi perdida, então não pode ser atualizado no mesmo pacote.
- Versão Android pública atual: `2.2.9`
- Código Android público atual: `41`
- Último APK público: `2.2.9` / código `41`, distribuído em `https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/apk-v2.2.9`.
- O workflow `Build Android APK` cria artefatos de depuração com chave temporária; eles não podem atualizar o APK público. Releases de produção exigem a keystore original e publicação correspondente no manifesto do servidor.
- SHA-256 do APK público 2.2.9: `57962d7d66a59baac432a748a69813116bc33eb9e833bc38fda2d71525c195d0`.

## Objetivo do projeto

Andre 3D é um jogo Godot em terceira pessoa para Android, com modo offline e modo online. O menu inicial permite escolher offline/online e o personagem André, Gorece ou DG. O multiplayer usa um servidor WebSocket separado. O servidor é a autoridade para presença, estados retransmitidos, pulo, posse de veículos e algumas restrições de personagem.

Não substituir o projeto por um template novo. O projeto já tem mapa, veículos, personagens, controles, cenas, testes e histórico de conversão; alterações devem ser incrementais.

## Arquitetura importante

- `project.godot`: versão, cena inicial e autoloads. A cena inicial é `res://scenes/session_menu.tscn`.
- `scenes/session_menu.tscn` e `scripts/session_menu.gd`: menu inicial, escolha de modo/personagem, espera da checagem remota e bloqueio de entrada quando há atualização obrigatória do APK. No Android, solicita apenas `POST_NOTIFICATIONS` ao iniciar, depois da checagem e se ainda não estiver concedida; não bloqueia o jogo nem solicita o microfone no menu.
- `scenes/third_person.tscn` e `scripts/third_person.gd`: gameplay principal em terceira pessoa; mantém a tela de carregamento até o streamer confirmar geometria visual e colisão na área inicial, e por mais cinco segundos. O `WorldEnvironment` usa `PanoramaSkyMaterial` com o panorama de nuvens CODA. A orientação do modelo é aplicada em coordenadas globais; sprint começa na faixa externa do analógico com histerese, e o botão `CORRER` alterna sprint contínuo até novo toque. A HUD também tem `PUXAR VEÍCULO`, que abre a lista dos veículos da cena e traz o escolhido para cerca de 4,8 m à frente do personagem. Se o personagem cair no vazio, o streamer o recupera no último ponto seguro ou no spawn da região.
- `scripts/gta3_map_streamer.gd`: exige `map_region` explícito na sessão, mantém apenas os tiles da região escolhida e não usa proximidade para habilitar tiles da outra região. Agora seleciona tiles pela distância às bordas reais, processa colisões antes dos visuais e cria uma barreira invisível na região ativa.
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
- A assinatura principal usa a keystore de release original, guardada fora do repositório. Nunca commitar a keystore, senha ou credenciais de assinatura; preservar cópias seguras da chave.

## Testes e higiene do repositório

- Servidor: `cd server && npm ci && npm test`.
- Sintaxe/recursos Godot: `godot --headless --path . --editor --quit --check-only`.
- Não adicionar arquivos `.import` gerados automaticamente em massa. Depois de abrir/importar o projeto, remova `.import` não versionados; restaure `.import` que já eram versionados.
- Não adicionar APKs de build ao Git comum se o objetivo for apenas distribuição; use GitHub Releases. O arquivo em `dist/` pode ser ignorado conforme o `.gitignore`.
- Não apagar assets ou arquivos de proveniência para “limpar” o projeto.
- Ao alterar o mapa, veículos ou controles, testar também o carregamento e o modo touch Android.

## Estado conhecido entregue

- APK `2.2.9` (`com.manus.andre3d.next`, código `41`) corrige a falha que deixava o mapa preso na tela de carregamento: o APK exclui os assets do mapa e o Centro era tratado incorretamente como embutido, portanto o PCK remoto nunca era montado. Agora o app baixa e monta o PCK Centro validado antes de carregar a cena.
- Release pública Android: `https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/apk-v2.2.9`.
- APK: `125377562` bytes; SHA-256 `57962d7d66a59baac432a748a69813116bc33eb9e833bc38fda2d71525c195d0`. `apksigner` validou a assinatura e o fingerprint coincide com o APK 2.2.8; o asset da release reporta o mesmo tamanho e SHA-256.
- Manifesto obrigatório `2026.11.04.2`, publicado no commit [`d355464`](https://github.com/brechoda/andre3d-multiplayer-server/commit/d355464) do repositório de distribuição (`main`), com `client.version: 2.2.9`, `code: 41` e `mandatory_online: true`; confirmado ao vivo no Render com HTTP 200.
- Manifesto público: `https://andre3d-multiplayer-server.onrender.com/updates/manifest.json`.
- Correção do jogo/PCK obrigatório: commit [`039d4f8`](https://github.com/brechoda/Andre3D-game/commit/039d4f8); pacote/version code: commit [`039d4f8`](https://github.com/brechoda/Andre3D-game/commit/039d4f8); spawn `global-10`: [`0e85bd8`](https://github.com/brechoda/andre3d-multiplayer-server/commit/0e85bd8).
- Auditoria do mapa: 15 testes Python (14 passaram, um skipped por arquivo-fonte excluído) e análise headless Godot passaram; o PCK CENTRO publicado carregou quatro meshes visuais e os raycasts COL1 passaram para os seis spawns. O Android baixa esse pacote (62.817.264 bytes) antes da entrada.
- O servidor público respondeu `{"ok":true,"build":"andre3d-mp-v4","rooms":0}` em `/health`; o manifesto atual ativo é `2026.11.04.1` e serve só o PCK `center`.

Antes de começar uma alteração, leia este arquivo, `docs/game-multiplayer.md`, `autoload/remote_updater.gd`, `scripts/net/multiplayer_client.gd` e o README do servidor. Depois de alterar, valide, atualize a documentação se o fluxo mudar e faça push somente dos arquivos intencionais.

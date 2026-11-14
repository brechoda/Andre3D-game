# Andre 3D — mapa CENTRO de Liberty City

## O que está disponível

A única região selecionável e baixável na fonte atual é **CENTRO**, composta por quatro dos 12 tiles-base de Liberty City. Oito tiles ainda estão fora do PCK. Existem no checkout candidatos `landne` e `landsw` (38 partes OBJ e meshes de colisão), mas não estão registrados no catálogo de runtime/manifesto e não têm spawn, limites nem jogabilidade Android validados; portanto, não são regiões disponíveis. A lista-fonte completa precisa ser reconciliada para identificar os demais assets. A opção **Level 2** está desativada: embora permaneça como metadado/código histórico no projeto, o menu, o atualizador e o streamer aceitam somente CENTRO. Uma sessão antiga que peça Level 2 é redirecionada para CENTRO.

O PCK CENTRO é baixado sob demanda; não está embutido no APK. O jogo precisa de internet para obter o manifesto, baixar o arquivo e conferir tamanho e SHA-256 antes de montá-lo. O spawn remoto `global-13` coloca André e Gorece lado a lado sobre a superfície COL1 do Centro.

## Versões e endpoints conferidos

- **Projeto-fonte atual:** branch `main`, `project.godot` versão `3.0.6`, variante Andre 3D Pistola. A configuração do jogo usa [`/updates/pistol/manifest.json`](https://andre3d-multiplayer-server.onrender.com/updates/pistol/manifest.json).
- **Atualizador da variante Pistola:** manifesto `2026.11.09.4`, com cliente 3.0.5 servido por CDN (`131.086.654` bytes; SHA-256 `49f2b8df27c151c57b7516fc9348ec2882d0c1475c6dd7c6cf03102a6a167558`). O arquivo e o hash foram conferidos na auditoria de 10 de novembro de 2026. Esse endpoint lista somente CENTRO.
- **Release Pistola no repositório do jogo:** [`pistol-v3.0.0`](https://github.com/brechoda/Andre3D-game/releases/tag/pistol-v3.0.0) contém `Andre3D-3.0.0-debug.apk`, assinado com chave debug e baseado em código anterior à restrição para CENTRO; o menu dessa tag ainda mostra Level 2. O manifesto atual anuncia 3.0.5, e o cliente 3.0.0 considera qualquer versão maior obrigatória e bloqueia o início até o usuário baixar/instalar a atualização. Portanto, não use a 3.0.0 sem completar o fluxo de atualização.
- **Manifesto principal legado:** [`/updates/manifest.json`](https://andre3d-multiplayer-server.onrender.com/updates/manifest.json), versão `2026.11.07.1`, cliente `2.2.13` código `45`; também lista somente CENTRO. A release principal do repositório do servidor é [`apk-v2.2.13`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/apk-v2.2.13). A variante Pistola 3.0.5 é entregue pelo endpoint/CDN separado.
- **Build de CI da fonte 3.0.6:** workflow `42758706238` passou e publicou apenas o artefato debug `Andre3D-3.0.6-debug`; não é uma release Android de produção. Uma publicação de produção requer estratégia segura de assinatura; a keystore principal foi exposta historicamente, conforme o alerta no `docs/AI_HANDOFF.md`.
- **PCK CENTRO:** [`map-v2.2.2-spawn-fix`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/map-v2.2.2-spawn-fix), `Andre3D-map-center.pck`, `62.720.388` bytes, SHA-256 `fc38ae751ea53c8795c222436ff7f332916a79eae5086521ced0ba7037cab26e`.

## Abrir o projeto editável

O projeto Godot completo está em [`brechoda/Andre3D-game`](https://github.com/brechoda/Andre3D-game), branch `main`, pasta `game/`. Clone o repositório e abra `game/project.godot` no Godot `4.7.2`. Os OBJ/MTL runtime do Centro e o código do streamer estão incluídos no checkout; assets originais de conversão excluídos não são necessários para editar esses recursos runtime. Para exportar somente o PCK Centro, use o preset `Android Map Center` (`preset.2`).

## Validação e o que ainda falta

Nesta auditoria, a suíte Python executou `16` testes: `15` passaram e `1` foi ignorado porque o relatório de conversão-fonte não está no repositório público. Godot 4.7.2 passou a verificação de parse, isolamento de região e instanciação do streamer. O PCK CENTRO carregou 50 partes visuais e os 12 pontos de verificação de spawns locais/remotos ficaram sobre COL1, com gap máximo de `0.000 m`. Os manifests locais e os dois endpoints ativos foram comparados: ambos publicam apenas CENTRO; o health do servidor e `npm test` também passaram.

Ainda é necessário fazer playtest visual/jogável do CENTRO em desktop e instalar a variante pretendida em um Android físico para conferir download, montagem, controles touch, transparência do vidro, transição entre tiles, FPS e memória. Para Liberty City completa, os oito tiles fora do PCK precisam ser reconciliados com a lista-fonte; `landne`/`landsw` são candidatos locais que exigem integração e validação antes de qualquer publicação. Level 2 não faz parte da disponibilidade atual; se for reativado no futuro, exige nova validação de colisões, memória e aparelho físico antes de voltar ao menu/manifesto.

Para repetir os testes no projeto:

```bash
cd game
python3 -m unittest tests.test_gta3_map_assets tests.test_map_boundary_protection -v
godot --headless --path . --editor --quit --check-only
godot --headless --path . --script res://test/check_map_region_isolation.gd
godot --headless --path . --script res://test/check_gta3_map_streamer_script.gd
godot --headless --path . --script res://test/check_map_region_spawns.gd -- <centro.pck> center <spawn.json>
```

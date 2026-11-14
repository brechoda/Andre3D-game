# Liberty City (GTA III) — estado da integração

**Auditoria:** 14 de novembro de 2026. Este relatório distingue o projeto-fonte atual, a variante Pistola distribuída pelo atualizador e os APKs debug publicados em repositórios diferentes.

## Conclusão

A região **CENTRO** está validada em Godot headless e é a **única região atualmente suportada** no cliente 3.0.6 e nos manifests ativos. Ela contém quatro dos 12 tiles-base de Liberty City. Portanto, o recorte Centro está tecnicamente pronto para download e validação headless, mas **Liberty City completa ainda não está pronta**: oito tiles continuam fora do PCK. Esta auditoria encontrou dois conjuntos candidatos no checkout (`landne` e `landsw`), mas eles ainda não estão registrados como regiões jogáveis nem passaram por teste de spawn, limites e Android; a lista-fonte completa dos 12 tiles não está neste repositório. Também falta o playtest visual/jogável do Centro.

A fonte `main` está na versão `3.0.6` da variante **Andre 3D Pistola**. O `RemoteUpdater` e o `Gta3MapStreamer` aceitam somente `center`; o menu apresenta CENTRO. Embora `map_regions.json` ainda conserve metadados históricos de Level 2 e o streamer mantenha código experimental para esse mapa, Level 2 não é baixável nem selecionável: não consta nos manifests ativos e sessões antigas que o solicitem são direcionadas ao Centro. Não se deve descrever Level 2 como funcional/disponível nesta versão.

As verificações headless confirmam dados, seleção dos tiles do Centro, carregamento das 50 partes visuais e spawns sobre COL1. Elas não substituem uma inspeção visual e teste real de controles, streaming, transparência, FPS ou memória em um aparelho Android.

## Escopo e implementação

A meta de conversão documenta 12 tiles-base. O catálogo runtime versionado registra seis conjuntos: os quatro tiles do recorte publicado CENTRO (`comnbtm`, `comntop`, `comse`, `comsw`) e os auxiliares `maps/overview` e `maps/props`; estes dois auxiliares não são regiões selecionáveis. O inventário encontrou também 14 partes OBJ de `landne` e 24 de `landsw`, com MTL/texturas referenciadas presentes e um OBJ de colisão para cada conjunto, mas esses arquivos não constam em `tile_parts.json`, `collision_manifest.json` nem `map_regions.json`. Sua presença não os torna disponíveis no jogo. `assets/maps/costa_vista` também não é uma região selecionável nesta integração.

A cena `scenes/third_person.tscn` usa `scripts/gta3_map_streamer.gd`. O menu prepara o conteúdo selecionado; `ExternalContent` monta o PCK regional depois de validar tamanho e SHA-256. O mapa não está embutido no APK e precisa ser baixado. No cliente atual, a lista permitida contém somente `center`; o streamer restringe o catálogo aos quatro tiles autorizados, seleciona tiles por bounds, processa colisões antes das meshes visuais e cria limites físicos invisíveis ao redor da área. As faixas de água da borda são visuais intencionais, separadas das paredes de colisão invisíveis.

O manifesto local ainda contém uma entrada histórica para Level 2, e o código de colisão trimesh dessa cena continua no fonte, mas ambos estão inativos para a versão atual. A geração de colisões Level 2 já passou anteriormente por testes headless; isso não significa que a região esteja disponível, nem substitui validação Android se ela voltar a ser habilitada.

## Spawns e PCK CENTRO

A revisão remota `global-13` e o manifesto interno do PCK CENTRO usam a mesma superfície COL1. André fica em `[184.73, 3.3474, -22.03]` e Gorece em `[185.0, 3.3474, -19.0]`; em `map_regions.json`, as coordenadas locais são `[315.33, 18.5474, 52.43]` e `[315.6, 18.5474, 49.4]`. Os quatro veículos também têm posições definidas.

O teste carrega o PCK com substituição dos recursos locais, inspeciona as 50 partes OBJ regionais e valida os spawns locais e remotos: 12 pontos de verificação sobre COL1, com distância vertical máxima de `0.000 m`. A validação isolada anterior confirmou quatro colisões regionais e `ground_fix` dentro do pacote.

## Distribuição atual

- **PCK CENTRO:** release [`map-v2.2.2-spawn-fix`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/map-v2.2.2-spawn-fix), `Andre3D-map-center.pck`, `62.720.388` bytes, SHA-256 `fc38ae751ea53c8795c222436ff7f332916a79eae5086521ced0ba7037cab26e`. Os manifests ativos apontam para esse mesmo pacote; só CENTRO é listado.
- **Variante Pistola usada pela fonte 3.0.6:** `config/updates.json` aponta para [`/updates/pistol/manifest.json`](https://andre3d-multiplayer-server.onrender.com/updates/pistol/manifest.json), versão de manifesto `2026.11.09.4`, variante `andre3d-pistol`, `min_app_version` `3.0.0`. O endpoint anuncia o cliente 3.0.5 num APK CDN de `131.086.654` bytes, SHA-256 `49f2b8df27c151c57b7516fc9348ec2882d0c1475c6dd7c6cf03102a6a167558`; o arquivo baixado na auditoria de 10 de novembro de 2026 conferiu em tamanho e hash. O manifesto lista apenas CENTRO.
- **Release Pistola 3.0.0 no repositório do jogo:** [`pistol-v3.0.0`](https://github.com/brechoda/Andre3D-game/releases/tag/pistol-v3.0.0), publicada como `Andre3D-3.0.0-debug.apk` (`131.081.963` bytes; SHA-256 `9de29d8f005ee2ee2251c5555c536017945db24b64fd0972a4ad5ffca6faa4a8`). A tag `626721a` antecede a revisão center-only e ainda contém opção/whitelist Level 2. Contudo, seu updater vê o cliente `3.0.5` anunciado no manifesto como versão superior a `3.0.0`, considera a atualização obrigatória e bloqueia `_start_game()` até instalá-la. A 3.0.5 é servida por CDN; não há release GitHub `apk-v3.0.5`.
- **Endpoint principal legado:** [`/updates/manifest.json`](https://andre3d-multiplayer-server.onrender.com/updates/manifest.json) continua na versão `2026.11.07.1`, com cliente `2.2.13` (código `45`) e somente CENTRO. A release `apk-v2.2.13` pertence ao repositório do servidor e não à variante Pistola.
- **Fonte atual:** `project.godot` registra `3.0.6`; o workflow Android passou no CI `42758706238` e produz artefato `3.0.6-debug` (`80.411.105` bytes), não uma release de produção. O commit `be9859b` restringiu a variante 3.0.5 a CENTRO; a main atual também limita whitelist, menu e streamer a essa região.
- **Spawn remoto:** `global-13`, `1.830` bytes, SHA-256 `9b839af0a1b967a482cb7a5b4d55bfd0b6da322d8a2c311e3b42d7c37ec0253b`.
- **Servidor:** `/health` respondeu `ok: true`, build `andre3d-mp-v4`; `npm test` passou. Os dois manifests servidos pelo Render correspondem aos arquivos do repositório e listam somente CENTRO.

A keystore de assinatura principal foi exposta historicamente no repositório público. Qualquer publicação de uma nova versão de produção deve seguir o plano de assinatura/migração segura descrito no `AI_HANDOFF.md`; o artefato CI debug não é atualização de produção.

## Verificações executadas nesta auditoria

- Suíte Python de mapa e limites: `16` testes; `15` aprovados e `1` ignorado porque o relatório de conversão-fonte não integra o repositório público de assets runtime.
- Godot 4.7.2 `--editor --quit --check-only`: sem erros de parse.
- `check_map_region_isolation.gd`: quatro tiles do CENTRO restritos e tile do spawn selecionado.
- `check_gta3_map_streamer_script.gd`: streamer instanciado; recursos de `ground_fix` carregados.
- `check_map_region_spawns.gd` com o PCK CENTRO ativo: 50 partes visuais e 12 verificações de spawns locais/remotos, gap máximo `0.000 m`.
- Verificador headless temporário de candidatos: Godot carregou 14 partes/94.183 triângulos de `landne` e 24 partes/197.491 triângulos de `landsw`, mais uma mesh de colisão para cada; isso só confirma importação de recursos, não alinhamento de colisão, spawn ou jogabilidade.
- Endpoint configurado para Pistola e endpoint legado comparados com os manifests locais: ambos saudáveis/coerentes e com CENTRO como única região.
- APK CDN Pistola 3.0.5: tamanho e SHA-256 conferidos contra o manifesto ativo.
- Release `pistol-v3.0.0`: tag, APK debug e código antigo com Level 2 verificados; a checagem de versão confirma que o cliente bloqueia o início até baixar/instalar o 3.0.5 anunciado pelo servidor.
- Servidor: `node --check server.mjs` e `npm test` passaram.

## Estado e pendências

| Item | Estado | Observação |
|---|---|---|
| PCK CENTRO | Validado headless | 50 partes visuais; cinco meshes de colisão verificadas no PCK; spawns no piso. |
| Streaming e bounds do Centro | Validado headless | Apenas quatro tiles da região Centro podem ser selecionados/streamados. |
| Release Pistola 3.0.0 | Debug, substituída pelo updater | A tag antiga ainda mostra Level 2, mas o manifesto atual exige atualizar para 3.0.5 antes de iniciar gameplay. |
| Level 2 | Desativado na versão atual | Metadados e código experimental permanecem no fonte, mas updater, menu e streamer suportam somente Centro. |
| Liberty City completa | Parcial | CENTRO cobre 4/12 tiles-base; oito estão fora do PCK. Há candidatos `landne`/`landsw` no checkout, mas ainda não são regiões do catálogo nem têm spawn/limites validados; a proveniência/lista dos demais tiles precisa ser reconciliada com a fonte completa. |
| Spawn remoto | Corrigido (`global-13`) | Seis posições locais/remotas coincidem e ficam sobre COL1 (gap `0.000 m`). |
| Transparência `subglass` | Assets de substituição presentes | Aparência ainda precisa de playtest visual. |
| Playtest desktop | Pendente | Percorrer o Centro, inspecionar vidro, transições de tile e colisões. |
| Teste Android físico | Pendente | Instalar a variante pretendida; validar download, montagem, controles touch, FPS e memória. |
| Nova versão 3.0.6 de produção | Pendente, se desejada | CI produz debug; resolver assinatura segura antes de distribuir build de produção. |
| Tiles fora do PCK | Pendente para cidade completa | Registrar e validar `landne`/`landsw` se forem tiles-base válidos; localizar/reconciliar os demais assets e a lista-fonte. Só depois testar colisões, spawns, streaming, PCK e Android antes de chamar a cobertura completa. |

Para repetir as verificações locais:

```bash
python3 -m unittest tests.test_gta3_map_assets tests.test_map_boundary_protection -v
godot --headless --path . --editor --quit --check-only
godot --headless --path . --script res://test/check_map_region_isolation.gd
godot --headless --path . --script res://test/check_gta3_map_streamer_script.gd
godot --headless --path . --script res://test/check_map_region_spawns.gd -- <centro.pck> center <spawn.json>
```

O preset de exportação chama-se `Android Map Center` (`preset.2`). O projeto editável está no repositório [`brechoda/Andre3D-game`](https://github.com/brechoda/Andre3D-game), pasta `game/`. Os assets OBJ/MTL runtime estão disponíveis no checkout; assets originais de conversão excluídos não devem ser confundidos com eles.

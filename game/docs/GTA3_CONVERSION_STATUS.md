# Liberty City (GTA III) — estado de integração

## Estado resumido

O mapa **já está integrado visualmente à cena jogável** como tiles com carregamento por proximidade. A cena usa até três regiões próximas do jogador, mantém os controles, personagens, veículos e o multiplayer existentes, e agora carrega colisões derivadas dos arquivos COL1 originais por setor.

## Base de dados e conversão

O projeto preserva o IMG mobile extraído em 3.402 entradas, incluindo 2.911 DFF e 491 TXD, além de IPL, IDE, COL e DAT. O manifesto espacial contém 8.689 posicionamentos em 12 tiles, cobrindo dez setores urbanos, props e overview. A conversão visual existente gerou cerca de 2,48 milhões de vértices e 1,46 milhão de triângulos distribuídos nos 12 OBJ originais.

A primeira importação de teste identificou que os OBJ originais excediam o limite de superfícies suportado pelo importador OBJ do Godot; a peça de teste gerava erros após atingir o máximo de superfícies. Também foi confirmado que os MTL originais apontavam as texturas um nível acima da pasta correta. Para resolver os bloqueios, `tools/split_gta3_obj_surfaces.py` gera 156 peças OBJ/MTL, cada uma com até 96 materiais, reescrevendo as referências para `../textures/...`. As peças e seu manifesto ficam em `assets/maps/liberty_city/godot_tiles/`; o script também copia para `assets/maps/liberty_city/textures/` apenas as 2.924 texturas referenciadas (aproximadamente 32 MB) e inclui ali o catálogo espacial. Essa árvore runtime fica fora de `assets/source`, que é excluída do preset Android.

## Integração runtime

`scenes/third_person.tscn` instancia `scripts/gta3_map_streamer.gd`, que usa a árvore runtime `assets/maps/liberty_city`. A cena alinha os eixos do sistema de coordenadas GTA ao eixo Y-up do Godot e desloca o mapa para que o jogador comece sobre uma via do IPL. O carregador compara a posição do jogador com os centros espaciais do catálogo e requisita os meshes dos três tiles mais próximos em segundo plano, mantendo também o overview em memória como referência distante. Para cada tile ativo, um OBJ de colisão é carregado separadamente e convertido em `StaticBody3D` trimesh; esse OBJ foi gerado diretamente dos modelos COL1, incluindo faces, caixas e esferas, após aplicar os posicionamentos IPL.

## Verificações executadas

Os testes `tests/test_gta3_map_assets.py` verificam cobertura dos 12 tiles, correspondência entre faces OBJ e manifesto, limite máximo de 96 materiais, caminhos de textura, transparência de `subglass` e registro dos assets do remendo de chão para Android. O teste de paridade contra `conversion_report.json` é executado quando os dados-fonte estão disponíveis; esse arquivo fica em `assets/source`, excluído do checkout público/runtime. `test/check_gta3_map_streamer_script.gd` também carrega os OBJ de visual e colisão do remendo de chão como meshes pelo Godot.

A validação headless da cena de terceira pessoa foi executada por 15 segundos. O log não mostrou falhas do streamer nem de recursos do mapa, mas reportou três arquivos de áudio Fiat Uno ausentes (`fiat_uno_motor_ligado.wav`, `fiat_uno_acelerando.wav` e `fiat_uno_desacelerando.wav`), que são uma pendência separada do mapa. O workflow GitHub Actions de Android concluiu builds APK com sucesso. Isso não substitui um playtest visual/jogável interativo no desktop nem a instalação e validação em dispositivo Android.

## Pendências para finalização

| Item | Estado | Observação |
|---|---|---|
| Streaming visual dos tiles e texturas | Integrado | O overview fica carregado; até três tiles próximos são carregados sob demanda. |
| Importação OBJ compatível com Godot | Verificada em peça de teste | As peças foram limitadas a 96 materiais/superfícies. |
| Colisão de movimento | Integrada | Usa os meshes de colisão COL1 dos tiles ativos, com layer/mask 1. |
| Colisão fonte COL | Integrada | 24 arquivos COL1 foram decodificados; os 8.689 posicionamentos tiveram modelo COL correspondente e foram gerados em 12 meshes por tile. |
| Transparência/máscaras | Integrada | O streamer detecta as 280 texturas runtime com alpha, duplica os materiais e aplica `TRANSPARENCY_ALPHA` com culling desativado. |
| TXD `subglass.txd` | Corrigido | A entrada original tinha somente 36 bytes úteis; foram geradas texturas RGBA substitutas para `glassfxsub1` e `glassfxsub2`, com MTLs atualizados e relatório de reparo. |
| Remendos de terreno e colisão | Integrados ao streamer | `ground_fix_visual.obj` e `ground_fix_collision.obj` são registrados como tile especial e carregados por recursos importados, sem depender do OBJ-fonte estar acessível via `FileAccess` no APK. |
| Smoke test desktop | Parcial | A cena rodou por 15 segundos sem erros do mapa/streamer; o log acusa três áudios Fiat Uno ausentes, fora do mapa. |
| Playtest visual desktop | Pendente | Conferir movimento, colisão, visibilidade, bordas dos remendos, câmera e streaming em execução interativa. |
| Build APK Android | Aprovado no CI | O workflow cria APK; falta instalar e validar o mapa em dispositivo Android real. |

Para regenerar as peças runtime e as respectivas texturas, execute `python3 tools/split_gta3_obj_surfaces.py --source assets/source/gta3_map/converted_tiles --output assets/maps/liberty_city/godot_tiles --material-limit 96`. Para regenerar as colisões COL1, instale `rwfury` e execute `python3 tools/generate_gta3_col_collision.py --manifest assets/source/gta3_map/map_manifest.json --col-root assets/source/gta3_map --output assets/maps/liberty_city/collisions`. Para reparar o subglass e atualizar os MTLs, execute `python3 tools/fix_gta3_transparency.py --source-txd assets/source/gta3_map/subglass.txd --mtl-root assets/maps/liberty_city/godot_tiles --texture-root assets/maps/liberty_city/textures --report assets/maps/liberty_city/subglass_repair_report.json`. Para validar os assets, execute `python3 tests/test_gta3_map_assets.py`.

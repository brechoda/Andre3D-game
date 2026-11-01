# Liberty City (GTA III) — estado de integração

## Estado resumido

O mapa **já está integrado visualmente à cena jogável** como tiles com carregamento por proximidade. A cena usa até três regiões próximas do jogador, mantém os controles, personagens, veículos e o multiplayer existentes, e agora carrega colisões derivadas dos arquivos COL1 originais por setor.

## Base de dados e conversão

O projeto preserva o IMG mobile extraído em 3.402 entradas, incluindo 2.911 DFF e 491 TXD, além de IPL, IDE, COL e DAT. O manifesto espacial contém 8.689 posicionamentos em 12 tiles, cobrindo dez setores urbanos, props e overview. A conversão visual existente gerou cerca de 2,48 milhões de vértices e 1,46 milhão de triângulos distribuídos nos 12 OBJ originais.

A primeira importação de teste identificou que os OBJ originais excediam o limite de superfícies suportado pelo importador OBJ do Godot; a peça de teste gerava erros após atingir o máximo de superfícies. Também foi confirmado que os MTL originais apontavam as texturas um nível acima da pasta correta. Para resolver os bloqueios, `tools/split_gta3_obj_surfaces.py` gera 156 peças OBJ/MTL, cada uma com até 96 materiais, reescrevendo as referências para `../textures/...`. As peças e seu manifesto ficam em `assets/maps/liberty_city/godot_tiles/`; o script também copia para `assets/maps/liberty_city/textures/` apenas as 2.924 texturas referenciadas (aproximadamente 32 MB) e inclui ali o catálogo espacial. Essa árvore runtime fica fora de `assets/source`, que é excluída do preset Android.

## Integração runtime

`scenes/third_person.tscn` instancia `scripts/gta3_map_streamer.gd`, que usa a árvore runtime `assets/maps/liberty_city`. A cena alinha os eixos do sistema de coordenadas GTA ao eixo Y-up do Godot e desloca o mapa para que o jogador comece sobre uma via do IPL. O carregador compara a posição do jogador com os centros espaciais do catálogo e requisita os meshes dos três tiles mais próximos em segundo plano, mantendo também o overview em memória como referência distante. Para cada tile ativo, um OBJ de colisão é carregado separadamente e convertido em `StaticBody3D` trimesh; esse OBJ foi gerado diretamente dos modelos COL1, incluindo faces, caixas e esferas, após aplicar os posicionamentos IPL.

## Verificações executadas

Os cinco testes `tests/test_gta3_map_assets.py` verificam cobertura dos 12 tiles, igualdade do número de triângulos entre fonte e peças, limite máximo de 96 materiais por peça, existência dos PNG referenciados e integração estática com a cena. O teste Godot `test/check_gta3_obj_import.gd` foi executado em um projeto isolado com uma peça real e importou uma malha com 96 superfícies. Um smoke test runtime separado carregou essa peça através do streamer e confirmou a presença do `StaticBody3D` trimesh. `test/check_gta3_map_streamer_script.gd` confirmou que o script de streaming pode ser carregado e instanciado pelo Godot 4.7.2.

A validação headless da cena de terceira pessoa foi concluída após a importação dos assets runtime: a cena executou por 15 segundos sem erros críticos, recursos ausentes ou falhas de script, e os meshes COL1 foram importados pelo Godot. Isso ainda não substitui um playtest visual/jogável com interação de câmera, movimento e streaming em desktop.

## Pendências para finalização

| Item | Estado | Observação |
|---|---|---|
| Streaming visual dos tiles e texturas | Integrado | O overview fica carregado; até três tiles próximos são carregados sob demanda. |
| Importação OBJ compatível com Godot | Verificada em peça de teste | As peças foram limitadas a 96 materiais/superfícies. |
| Colisão de movimento | Integrada | Usa os meshes de colisão COL1 dos tiles ativos, com layer/mask 1. |
| Colisão fonte COL | Integrada | 24 arquivos COL1 foram decodificados; os 8.689 posicionamentos tiveram modelo COL correspondente e foram gerados em 12 meshes por tile. |
| Transparência/máscaras | Integrada | O streamer detecta as 280 texturas runtime com alpha, duplica os materiais e aplica `TRANSPARENCY_ALPHA` com culling desativado. |
| TXD `subglass.txd` | Corrigido | A entrada original tinha somente 36 bytes úteis; foram geradas texturas RGBA substitutas para `glassfxsub1` e `glassfxsub2`, com MTLs atualizados e relatório de reparo. |
| Smoke test desktop | Concluído | A cena de terceira pessoa executou por 15 segundos em Godot headless sem erros críticos; os meshes COL1 foram importados. |
| Playtest visual desktop | Pendente | Conferir movimento, colisão, visibilidade, câmera e carregamento assíncrono em execução interativa. |
| APK | Pendente | A validação Android será feita após o playtest desktop. |

Para regenerar as peças runtime e as respectivas texturas, execute `python3 tools/split_gta3_obj_surfaces.py --source assets/source/gta3_map/converted_tiles --output assets/maps/liberty_city/godot_tiles --material-limit 96`. Para regenerar as colisões COL1, instale `rwfury` e execute `python3 tools/generate_gta3_col_collision.py --manifest assets/source/gta3_map/map_manifest.json --col-root assets/source/gta3_map --output assets/maps/liberty_city/collisions`. Para reparar o subglass e atualizar os MTLs, execute `python3 tools/fix_gta3_transparency.py --source-txd assets/source/gta3_map/subglass.txd --mtl-root assets/maps/liberty_city/godot_tiles --texture-root assets/maps/liberty_city/textures --report assets/maps/liberty_city/subglass_repair_report.json`. Para validar os assets, execute `python3 tests/test_gta3_map_assets.py`.

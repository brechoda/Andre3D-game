# Liberty City (GTA III) — estado de integração

## Estado resumido

O mapa é jogável por streaming nas duas regiões distribuídas atualmente: **INDUSTRIAL** e **CENTRO**. O APK não leva as malhas do mapa; baixa um PCK regional e o jogo monta somente a região escolhida. A auditoria encontrou e corrigiu o spawn do CENTRO, que estava fora do piso COL1, e as alturas remotas dos veículos, que ficavam cerca de 80 m acima do terreno. Os novos spawns locais e remotos e os PCKs foram validados com Godot 4.7.2; ainda falta playtest visual/interativo em desktop e Android físico para declarar o mapa finalizado.

## Conteúdo e escopo

A conversão do repositório contém 12 tiles-base, com cerca de 1,46 milhão de triângulos nas malhas originais divididas em 156 peças OBJ/MTL (máximo de 96 materiais por peça). O catálogo espacial também contém os dados para overview e props. A seleção de regiões habilita quatro tiles para CENTRO e quatro para INDUSTRIAL. Os tiles `landne/landne`, `landsw/landsw`, `maps/overview` e `maps/props` não fazem parte dos dois PCKs oferecidos no menu. Portanto, a distribuição regional atual não equivale a todos os tiles da Liberty City original; os recortes de ilhas/parques foram retirados da seleção de propósito.

As peças ficam em `assets/maps/liberty_city/godot_tiles/`; texturas referenciadas pelos MTLs ficam em `assets/maps/liberty_city/textures/`. O patch do chão usa `ground_fix_visual.obj` e `ground_fix_collision.obj`. As colisões COL1 dos setores foram geradas a partir dos modelos-fonte, com faces, caixas e esferas posicionadas pelos IPL.

## Integração no jogo

`scenes/third_person.tscn` instancia `scripts/gta3_map_streamer.gd`. A escolha do menu é gravada na sessão; `ExternalContent` baixa, valida por tamanho e SHA-256, e monta somente o PCK escolhido. O APK exclui `assets/maps/*`; os pacotes regionais externos fornecem os assets necessários. O streamer restringe o catálogo aos quatro tiles da região selecionada, seleciona tiles pela distância aos limites espaciais e carrega as colisões antes das malhas visuais. O patch de chão é carregado como recurso importado, sem depender de `FileAccess.file_exists()` sobre o OBJ-fonte no APK. Montanhas visuais e barreiras físicas delimitam a região; o jogador e Gorece têm recuperação ao cair fora do mapa.

O manifesto local agora guarda posições para jogador, Gorece e cada veículo por região. O streamer as aplica também no modo offline e sincroniza a referência de chão depois de um teleporte. A configuração remota (`spawn_revision: regional-06`) foi corrigida junto: CENTRO mudou de `z=517` para `z=497`, onde os seis raios de spawn encontram colisão; as alturas dos quatro veículos em CENTRO e INDUSTRIAL foram recalculadas a partir dos meshes COL1.

O servidor de atualizações anuncia os PCKs CENTRO e INDUSTRIAL na release `map-v2.2.1-spawn-fix`. O manifesto ainda lista um pacote opcional `islands`, mas o APK atual só aceita os IDs `center` e `industrial`, então esse item extra não pode ser escolhido nem montado pela seleção normal do jogo.

O deploy automático do Render foi confirmado: `/health` respondeu `ok: true` e o manifesto público passou para `2026.11.03.15`, com `spawn_revision: regional-06` e hashes dos dois PCKs novos. O commit de produção do servidor é `d6778b6b`.

## Verificações executadas

A suíte `tests.test_gta3_map_assets` e `tests.test_map_boundary_protection` executou 14 testes: 13 passaram e o único teste que compara com `assets/source/.../conversion_report.json` foi pulado porque os dados-fonte são excluídos do checkout público. O novo teste `test/check_map_region_spawns.gd` verificou o piso sob 12 pontos nos assets locais; montado sobre cada PCK publicado, verificou os quatro meshes visuais e o piso COL1 sob os seis pontos de spawn daquela região. O teste `test/check_map_region_isolation.gd` confirmou que escolher CENTRO não solicita tiles INDUSTRIAL; `test/check_gta3_map_streamer_script.gd` confirmou a importação do streamer e dos meshes do patch de chão.

Os PCKs corrigidos foram exportados, montados localmente no Godot 4.7.2 e publicados em `map-v2.2.1-spawn-fix`. CENTRO: 62.826.740 bytes, SHA-256 `93edca3a3cd8f3f9bffabe3da117ac559e8416d3f32e5e6a1fdcf3ea166d17e1`; INDUSTRIAL: 54.334.712 bytes, SHA-256 `2c856d1e8cc781311e039e06ef204a17fac7f677ae26c7cc9257db69fa90ec47`. Os novos PCKs carregaram uma mesh visual por tile e colisão COL1 sob player, Gorece e cada veículo. Os builds APK mais recentes do GitHub Actions concluíram com sucesso.

Essas verificações são headless: não demonstram qualidade visual, continuidade perfeita entre tiles, desempenho em um Android específico ou comportamento dos controles na tela. Uma execução headless da cena também registrou três arquivos de áudio Fiat Uno ausentes (`fiat_uno_motor_ligado.wav`, `fiat_uno_acelerando.wav` e `fiat_uno_desacelerando.wav`), uma pendência separada do mapa.

## Pendências para considerar pronto

- Fazer playtest visual e jogável em desktop, conferindo câmera, movimento, streaming, colisões e bordas dos remendos de chão nas duas regiões.
- Instalar o APK atual em aparelho Android e validar download dos PCKs, montagem da região escolhida, controles touch, memória e desempenho.
- Se o objetivo for entregar toda a Liberty City, decidir se os quatro tiles atualmente excluídos devem voltar a ser convertidos e oferecidos como regiões próprias. Isso amplia o escopo atualmente selecionável.

| Item | Estado | Observação |
|---|---|---|
| PCK INDUSTRIAL e CENTRO | Verificados no Godot | Novos hashes/tamanhos registrados; 4 meshes visuais por pacote e piso sob 6 spawns por região. |
| Isolamento de região | Verificado | O teste de runtime confirmou que CENTRO não solicita tiles INDUSTRIAL. |
| Colisões COL1 e patch do chão | Integrados | O streamer prioriza colisões; os meshes do patch foram importados nos dois PCKs. |
| Transparência e `subglass.txd` | Corrigidos | O streamer detecta alpha e os MTLs usam substitutos RGBA para o TXD truncado. |
| Build APK | Aprovado no CI | O GitHub Actions exportou e verificou APK; isso não comprova instalação em aparelho. |
| Playtest visual desktop/Android | Pendente | Necessário antes de declarar qualidade e desempenho finais. |

Para testar os pontos de spawn contra as colisões e meshes visuais, execute `godot --headless --path . --script res://test/check_map_region_spawns.gd`; com um pacote exportado, acrescente `-- <arquivo.pck> <center|industrial>`. Para exportar novamente os PCKs, use os presets `Android Map Center` e `Android Map Industrial`. Para regenerar as peças runtime e as texturas, execute `python3 tools/split_gta3_obj_surfaces.py --source assets/source/gta3_map/converted_tiles --output assets/maps/liberty_city/godot_tiles --material-limit 96`. Para regenerar as colisões COL1, instale `rwfury` e execute `python3 tools/generate_gta3_col_collision.py --manifest assets/source/gta3_map/map_manifest.json --col-root assets/source/gta3_map --output assets/maps/liberty_city/collisions`. Para reparar o `subglass.txd`, execute `python3 tools/fix_gta3_transparency.py --source-txd assets/source/gta3_map/subglass.txd --mtl-root assets/maps/liberty_city/godot_tiles --texture-root assets/maps/liberty_city/textures --report assets/maps/liberty_city/subglass_repair_report.json`. Para validar os assets, execute `python3 -m unittest tests.test_gta3_map_assets tests.test_map_boundary_protection -v`.

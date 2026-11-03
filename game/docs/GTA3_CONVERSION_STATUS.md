# Liberty City (GTA III) — estado de integração

## Estado resumido

O mapa é jogável por streaming nas duas regiões distribuídas atualmente: **INDUSTRIAL** e **CENTRO**. O APK não leva as malhas do mapa; baixa um PCK regional e o jogo monta somente a região escolhida. Os assets, pacotes e meshes de colisão foram verificados no Godot, mas ainda falta o playtest visual/interativo em desktop e Android físico para declarar o mapa finalizado.

## Conteúdo e escopo

A conversão do repositório contém 12 tiles-base, com cerca de 1,46 milhão de triângulos nas malhas originais divididas em 156 peças OBJ/MTL (máximo de 96 materiais por peça). O catálogo espacial também contém os dados para overview e props. A seleção de regiões habilita quatro tiles para CENTRO e quatro para INDUSTRIAL. Os tiles `landne/landne`, `landsw/landsw`, `maps/overview` e `maps/props` não fazem parte dos dois PCKs oferecidos no menu. Portanto, a distribuição regional atual não equivale a todos os tiles da Liberty City original; os recortes de ilhas/parques foram retirados da seleção de propósito.

As peças ficam em `assets/maps/liberty_city/godot_tiles/`; texturas referenciadas pelos MTLs ficam em `assets/maps/liberty_city/textures/`. O patch do chão usa `ground_fix_visual.obj` e `ground_fix_collision.obj`. As colisões COL1 dos setores foram geradas a partir dos modelos-fonte, com faces, caixas e esferas posicionadas pelos IPL.

## Integração no jogo

`scenes/third_person.tscn` instancia `scripts/gta3_map_streamer.gd`. A escolha do menu é gravada na sessão; `ExternalContent` baixa, valida por tamanho e SHA-256, e monta somente o PCK escolhido. O APK exclui `assets/maps/*`; os pacotes regionais externos fornecem os assets necessários. O streamer restringe o catálogo aos quatro tiles da região selecionada, seleciona tiles pela distância aos limites espaciais e carrega as colisões antes das malhas visuais. O patch de chão é carregado como recurso importado, sem depender de `FileAccess.file_exists()` sobre o OBJ-fonte no APK. Montanhas visuais e barreiras físicas delimitam a região; o jogador e Gorece têm recuperação ao cair fora do mapa.

O servidor de atualizações atualmente anuncia pacotes CENTRO e INDUSTRIAL na release `map-v2.2.0-regions`. O manifesto ainda lista um pacote opcional `islands`, mas o APK atual só aceita os IDs `center` e `industrial`, então esse item extra não pode ser escolhido nem montado pela seleção normal do jogo.

## Verificações executadas

A suíte `tests.test_gta3_map_assets` e `tests.test_map_boundary_protection` executou 13 testes: 12 passaram e o único teste que compara com `assets/source/.../conversion_report.json` foi pulado porque os dados-fonte são excluídos do checkout público. O teste Godot `test/check_map_region_isolation.gd` confirmou que escolher CENTRO não solicita tiles INDUSTRIAL; `test/check_gta3_map_streamer_script.gd` confirmou a importação do streamer e dos meshes do patch de chão.

Também baixei os dois PCKs anunciados pelo manifesto remoto e montei cada um no Godot 4.7.2. Os tamanhos e SHA-256 corresponderam ao manifesto. O pacote INDUSTRIAL expôs seus quatro tiles e 52 peças OBJ; CENTRO expôs quatro tiles e 50 peças. Em ambos, as referências a meshes importados, as colisões por tile e os meshes visual/de colisão do patch de chão foram encontrados e importados. Os builds APK mais recentes do GitHub Actions concluíram com sucesso.

Essas verificações são headless: não demonstram qualidade visual, continuidade perfeita entre tiles, desempenho em um Android específico ou comportamento dos controles na tela. Uma execução headless da cena também registrou três arquivos de áudio Fiat Uno ausentes (`fiat_uno_motor_ligado.wav`, `fiat_uno_acelerando.wav` e `fiat_uno_desacelerando.wav`), uma pendência separada do mapa.

## Pendências para considerar pronto

- Fazer playtest visual e jogável em desktop, conferindo câmera, movimento, streaming, colisões e bordas dos remendos de chão nas duas regiões.
- Instalar o APK atual em aparelho Android e validar download dos PCKs, montagem da região escolhida, controles touch, memória e desempenho.
- Se o objetivo for entregar toda a Liberty City, decidir se os quatro tiles atualmente excluídos devem voltar a ser convertidos e oferecidos como regiões próprias. Isso amplia o escopo atualmente selecionável.

| Item | Estado | Observação |
|---|---|---|
| PCK INDUSTRIAL e CENTRO | Verificados no Godot | Hash/tamanho do manifesto conferidos; tiles e meshes de colisão importados. |
| Isolamento de região | Verificado | O teste de runtime confirmou que CENTRO não solicita tiles INDUSTRIAL. |
| Colisões COL1 e patch do chão | Integrados | O streamer prioriza colisões; os meshes do patch foram importados nos dois PCKs. |
| Transparência e `subglass.txd` | Corrigidos | O streamer detecta alpha e os MTLs usam substitutos RGBA para o TXD truncado. |
| Build APK | Aprovado no CI | O GitHub Actions exportou e verificou APK; isso não comprova instalação em aparelho. |
| Playtest visual desktop/Android | Pendente | Necessário antes de declarar qualidade e desempenho finais. |

Para regenerar as peças runtime e as texturas, execute `python3 tools/split_gta3_obj_surfaces.py --source assets/source/gta3_map/converted_tiles --output assets/maps/liberty_city/godot_tiles --material-limit 96`. Para regenerar as colisões COL1, instale `rwfury` e execute `python3 tools/generate_gta3_col_collision.py --manifest assets/source/gta3_map/map_manifest.json --col-root assets/source/gta3_map --output assets/maps/liberty_city/collisions`. Para reparar o `subglass.txd`, execute `python3 tools/fix_gta3_transparency.py --source-txd assets/source/gta3_map/subglass.txd --mtl-root assets/maps/liberty_city/godot_tiles --texture-root assets/maps/liberty_city/textures --report assets/maps/liberty_city/subglass_repair_report.json`. Para validar os assets, execute `python3 -m unittest tests.test_gta3_map_assets tests.test_map_boundary_protection -v`.

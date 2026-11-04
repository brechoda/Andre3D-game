# Liberty City (GTA III) — estado de integração

## Estado resumido

O jogo integrado oferece atualmente uma única região jogável: **CENTRO**, baixada como PCK externo. Godot 4.7.2 carregou os quatro meshes visuais do PCK de produção e encontrou COL1 sob os seis spawns locais e os seis remotos corrigidos (`global-10`). A validação cobre a integridade técnica do recorte e seus pontos de início, mas não torna a Liberty City inteira pronta: só 4 dos 12 tiles-base estão distribuídos e ainda falta playtest visual/interativo em desktop e Android físico.

## Conteúdo e escopo

A conversão do repositório contém 12 tiles-base, com cerca de 1,46 milhão de triângulos nas malhas originais divididas em 156 peças OBJ/MTL (máximo de 96 materiais por peça). O catálogo espacial também contém dados para overview e props. O PCK CENTRO inclui quatro tiles; os outros oito tiles-base e `maps/overview`/`maps/props` não são oferecidos pelo cliente atual. O kit-fonte `assets/maps/costa_vista` permanece no repositório, mas não é instanciado pelo jogo. Portanto, o recorte atual não representa todos os bairros da Liberty City original.

As peças ficam em `assets/maps/liberty_city/godot_tiles/`; texturas referenciadas pelos MTLs ficam em `assets/maps/liberty_city/textures/`. O patch do chão usa `ground_fix_visual.obj` e `ground_fix_collision.obj`. As colisões COL1 dos setores foram geradas a partir dos modelos-fonte, com faces, caixas e esferas posicionadas pelos IPL.

## Integração no jogo

`scenes/third_person.tscn` instancia `scripts/gta3_map_streamer.gd`. A escolha do menu é gravada na sessão; `ExternalContent` baixa, valida por tamanho e SHA-256, e monta somente o PCK CENTRO. O APK exclui `assets/maps/*`; o PCK fornece os recursos do mapa. O streamer restringe o catálogo aos quatro tiles selecionados, escolhe-os pelos limites espaciais e carrega colisões antes das malhas visuais. O patch de chão é carregado como recurso importado, sem depender de `FileAccess.file_exists()` sobre o OBJ-fonte no APK. Uma barreira física invisível delimita a região; o jogador e Gorece têm recuperação ao cair fora do mapa.

O manifesto local guarda posições de jogador, Gorece e quatro veículos em coordenadas do mapa; o streamer aplica a transformação da cena e sincroniza o chão após teleporte. A configuração de produção antiga (`global-09`) divergia das posições locais: no PCK real, quatro dos seis raios remotos não encontravam chão. A nova versão (`global-10`) foi recalculada pela transformação efetiva do `MapStreamer`; o teste com o PCK servindo em produção confirmou chão sob todos os spawns locais e remotos.

O servidor de atualizações anuncia somente o PCK CENTRO da release `map-v2.2.0-regions`: 62.817.264 bytes, SHA-256 `1ccc94887ffdc3318813cea0896d366dc6373a9705da5a74d79083dcf7caa356`. O cliente atual aceita somente o ID `center`; INDUSTRIAL e ilhas não são opções disponíveis.

O deploy foi confirmado após o commit `0e85bd8` no servidor: `/health` respondeu `ok: true`; o manifesto público `2026.11.04.1` e o `spawn.json` `global-10` estão ativos. O arquivo servido (1.820 bytes; SHA-256 `df0a4b51533c54943a6a55f1feaea5f33977d5baea57e3da7ef76f9272c36bad`) confere com o hash/tamanho do manifesto e publica somente a região `center`.

## Verificações executadas

A suíte `tests.test_gta3_map_assets` e `tests.test_map_boundary_protection` executou 15 testes: 14 passaram e o teste de paridade que exige `assets/source/.../conversion_report.json` foi pulado porque os dados-fonte estão excluídos do checkout público. O teste `test/check_map_region_spawns.gd` montou o PCK publicado, carregou os quatro meshes visuais e verificou COL1 sob seis spawns locais mais os seis remotos fornecidos como terceiro argumento. Os testes de isolamento e importação do streamer também foram executados nas revisões anteriores.

O PCK CENTRO de produção foi baixado do mesmo release listado no manifesto e passou no teste Godot com quatro meshes visuais e 12 raycasts de spawn. O APK público `2.2.8` passou no workflow Android do commit `6f9d506`. Esta correção altera configuração/testes/documentação, não cria uma nova release instalável nem substitui o teste em aparelho.

Essas verificações são headless: não demonstram qualidade visual, continuidade perfeita entre tiles, desempenho em um Android específico ou comportamento dos controles na tela. Um smoke anterior da cena registrou três arquivos de áudio Fiat Uno ausentes (`fiat_uno_motor_ligado.wav`, `fiat_uno_acelerando.wav` e `fiat_uno_desacelerando.wav`), uma pendência separada do mapa que não foi revalidada nesta auditoria.

## Pendências para considerar pronto

- Fazer playtest visual e jogável em desktop na região CENTRO, conferindo câmera, movimento, streaming, colisões e bordas dos remendos de chão.
- Instalar o APK atual em aparelho Android e validar download/montagem do PCK, controles touch, memória e desempenho. O build CI não substitui teste em dispositivo.
- Se o objetivo for a Liberty City completa, converter, integrar e testar os oito tiles-base que não são oferecidos no PCK CENTRO atual.

| Item | Estado | Observação |
|---|---|---|
| PCK CENTRO | Verificado no Godot | 4 meshes visuais; piso COL1 sob os 6 spawns locais e os 6 remotos após o alinhamento. |
| Escopo do mapa | Parcial | Uma região (CENTRO, 4 tiles); os outros 8 tiles-base não estão disponíveis no cliente atual. |
| Colisões COL1 e patch do chão | Integrados | O streamer prioriza colisões; os meshes do patch estão no PCK CENTRO. |
| Transparência e `subglass.txd` | Corrigidos | O streamer detecta alpha e os MTLs usam substitutos RGBA para o TXD truncado. |
| Spawn remoto | Corrigido (`global-10`) | 6 de 6 pontos em produção encontram piso no PCK CENTRO. |
| Build APK | Aprovado no CI anterior | O workflow do commit `6f9d506` passou; o push atual dispara nova execução, sem comprovar instalação em aparelho. |
| Playtest visual desktop/Android | Pendente | Necessário antes de declarar qualidade e desempenho finais. |

Para testar o PCK e o spawn remoto ativo, execute `godot --headless --path . --script res://test/check_map_region_spawns.gd -- <arquivo.pck> center <spawn.json>`. Sem spawn remoto, omita o terceiro argumento. Para exportar novamente, use o preset `Android Map Center`. Para regenerar peças runtime/texturas ou colisões COL1, consulte os comandos existentes abaixo e os assets-fonte locais, que não fazem parte do checkout público. Para validar os assets, execute `python3 -m unittest tests.test_gta3_map_assets tests.test_map_boundary_protection -v`.

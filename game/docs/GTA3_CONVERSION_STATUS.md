# Liberty City (GTA III) — estado da integração

## Conclusão

A integração de **CENTRO** e a geração runtime de colisões para **Level 2** passaram por validações automatizadas headless na branch de fonte. Porém, o APK público `2.2.13` precede os commits de colisão; essa correção ainda não chegou a uma versão pública de produção, portanto Level 2 não está validado para usuários do APK atual. Também **não significa que Liberty City inteira esteja pronta**: o cliente possui quatro dos 12 tiles-base da cidade; os outros oito tiles ainda não estão integrados. Level 2 é um mapa estático externo separado, não os tiles restantes da cidade.

A validação atual cobre dados, seleção de região, streaming por tile, colisões e spawns em Godot headless. Ainda faltam playtest visual/jogável em desktop e instalação/teste em um aparelho Android físico; sem essas verificações, não se deve afirmar que desempenho, transparência, controles touch e aparência estejam aprovados.

## Escopo e implementação

A conversão de Liberty City contém 12 tiles-base, aproximadamente 1,46 milhão de triângulos nas malhas originais, divididos em 156 partes OBJ/MTL (limite de 96 materiais por parte). O pacote CENTRO contém `comnbtm`, `comntop`, `comse` e `comsw`. Os outros oito tiles, `maps/overview` e `maps/props` não estão disponíveis no cliente. O pacote opcional `level2` é uma cena estática distribuída separadamente e não amplia a cobertura de Liberty City. O kit-fonte `assets/maps/costa_vista` também não é uma região selecionável nesta integração.

`scenes/third_person.tscn` instancia `scripts/gta3_map_streamer.gd`. O menu registra a região escolhida; `ExternalContent` baixa e monta somente o PCK da região solicitada. O atualizador valida tamanho e SHA-256. O APK exclui `assets/maps/*`. Para CENTRO, o streamer limita o catálogo aos quatro tiles autorizados, seleciona tiles pelos bounds, carrega colisões antes das meshes visuais e cria uma barreira física invisível. Para Level 2, o cliente gera colisões trimesh em runtime, reutiliza shapes para meshes compartilhadas e exclui meshes de copas/folhagem; o mapa não fica pronto se nenhuma colisão for construída. O patch de chão é carregado pelo caminho do recurso importado, sem depender de `FileAccess.file_exists()` sobre o OBJ-fonte no APK. André e Gorece também têm recuperação contra queda no vazio.

## Correção de spawns

A revisão remota `global-13` e o manifesto interno do PCK CENTRO usam a mesma superfície COL1. André fica em `[184.73, 3.3474, -22.03]` e Gorece em `[185.0, 3.3474, -19.0]`; as coordenadas locais no `map_regions.json` são `[315.33, 18.5474, 52.43]` e `[315.6, 18.5474, 49.4]`. Os quatro veículos também têm posições definidas. O teste compara os spawns locais e remotos e reprova discrepâncias acima de 0,01 m entre coordenadas correspondentes e gaps maiores que 0,75 m em relação ao piso.

O teste com o PCK CENTRO publicado confirmou 12 pontos locais/remotos (seis posições correspondentes) no piso COL1, com gap vertical máximo de `0.000 m`. No Level 2, André `[95, 15, -551]` e Gorece `[100, 15, -551]` foram conferidos contra as colisões construídas pelo método de produção; o gap vertical máximo foi `0.139 m`.

## Distribuição ativa

- PCK CENTRO: release [`map-v2.2.2-spawn-fix`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/map-v2.2.2-spawn-fix), `Andre3D-map-center.pck`, 62.720.388 bytes, SHA-256 `fc38ae751ea53c8795c222436ff7f332916a79eae5086521ced0ba7037cab26e`. O pacote contém somente CENTRO e o manifesto interno atualizado.
- Level 2 opcional e separado: release [`map-v2.2.0-regions`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/map-v2.2.0-regions), `Andre3D-map-level2.pck`, 47.307.196 bytes, SHA-256 `e1bb2dace0787dbc3f0cf4db3baa29d33ca2d2ac4d45e57b447b0c2defc15b62`.
- Manifesto ativo corrigido: [`2026.11.07.1`](https://andre3d-multiplayer-server.onrender.com/updates/manifest.json). Aponta CENTRO ao PCK v2.2.2, mantém Level 2 opcional e preserva o APK 2.2.13. O arquivo de spawn `global-13` tem 1.830 bytes e SHA-256 `9b839af0a1b967a482cb7a5b4d55bfd0b6da322d8a2c311e3b42d7c37ec0253b`. A publicação intermediária declarava incorretamente 1.834 bytes e havia voltado ao PCK CENTRO v2.2.0; ambos os metadados foram corrigidos nesta auditoria.
- Health do servidor: [`/health`](https://andre3d-multiplayer-server.onrender.com/health) respondeu `ok: true`, build `andre3d-mp-v4` após o deploy.
- APK público atual: [`2.2.13`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/apk-v2.2.13), código Android `45`, pacote `com.manus.andre3d.next`; permite baixar Level2, mas antecede a correção das colisões runtime nos commits `1150a53`/`90994e3`. O CI atual passou e gera apenas artefato debug, não atualização assinada de produção. Esta auditoria não publicou outro APK; embora o PCK seja remoto, a geração de colisões depende do código do cliente.

## Verificações executadas

- Testes Python do mapa e limites: 16 testes; 15 aprovados e 1 ignorado porque `assets/source/.../conversion_report.json` não está incluído no repositório público de assets runtime.
- Godot 4.7.2 `--editor --quit --check-only`: sem erros de parse.
- `check_map_region_isolation.gd`: a região CENTRO seleciona apenas seus quatro tiles; o tile do spawn é selecionado pelo método espacial sem iniciar carregamento assíncrono para o teste.
- `check_gta3_map_streamer_script.gd`: streamer instanciado; meshes visuais e de colisão `ground_fix` carregadas.
- `check_map_region_spawns.gd` com CENTRO: ao montar o PCK com substituição dos recursos locais, carregou 50 partes visuais e validou os spawns locais/remotos sobre COL1; máximo `0.000 m`.
- Validação isolada do PCK: quatro tiles CENTRO e cinco meshes de colisão (quatro colisões regionais mais `ground_fix`) carregados sem fallback para os assets do projeto.
- Level 2: o PCK público (`47.307.196` bytes; SHA-256 `e1bb2dace0787dbc3f0cf4db3baa29d33ca2d2ac4d45e57b447b0c2defc15b62`) monta `level2_static.tscn` com 2.556 meshes visuais. O método real `_build_static_region_collisions()` gerou 1.530 formas elegíveis, reutilizando shapes por recurso e filtrando nomes de copas/folhagem. Raycasts dos dois spawns atingiram COL1; máximo `0.139 m`. O teste headless consumiu aproximadamente `399 MB` (`390 MiB`) de RSS de pico no ambiente de validação; isso não prevê desempenho/memória Android, que permanece sem teste físico. A correção ainda não está no APK público 2.2.13.
- Servidor: `node --check`, `npm test` e verificação do manifesto/tamanhos/hashes passaram depois da correção.

Os testes de mapa aqui reportados são headless. **Ainda é necessário** percorrer e inspecionar visualmente CENTRO e Level 2, testar câmera, streaming, transparência de vidro, colisões, desempenho, memória e controles touch em um Android real. Se a meta for Liberty City completa, ainda é necessário integrar os oito tiles ausentes. Um smoke anterior da cena reportou arquivos de áudio Fiat Uno ausentes; é uma pendência separada do mapa e não foi revalidada nesta auditoria.

| Item | Estado | Observação |
|---|---|---|
| PCK CENTRO | Verificado em Godot | 50 partes visuais, cinco malhas de colisão e 12 spawns locais/remotos no piso. |
| Liberty City inteira | Parcial | Somente CENTRO (4/12 tiles-base); faltam oito tiles. |
| Level 2 | Fonte validada headless; release pendente | 1.530 formas geradas em runtime; dois spawns sobre COL1 (máximo `0.139 m`). APK público 2.2.13 ainda não contém a correção; faltam novo APK de produção, playtest visual e Android. |
| Colisões COL1 e patch do chão | Integrados no PCK CENTRO | Colisão é carregada antes da mesh visual. |
| `subglass.txd`/transparência | Assets de substituição presentes | A validação visual ainda depende do playtest desktop/Android. |
| Spawn remoto | Corrigido (`global-13`) | Os 12 pontos locais/remotos ficaram a `0.000 m` do piso. |
| Playtest visual/jogável em desktop | Pendente | Fazer em CENTRO e Level 2; headless não valida aparência, streaming ou controles. |
| Publicação da correção Level2 | Pendente | O CI gera APK debug 2.2.13; é necessário APK de produção assinado que incorpore os commits de colisão antes de usuários receberem a correção. |
| Teste em Android físico | Pendente | Medir especialmente montagem/geração de 1.530 colisões, memória, FPS, controles touch e download remoto. |

Para testar o PCK e o spawn remoto:

```bash
godot --headless --path . --script res://test/check_map_region_spawns.gd -- <arquivo.pck> center <spawn.json>
godot --headless --path . --script res://test/check_map_region_spawns.gd -- <level2.pck> level2
python3 -m unittest tests.test_gta3_map_assets tests.test_map_boundary_protection -v
```

O preset corrigido de exportação chama-se `Android Map Center` (`preset.2`). O projeto Godot editável está em [`brechoda/Andre3D-game`](https://github.com/brechoda/Andre3D-game), diretório `game/`; assets-fonte de conversão excluídos do checkout público não devem ser confundidos com os OBJ/MTL runtime incluídos no projeto.

# Liberty City (GTA III) — estado da integração

## Conclusão

A integração funcional do recorte **CENTRO** foi validada no projeto e o PCK corrigido está ativo no servidor. Isso **não significa que Liberty City inteira esteja pronta**: o cliente possui quatro dos 12 tiles-base da cidade. Os outros oito tiles ainda não estão convertidos/disponibilizados. A opção **Level 2** é um mapa estático externo separado; ela não representa os tiles restantes de Liberty City.

A validação atual cobre dados, seleção de região, streaming por tile, colisões e spawns em Godot headless. Ainda faltam playtest visual/jogável em desktop e instalação/teste em um aparelho Android físico; sem essas verificações, não se deve afirmar que desempenho, transparência, controles touch e aparência estejam aprovados.

## Escopo e implementação

A conversão de Liberty City contém 12 tiles-base, aproximadamente 1,46 milhão de triângulos nas malhas originais, divididos em 156 partes OBJ/MTL (limite de 96 materiais por parte). O pacote CENTRO contém `comnbtm`, `comntop`, `comse` e `comsw`. Os outros oito tiles, `maps/overview` e `maps/props` não estão disponíveis no cliente. O pacote opcional `level2` é uma cena estática distribuída separadamente e não amplia a cobertura de Liberty City. O kit-fonte `assets/maps/costa_vista` também não é uma região selecionável nesta integração.

`scenes/third_person.tscn` instancia `scripts/gta3_map_streamer.gd`. O menu registra a região escolhida; `ExternalContent` baixa e monta somente o PCK da região solicitada. O atualizador valida tamanho e SHA-256. O APK exclui `assets/maps/*`. Para CENTRO, o streamer limita o catálogo aos quatro tiles autorizados, seleciona tiles pelos bounds, carrega colisões antes das meshes visuais e cria uma barreira física invisível. O patch de chão é carregado pelo caminho do recurso importado, sem depender de `FileAccess.file_exists()` sobre o OBJ-fonte no APK. André e Gorece também têm recuperação contra queda no vazio.

## Correção de spawns

A revisão remota `global-13` e o manifesto interno do PCK CENTRO usam a mesma superfície COL1. André fica em `[184.73, 3.3474, -22.03]` e Gorece em `[185.0, 3.3474, -19.0]`; as coordenadas locais no `map_regions.json` são `[315.33, 18.5474, 52.43]` e `[315.6, 18.5474, 49.4]`. Os quatro veículos também têm posições definidas. O teste compara os spawns locais e remotos e reprova discrepâncias acima de 0,01 m entre coordenadas correspondentes e gaps maiores que 0,75 m em relação ao piso.

O teste com o PCK CENTRO publicado confirmou 12 pontos locais/remotos no piso COL1, com gap vertical máximo medido de `0.000 m`.

## Distribuição ativa

- PCK CENTRO: release [`map-v2.2.2-spawn-fix`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/map-v2.2.2-spawn-fix), `Andre3D-map-center.pck`, 62.720.388 bytes, SHA-256 `fc38ae751ea53c8795c222436ff7f332916a79eae5086521ced0ba7037cab26e`. O pacote contém somente CENTRO e o manifesto interno atualizado.
- Level 2 opcional e separado: release [`map-v2.2.0-regions`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/map-v2.2.0-regions), `Andre3D-map-level2.pck`, 47.307.196 bytes, SHA-256 `e1bb2dace0787dbc3f0cf4db3baa29d33ca2d2ac4d45e57b447b0c2defc15b62`.
- Manifesto ativo: [`2026.11.05.5`](https://andre3d-multiplayer-server.onrender.com/updates/manifest.json), commit do servidor [`e97681a`](https://github.com/brechoda/andre3d-multiplayer-server/commit/e97681a). O manifesto aponta CENTRO ao PCK v2.2.2, mantém Level 2 opcional e preserva o APK 2.2.12. O arquivo de spawn `global-13` tem 1.830 bytes e SHA-256 `9b839af0a1b967a482cb7a5b4d55bfd0b6da322d8a2c311e3b42d7c37ec0253b`. A versão anterior do manifesto declarava incorretamente 1.834 bytes; o metadado foi corrigido.
- Health do servidor: [`/health`](https://andre3d-multiplayer-server.onrender.com/health) respondeu `ok: true`, build `andre3d-mp-v4` após o deploy.
- APK público atual: [`2.2.12`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/apk-v2.2.12), código Android `44`, pacote `com.manus.andre3d.next`. Este trabalho não gerou nem assinou um novo APK; o PCK é conteúdo remoto e a atualização do manifesto é independente do APK.

## Verificações executadas

- Testes Python do mapa e limites: 16 testes; 15 aprovados e 1 ignorado porque `assets/source/.../conversion_report.json` não está incluído no repositório público de assets runtime.
- Godot 4.7.2 `--editor --quit --check-only`: sem erros de parse.
- `check_map_region_isolation.gd`: a região CENTRO seleciona apenas seus quatro tiles; o tile do spawn é selecionado pelo método espacial sem iniciar carregamento assíncrono para o teste.
- `check_gta3_map_streamer_script.gd`: streamer instanciado; meshes visuais e de colisão `ground_fix` carregadas.
- `check_map_region_spawns.gd`: ao montar o PCK com substituição dos recursos locais, carregou 50 partes visuais e validou 12 raycasts/spawns sobre COL1; máximo `0.000 m`.
- Validação isolada do PCK: quatro tiles CENTRO e cinco meshes de colisão (quatro colisões regionais mais `ground_fix`) carregados sem fallback para os assets do projeto.
- Servidor: `node --check`, `npm test` e verificação do manifesto/tamanhos/hashes passaram depois da correção.

Os testes são headless. **Ainda é necessário** percorrer e inspecionar visualmente CENTRO, testar câmera, streaming, transparência de vidro, colisões e desempenho, e validar no Android real o download/montagem do PCK, memória e controles touch. Se a meta for Liberty City completa, ainda é necessário integrar os oito tiles ausentes. Um smoke anterior da cena reportou arquivos de áudio Fiat Uno ausentes; é uma pendência separada do mapa e não foi revalidada nesta auditoria.

| Item | Estado | Observação |
|---|---|---|
| PCK CENTRO | Verificado em Godot | 50 partes visuais, cinco malhas de colisão e 12 spawns locais/remotos no piso. |
| Liberty City inteira | Parcial | Somente CENTRO (4/12 tiles-base); faltam oito tiles. |
| Level 2 | Pacote opcional separado | Mapa estático externo; não corresponde à cobertura faltante de Liberty City. |
| Colisões COL1 e patch do chão | Integrados no PCK CENTRO | Colisão é carregada antes da mesh visual. |
| `subglass.txd`/transparência | Assets de substituição presentes | A validação visual ainda depende do playtest desktop/Android. |
| Spawn remoto | Corrigido (`global-13`) | Os 12 pontos locais/remotos ficaram a `0.000 m` do piso. |
| Playtest visual/jogável em desktop | Pendente | Headless não valida aparência, controles nem continuidade visual. |
| Teste em Android físico | Pendente | Build/CI não substitui instalar e jogar em aparelho real. |

Para testar o PCK e o spawn remoto:

```bash
godot --headless --path . --script res://test/check_map_region_spawns.gd -- <arquivo.pck> center <spawn.json>
python3 -m unittest tests.test_gta3_map_assets tests.test_map_boundary_protection -v
```

O preset corrigido de exportação chama-se `Android Map Center` (`preset.2`). O projeto Godot editável está em [`brechoda/Andre3D-game`](https://github.com/brechoda/Andre3D-game), diretório `game/`; assets-fonte de conversão excluídos do checkout público não devem ser confundidos com os OBJ/MTL runtime incluídos no projeto.
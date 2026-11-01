# Andre3D

Projeto Godot 4.7.2 do Andre3D, com cliente Android online, servidor WebSocket, chat de voz por proximidade, atualização remota e otimizações para celulares fracos.

## Versão

`2.1.17`

## Conteúdo

- `game/`: projeto Godot e assets de runtime.
- `server/`: servidor multiplayer e manifesto remoto.
- `android_plugin_src/`: código-fonte dos plugins Android.
- `game/assets/maps/liberty_city/godot_tiles/tile_part_bounds.json`: catálogo espacial das 148 subpartes do mapa.

Os artefatos grandes de distribuição não ficam no histórico Git. Baixe-os na release `online-v2.1.17`:

- APK assinado Andre3D 2.1.17.
- PCK do mapa 2.1.17.
- Template Android `godot-lib.aar`, quando necessário para exportação local.

## Abrir

Abra a pasta `game/` no Godot 4.7.2.stable. Para o servidor, execute `npm ci` e `npm test` dentro de `server/`.

A keystore de release e a senha nunca são armazenadas neste repositório. O APK da release já está assinado.

## Otimização Ultra Baixo

O modo Ultra Baixo usa streaming por subpartes próximas, materiais com filtro nearest, sem anisotropia, iluminação por vértice, GI desativado, colisão somente do setor ativo e menor simulação de NPCs/veículos distantes.

# Andre 3D — mapa CENTRO de Liberty City

## Conteúdo disponível

O mapa de Liberty City disponível no cliente é somente a região **CENTRO**, em um PCK baixado sob demanda: quatro dos 12 tiles-base. Os oito tiles restantes ainda não estão integrados. A opção **Level 2** é um mapa estático externo separado e não completa Liberty City. Na fonte atual, o cliente gera `StaticBody3D`/`CollisionShape3D` a partir das malhas visuais, reutiliza formas de colisão por recurso e filtra copas/folhagem (malhas `ColliderArvore` continuam físicas). A região é recusada se nenhuma colisão puder ser criada. Os dois PCKs passaram validação headless de spawn/colisão, mas os commits dessa correção são posteriores ao APK público 2.2.13; é necessária uma nova versão de produção para que ela chegue a quem usa o APK. Ainda falta playtest visual e em Android. INDUSTRIAL e ilhas não estão disponíveis como regiões de Liberty City.

O APK exclui `assets/maps/*`. Ao entrar em CENTRO, o jogo precisa de internet para baixar o PCK, verificar tamanho e SHA-256 e montá-lo. O manifesto do servidor mantém CENTRO como obrigatório e Level 2 como opcional.

## Versões publicadas

- APK Android: `2.2.13`, código `45`, release [`apk-v2.2.13`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/apk-v2.2.13); contém a correção para baixar a região Level2.
- PCK CENTRO: `Andre3D-map-center.pck`, release [`map-v2.2.2-spawn-fix`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/map-v2.2.2-spawn-fix), 62.720.388 bytes, SHA-256 `fc38ae751ea53c8795c222436ff7f332916a79eae5086521ced0ba7037cab26e`.
- Level 2 (opcional e separado): `Andre3D-map-level2.pck`, release [`map-v2.2.0-regions`](https://github.com/brechoda/andre3d-multiplayer-server/releases/tag/map-v2.2.0-regions).
- Manifesto ativo: [`2026.11.07.1`](https://andre3d-multiplayer-server.onrender.com/updates/manifest.json); spawn remoto `global-13`. André `[184.73, 3.3474, -22.03]` e Gorece `[185.0, 3.3474, -19.0]` aparecem lado a lado na superfície COL1 do Centro.

## Projeto editável

O projeto Godot está no repositório [`brechoda/Andre3D-game`](https://github.com/brechoda/Andre3D-game), branch `main`, na pasta `game/`. Clone o repositório e abra `game/project.godot` com Godot `4.7.2`. Os assets OBJ/MTL runtime do Centro e o código do streamer ficam no projeto; não confundir esses arquivos com os assets originais de conversão, que não fazem parte do checkout público. Para exportar o pacote CENTRO, use o preset `Android Map Center`.

## Validação e pendências

Os PCKs públicos foram baixados e os SHA-256 conferem com as releases. O PCK CENTRO v2.2.2 passou a validação Godot 4.7.2: 50 partes visuais e seis spawns distintos (jogadores e quatro veículos) sobre COL1, com distância vertical máxima `0.000 m`. O PCK Level2 contém 2.556 malhas; o método de produção cria 1.530 formas de colisão elegíveis, reutilizando recursos de malha e filtrando nomes de copas/folhagem. Os dois spawns de personagens atingem COL1 por raycast, com gap máximo de `0.139 m`. O processo headless de validação atingiu cerca de `399 MB` (`390 MiB`) de RSS de pico; isso não substitui medir desempenho/memória em Android.

Para considerar as regiões prontas, primeiro publique um APK de produção que contenha as colisões Level2 e, então, instale-o, conecte à internet, selecione CENTRO e Level 2 e faça playtest visual/jogável com câmera, streaming, transparência, colisões, desempenho e controles touch. A validação visual em desktop e o teste em Android físico ainda estão pendentes. Liberty City completa também depende da integração dos oito tiles que faltam.

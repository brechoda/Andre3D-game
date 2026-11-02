# Correções do chão — Liberty City

Análise do mapa inteiro, só no chão (ruas, terreno, calçadas).

## O que foi feito
1. **Buracos no chão**: ~12 mil m² de buracos cercados de malha foram preenchidos com **terra/grama verde**
   (`assets/maps/liberty_city/ground_fix/ground_fix_visual.obj`, textura `grass_dirt.png`).
   A altura segue o chão vizinho. Áreas de água/sem chão por perto (~8 mil m²) foram **deixadas vazias** de propósito.
2. **Piso invisível** (colisão sem malha): ganhou o mesmo remendo de terra verde.
3. **Chão sem colisão**: criado `collisions/ground_fix_collision.obj` (remendos + chão visível que não tinha colisão),
   registrado em `collision_manifest.json`.
4. **Faces invertidas**: 5 triângulos de chão virados para baixo foram desvirados nos OBJ originais.

## No jogo
O jogo não tem uma cena autônoma `scenes/liberty_city_map.tscn` nem um script `ground_fix_collision.gd`. O visual e a colisão são assets runtime registrados pelo tile especial `ground_fix` em `scripts/gta3_map_streamer.gd`; o streamer instancia o `StaticBody3D` a partir de `collisions/ground_fix_collision.obj`.
Depois de sincronizar os arquivos, abra o projeto Godot 4.7 para reimportar os OBJ novos e os cinco OBJ alterados. No Android, o streamer deve requisitar os caminhos de recursos importados sem depender de `FileAccess.file_exists()` sobre o OBJ-fonte.

## Limites
Correção feita por análise dos dados, sem validação visual dos 12.000 m² remendados. O playtest interativo e a inspeção das bordas ainda são necessários; não marque o mapa como finalizado somente com o smoke test headless ou build APK.

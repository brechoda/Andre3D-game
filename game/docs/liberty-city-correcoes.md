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

## Na cena
`scenes/liberty_city_map.tscn` tem o novo nó `MapRoot/ground_fix` (visual + `StaticBody3D`).
A colisão é criada ao abrir a cena por `scripts/ground_fix_collision.gd`.
Ao abrir no Godot 4.7, deixe reimportar os assets (os OBJ novos e os 5 alterados).

## Limites
Correção feita por análise dos dados (sem renderizar). Confira no editor, principalmente as bordas dos remendos.

# Fiat Uno + Escada (sem braços)

## Status

| Item | Valor |
|------|-------|
| Modelo fonte | `washing.dff` (sem braços) → `fiat_uno_escada.glb` |
| ID multiplayer | `fiatuno_01` |
| Tipo no servidor | `fiatuno` |
| Personagens | André, Gorece e DG (sem restrição) |
| Script | `scripts/fiatuno_controller.gd` |
| Spawn | `[10.0, 2.85, 89.0]`, rotation_y `90` |

Servidor e spawn já estão atualizados. Controlador criado.

## Análise do GLB enviado

Hierarquia principal (compatível com o estilo GTA do projeto):

- `car` → `fiat uno fire`
- Rodas:
  - `wheel_lf` ✅
  - `wheel_lb` ✅
  - `wheel_rb` ✅
  - Roda dianteira direita aparece como nó `wheel` (filho de `wheel_rf_dummy`) — o controlador já trata esse caso
- Portas: `door_lf_ok`, `door_rf_ok`, `door_lr_ok`, `door_rr_ok`
- Assentos: `ped_frontseat`, `ped_backseat`
- Outros: `steering_ok`, `chassis`, `bonnet_ok`, `boot_ok`, `exhaust`, luzes, etc.

**Atenção:** o GLB não embute texturas (`images: 0`). Os materiais existem (`paint_primary`, `glass`, etc.), mas sem texturas o carro pode aparecer só com cores planas. Se precisar de texturas, reexporte o GLB incluindo as imagens ou coloque os PNG no projeto e religue os materiais.

## Como colocar na cena (passo a passo no Godot)

1. **Copie o arquivo**
   ```
   game/assets/models/fiat_uno_escada.glb
   ```

2. **Abra** `scenes/third_person.tscn`

3. **Crie a hierarquia** (igual à Hilux):
   ```
   FiatUno (Node3D)          ← anexe fiatuno_controller.gd aqui
   ├── FiatUnoVisual         ← instância do GLB (ou MeshInstance / PackedScene)
   └── CollisionBody (StaticBody3D)
       └── Collision (CollisionShape3D)  ← BoxShape3D ~ (1.6, 1.3, 3.6)
   ```

4. **No script do FiatUno**:
   - `network_vehicle_id` = `"fiatuno_01"`
   - `vehicle_display_name` = `"FIAT UNO + ESCADA"`

5. **Posição inicial** (ou deixe o spawn remoto sobrescrever):
   - Position ≈ `(10, 2.85, 89)`
   - Rotation Y ≈ `90°`

6. **Ajuste fino depois do primeiro teste**:
   - `SEAT_HIP`, `DOOR_APPROACH`, `WHEEL_RADIUS` no script
   - Altura do nó raiz para as rodas tocarem o chão
   - Tamanho da caixa de colisão

## Testes recomendados

- [ ] Offline: aproximar, botão DIRIGIR aparece, entrar/sair
- [ ] Rodas giram e esterçam
- [ ] Chão do mapa (MapStreamer) mantém o carro no asfalto
- [ ] Online: claim exclusivo, outro jogador vê o movimento
- [ ] DG consegue dirigir (sem bloqueio)

## Referências

- `scripts/hilux_controller.gd` — base do controlador
- `docs/hilux-srx-2017.md` — conversão de rodas e altura
- `docs/vehicle-physics.md`
- Servidor: `VEHICLE_TYPES` + `spawn.json` + manifesto `2026.11.01.14`

## Créditos do modelo

- LFG / Fenix3D / OcelotMods

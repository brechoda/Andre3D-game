# Fiat Uno + Escada (sem braços)

## Status

- **Modelo fonte**: `washing.dff` (versão *sem braços*)
- **ID multiplayer**: `fiatuno_01`
- **Tipo no servidor**: `fiatuno`
- **Personagens permitidos**: André, Gorece e DG (sem restrição)
- **Servidor**: já atualizado (claim + spawn)
- **Spawn**: posição `[10.0, 2.85, 89.0]`, rotation_y `90`

## O que já foi feito no servidor

1. `VEHICLE_TYPES` em `server.mjs` agora inclui `fiatuno_01 → fiatuno`.
2. `updates/files/config/spawn.json` tem a entrada do veículo.
3. Manifesto atualizado (`2026.11.01.14`) com novo size/sha256 do spawn.

## O que ainda falta no cliente Godot

### 1. Converter o DFF → GLB

Use a mesma pipeline da Hilux (`sadler.dff` → `hilux_srx_2017.glb`):

1. Abra o Blender com o addon de importação GTA (DragonFF / INU tools / equivalente).
2. Importe `washing.dff` (versão **sem braços**).
3. Identifique e nomeie as rodas:
   - `wheel_lf`, `wheel_rf`, `wheel_lb`, `wheel_rb`
4. Ajuste altura das rodas para tocar o chão (igual foi feito na Hilux).
5. Exporte como `assets/models/fiat_uno_escada.glb`.

### 2. Criar o controlador

Copie `scripts/hilux_controller.gd` → `scripts/fiatuno_controller.gd` e ajuste:

- `class_name FiatUnoController`
- `network_vehicle_id := "fiatuno_01"`
- `vehicle_display_name := "FIAT UNO + ESCADA"`
- Constantes de física (velocidade máxima ~12–14 m/s, wheelbase, etc.)
- Posições de assento (`SEAT_HIP`, `DOOR_APPROACH`, etc.) conforme o modelo
- Áudio do motor (pode reutilizar o da Hilux temporariamente ou adicionar um novo)

### 3. Adicionar na cena

Em `scenes/third_person.tscn`:

- Instancie o GLB como filho de um nó `FiatUno` (Node3D)
- Anexe o script `fiatuno_controller.gd`
- Configure `network_vehicle_id = "fiatuno_01"`
- Adicione `CollisionBody` + `CollisionShape3D` (caixa simples, igual à Hilux)

### 4. Testes

- Offline: entrar/sair, dirigir, rodas girando, chão do mapa
- Online: claim exclusivo, outro jogador vê o carro se movendo, áudio remoto

## Referências

- `docs/hilux-srx-2017.md` — conversão de rodas e altura
- `docs/vehicle-physics.md` — física procedural
- `scripts/hilux_controller.gd` — base do controlador de carro
- Servidor: `VEHICLE_TYPES` e `vehicle_claim` / `vehicle_release`

## Créditos do modelo

- LFG
- Fenix3D
- OcelotMods

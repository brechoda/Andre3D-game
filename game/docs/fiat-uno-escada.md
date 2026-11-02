# Fiat Uno + Escada

## Integração

| Item | Valor |
|---|---|
| Modelo | `assets/models/fiat_uno_escada.glb` |
| ID multiplayer | `fiatuno_01` |
| Tipo de rede | `fiatuno` |
| Controlador | `scripts/fiatuno_controller.gd` |
| Cena | `scenes/third_person.tscn` |
| Spawn local | `(10.0, 2.85, 89.0)`, rotação Y `90°` |
| Personagens | André, Gorece e DG |

O GLB está instanciado como `FiatUnoVisual` na cena principal. O controlador existente usa as rodas e a porta do modelo, toca os sons do motor, oferece direção por teclado/toque e participa da seleção do GPS. O ID `fiatuno_01` está registrado no cliente e no servidor multiplayer para claims exclusivos.

Áudios importados em `assets/audio/`:

- `fiat_uno_motor_ligado.wav` — marcha lenta em loop.
- `fiat_uno_acelerando.wav` — aceleração em loop.
- `fiat_uno_desacelerando.wav` — desaceleração de execução única.

## Modelo

Hierarquia reconhecida pelo controlador:

- `car` → `fiat uno fire`.
- Rodas: `wheel_lf`, `wheel_lb`, `wheel_rb` e `wheel` (roda dianteira direita dentro de `wheel_rf_dummy`).
- Portas: `door_lf_ok`, `door_rf_ok`, `door_lr_ok`, `door_rr_ok`.
- Outros nós: assentos, `steering_ok`, `chassis`, `bonnet_ok`, `boot_ok`, escape e luzes.

**Texturas:** o GLB fornecido não contém imagens incorporadas (`images: 0`). Os materiais presentes são importados, mas o acabamento pode ficar em cores planas; para texturas detalhadas, será necessário reexportar o modelo com as imagens ou fornecer e religar os mapas de textura.

## Verificações executadas

- Teste Godot `test/test_fiat_uno_integration.gd`: modelo, rodas/porta, três streams de áudio, botões touch, seleção de GPS, identificação multiplayer e proximidade dos três personagens.
- Teste de controles da Hilux/motos: passou após alinhar o teste aos nomes e metadados atuais dos botões touch.
- Suíte do servidor: passou, incluindo autorização e exclusividade do claim do Fiat Uno.

Ajuste visual/físico fino — altura sobre o piso, dimensões da colisão e posição do motorista — ainda pode ser validado manualmente em execução dentro do mapa.

## Créditos do modelo

- LFG / Fenix3D / OcelotMods

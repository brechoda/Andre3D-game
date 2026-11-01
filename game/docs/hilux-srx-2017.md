# Hilux SRX 2017

O arquivo fornecido `sadler.dff` foi convertido tecnicamente para `assets/models/hilux_srx_2017.glb` e adicionado à cena `scenes/third_person.tscn` como o nó `HiluxSRX2017`.

O DFF original trazia uma única malha de roda e quatro dummies (`wheel_lf_dummy`, `wheel_rf_dummy`, `wheel_lb_dummy` e `wheel_rb_dummy`). A conversão reconstrói as quatro rodas independentes como `wheel_lf`, `wheel_rf`, `wheel_lb` e `wheel_rb`.

O controlador aplica rotação contínua às quatro rodas e esterço às duas dianteiras, respeitando a direção da Hilux.

## Correção de rodas

- As quatro rodas foram elevadas para y = -0,30 (centro no arco do paralama); o nó `HiluxSRX2017` na cena fica em y = 0,70, com os pneus tocando o chão.
- As malhas `wheel_lf` e `wheel_lb` foram giradas 180° em Y diretamente na geometria, para o desenho do aro ficar virado para fora. O controlador continua girando e esterçando as rodas normalmente.

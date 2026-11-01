# Entrada e saída da Hilux

Fluxo de entrada do Gorece (`hilux_controller.gd`):

1. Só é possível entrar pelo lado esquerdo do carro (porta do motorista), a até 3 m do ponto de acesso. Do lado errado o botão mostra "VÁ ATÉ A PORTA ESQUERDA".
2. O Gorece caminha até o ponto ao lado da porta, vira para o carro e a porta abre.
3. Ele passa pela porta e senta; o corpo é curvado para a pose de motorista (`SEATED_POSE_DEGREES` em `gorece_npc.gd`): coxas a 80°, joelhos dobrados, tronco levemente inclinado e mãos no volante.
4. A porta fecha e o carro é liberado. Durante a direção a patrulha e a animação de caminhada do Gorece ficam desligadas.
5. Na saída a porta abre, ele levanta, sai pela porta e a porta fecha atrás dele.

A pose sentada é calculada em tempo de execução sobre a pose parada (`IDLE_stance`), porque o modelo do Gorece não traz as animações `CAR_*` do `ped.ifp`. Para usar as animações originais, converta-as com `tools/convert_gore_ifp.py` (precisa de Blender + INU Tools).

Pontos ajustáveis em `hilux_controller.gd`: `SEAT_HIP`, `DOOR_APPROACH`, `DOOR_THRESHOLD_HIP`, `SLIDE_IN_SECONDS`.

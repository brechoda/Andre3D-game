# Física de veículos

A Hilux usa um controlador procedural com aceleração progressiva, frenagem separada, ré limitada, esterço por entre-eixos, redução de esterço em alta velocidade e rolagem visual limitada da carroceria.

As motos usam o mesmo princípio de esterço por entre-eixos, com resposta filtrada, perda de autoridade em alta velocidade, inclinação da moto e animações existentes de pilotagem.

A solução nativa `VehicleBody3D` foi considerada, mas a documentação oficial do Godot informa que ela possui limitações conhecidas e não foi projetada para física 3D realista avançada. Por isso, o projeto mantém controladores próprios, que preservam a integração com os modelos e animações existentes.

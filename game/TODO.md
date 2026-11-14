# O Grande Roubo de Motos — entregas

## Cena 3D Android em terceira pessoa
- Usar exclusivamente o arquivo fornecido `andre.dff` como personagem, realizando somente a conversão técnica necessária para um recurso 3D compatível com Godot.
- Entregar um player controlável em terceira pessoa com câmera acompanhando o personagem.
- Manter um mapa 3D vazio e simples, com apenas uma superfície para movimentação e teste.
- Disponibilizar controles touch básicos e suporte de teclado para teste no desktop.
- Não incluir campanha, inimigos, itens, multiplayer ou sistemas extras.
- Gerar uma versão Android nativa exportada como APK instalável, se o toolchain Android disponível permitir.

## Companheiro seguir o personagem
- Adicionar um botão visível escrito `SEGUIR` que alterna ligar/desligar o acompanhamento do outro personagem.
- Quando o acompanhamento estiver ligado e o personagem ativo se deslocar a pé, o outro personagem deve segui-lo mantendo uma distância curta; ao desligar, o companheiro deve parar de seguir.
- Quando o jogador controlar Gorece e entrar na Hilux, Andre deve procurar uma moto desocupada, montar nela e dirigir atrás da Hilux; se sair da Hilux ou desligar `SEGUIR`, Andre deve deixar de conduzir a moto e só continuar a pé quando o acompanhamento estiver ligado.
- Ao alternar qual personagem é controlado, o companheiro continua sendo o personagem não ativo e segue o personagem ativo.
- Não alterar a condução manual atual da Hilux nem das motos; os veículos usados por um companheiro devem permanecer indisponíveis para outro piloto durante o acompanhamento.

## Nova skin DG
- [x] Adicionar a skin fornecida em `SKIN_COMPLETA.zip` como personagem selecionável, tanto no modo offline quanto no online.
- [x] O personagem DG deve possuir todas as 40 animações presentes no modelo do André, incluindo movimentação, combate e animações de pilotagem/montagem/desmontagem da moto.
- [x] O personagem DG pode montar e pilotar as motos já existentes, usando as animações de piloto do André; não pode montar nem dirigir a Hilux.
- [x] No multiplayer, outros jogadores devem ver a skin DG e receber as animações/estado de veículo correspondentes.

## Rodas visíveis no multiplayer
- [x] Quando outro jogador conduzir a Pop 100, a Wayfarer R1200 ou a Hilux, as rodas do veículo compartilhado devem girar conforme a velocidade recebida pela rede.
- [x] A atualização remota deve ser apenas visual: não deve executar aceleração, colisão nem movimento local duplicado no veículo compartilhado.
- [x] As rodas devem parar de acumular giro quando o veículo estiver parado ou quando o motorista remoto desmontar.

## Mapa Liberty City (GTA III)
- [x] Manter CENTRO como única região selecionável, baixada em PCK; não distribuir INDUSTRIAL nem COSTA VISTA no cliente atual.
- [x] Gerar catálogo espacial de 8.689 posicionamentos; o catálogo runtime atual registra seis conjuntos (quatro tiles CENTRO mais `maps/overview` e `maps/props`), não 12 tiles jogáveis.
- [x] Dividir os seis conjuntos registrados em partes de até 96 materiais/superfícies; as 14 partes `landne` e 24 partes `landsw` presentes no checkout ainda não estão registradas no catálogo de runtime.
- [x] Corrigir os caminhos relativos e preparar os assets runtime para distribuição no PCK regional (os mapas são excluídos do APK principal).
- [x] Conectar o streamer à cena jogável para carregar apenas os tiles Centro da região escolhida, preservando personagens, veículos, multiplayer e controles existentes.
- [x] Alinhar o spawn a uma superfície de estrada do IPL e ampliar o alcance de câmera para a escala da cidade.
- [x] Gerar e aplicar as colisões COL1 originais por tile, incluindo faces, caixas e esferas transformadas pelos posicionamentos IPL.
- [x] Corrigir transparências/máscaras: 280 texturas com alpha são detectadas no runtime e os materiais transparentes usam modo alpha com culling desativado.
- [x] Substituir o `subglass.txd` truncado por texturas RGBA `glassfxsub1`/`glassfxsub2` e atualizar os MTLs dos modelos afetados.
- [x] Executar smoke test desktop headless da cena de terceira pessoa após a importação dos meshes COL1.
- [x] Remover de todos os tiles as árvores (incluindo variantes LOD e sombras), postes de iluminação/telefonia e semáforos, tanto visualmente quanto nas colisões; preservar arbustos baixos, prédios, asfalto e suportes estruturais.
- [x] Distribuir somente o PCK CENTRO, baixado sob demanda e montado apenas após a escolha da região.
- [x] Gerar e validar colisões trimesh experimentais para o PCK Level2 em testes headless; Level2 permanece desativado no produto atual e esses testes históricos não certificam gameplay Android.
- [x] Manter CENTRO como única região aceita pelo atualizador/streamer e único PCK regional publicado nos manifests ativos; sessões antigas Level2 retornam ao Centro.
- [ ] Fazer playtest visual/jogável de CENTRO em desktop e dispositivo Android; raycasts headless não substituem validação de aparência, streaming, controles, FPS e memória.
- [ ] Se Level2 voltar a ser oferecido, revalidar suas colisões e uso de memória em Android físico antes de reativá-lo no menu/manifesto.
- [ ] Se o objetivo for Liberty City completa, reconciliar os oito tiles-base fora do PCK com a lista-fonte: validar e registrar os candidatos `landne`/`landsw`, localizar/reconciliar os demais assets e só então definir spawns, limites, colisões, streaming, PCKs e teste Android.

## Piloto automático e GPS offline
- [x] No modo offline, adicionar um botão de piloto automático para o veículo; ao ativá-lo, o veículo deve seguir a pista sozinho e poder percorrê-la nos dois sentidos, sem remover o controle manual existente.
- [x] Adicionar um minimapa/GPS estilo GTA; permitir marcar um destino no mapa e fazer o veículo seguir a rota pelas ruas até esse destino usando o piloto automático.

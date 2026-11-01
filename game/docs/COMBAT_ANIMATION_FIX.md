# Animações de combate — combo e reação a socos

O botão **DAR SOCO** toca a sequência original de `ped.ifp`:

1. `FightA_1` — primeiro golpe  
2. `FightA_2` — segundo golpe do combo  
3. `FightA_3` — finalizador  

## Controles

- **Toque / clique único**: executa `FightA_1` e volta ao idle.
- **Toques repetidos** (depois de ~28% do clipe atual): avança para o próximo golpe.
- **Segurar o botão**: enfileira automaticamente o próximo golpe assim que a janela de combo abre, até `FightA_3`.

Se `FightA_2` / `FightA_3` não estiverem no modelo, o jogo usa só os clipes disponíveis (fallback seguro para `FightA_1` ou pose procedural).

## Acertar e receber socos

- Cada golpe do combo tenta acertar o personagem oposto no momento de impacto do clipe.
- O golpe só conecta se o alvo estiver a até 1,65 m e dentro do cone frontal do atacante; cada clipe do combo causa no máximo um acerto.
- Andre pode acertar Gorece, e Gorece pode acertar Andre quando cada personagem está sendo controlado.
- Ao receber um golpe, o jogo prioriza a reação direcional IFP correspondente (`HIT_front`, `HIT_back`, `HIT_L`, `HIT_R`) e depois tenta `HitA_1/2/3`.
- Os dois IFPs fornecidos (`assets/source/ped.ifp` e `assets/source/gore/ped.ifp`) contêm as reações genéricas. Elas foram importadas nos GLBs finais `andre_armed_biked.glb` (Andre) e `gorece_rigged.glb` (Gorece); o recuo procedural permanece apenas como fallback se um clipe vier a faltar.
- Não há dano/vida neste fluxo; a alteração cobre contato e animação de reação.

Armas de fogo e disparos foram removidos da jogabilidade; o combate é corpo a corpo.

## Pipeline de importação

O IFP é importado por INU Tools no Blender. O projeto:

1. Converte o DFF + ações necessárias (combo e reações de impacto) para `assets/models/andre_rigged.glb` via `convert_dff_ifp.py`.
2. `tools/merge_ifp_fight_action.py` copia `FightA_1/2/3` para `andre_armed.glb`.
3. `tools/merge_ifp_hit_reactions.py` mescla os clipes de reação em `andre_armed_biked.glb`, o GLB realmente carregado pela cena.
4. `tools/convert_gore_ifp.py` exporta as reações do IFP do Gorece para o GLB-fonte `gorece_ifp_reaction_source.glb`.
5. `tools/merge_gorece_ifp_hit_reactions.py` copia apenas os sete clipes de reação para o GLB original do Gorece. O mesclador preserva os dados binários e as curvas `FightA_1/2/3` existentes, sem reexportá-las pelo Blender.
6. Os dois modelos finais foram reimportados no Godot; o teste exige os sete clipes em ambos e verifica o uso real de uma reação IFP em cada sentido.

### Reconstruir

```sh
INU_TOOLS_PATH=/caminho/para/INU_Tools-GTA-Blender blender -b --python convert_dff_ifp.py
blender -b --python tools/merge_ifp_fight_action.py
blender -b --python tools/merge_ifp_hit_reactions.py
INU_TOOLS_PATH=/caminho/para/INU_Tools-GTA-Blender blender -b --python tools/convert_gore_ifp.py
python3 tools/merge_gorece_ifp_hit_reactions.py
```

Os merges exportam primeiro para um arquivo de staging e substituem o GLB somente após validar as animações esperadas.

## Verificação

```sh
godot --headless --path . --script res://test/test_combat_actions.gd
```

O teste confere o clipe IFP, o deslocamento do punho, a ausência da arma/UI e o recebimento de soco nos dois sentidos.

## Fontes técnicas

- [IFP animation format — GTA Modding Wiki](https://gtamods.com/wiki/IFP)
- [INU Tools for GTA San Andreas](https://github.com/INU-ez/INU_Tools-GTA-Blender)

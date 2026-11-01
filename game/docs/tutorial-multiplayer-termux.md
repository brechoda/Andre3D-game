# Multiplayer gratuito com celular servidor e Termux

Este projeto agora possui uma primeira camada multiplayer: o servidor Node.js cria salas por código, aceita até 8 jogadores e sincroniza a posição básica dos personagens. O cliente Godot cria os jogadores remotos na cena. Motos, Hilux, posse de veículos e física autoritativa entram na próxima etapa.

## Parte A — o que eu já deixei no jogo

- `server/server.mjs`: servidor WebSocket com salas e snapshots.
- `server/package.json`: dependência `ws`.
- `scripts/net/multiplayer_client.gd`: cliente WebSocket do Godot.
- `config/multiplayer.json`: endereço, sala e nome do jogador.
- Nó `OnlineMultiplayer` na cena principal.

O multiplayer fica desligado por padrão para o jogo continuar abrindo offline. Antes de exportar o APK, altere o arquivo `config/multiplayer.json` para `"enabled": true` e informe o endereço público do servidor.

## Parte B — preparar o celular reserva

Use o Termux instalado pelo F-Droid ou pelo GitHub oficial do Termux. Evite versões antigas da Play Store.

No Termux, execute:

```bash
pkg update -y && pkg upgrade -y
pkg install nodejs-lts curl -y
termux-wake-lock
mkdir -p ~/andre3d-server
```

Copie a pasta `server` deste projeto para `~/andre3d-server`. Ela precisa conter `server.mjs` e `package.json`. Depois execute:

```bash
cd ~/andre3d-server
npm install
npm start
```

Você deverá ver:

```text
[andre3d-server] listening on 0.0.0.0:8080 build=andre3d-mp-v1
```

Em outra sessão do Termux, confirme que o servidor está vivo:

```bash
curl http://127.0.0.1:8080/health
```

A resposta deve conter `"ok":true`.

Não feche a sessão que está executando `npm start`. Deixe o celular conectado ao carregador e mantenha o bloqueio de bateria desativado para o Termux.

## Parte C — tornar o servidor acessível de qualquer lugar

O celular normalmente fica atrás do CGNAT da operadora. Por isso, não basta informar o IP do Wi-Fi. Use um túnel público.

Em outra sessão do Termux, execute:

```bash
npx localtunnel --port 8080
```

Na primeira execução, confirme a instalação se o npm perguntar. O comando exibirá algo semelhante a:

```text
your url is: https://algum-nome.loca.lt
```

Guarde esse endereço. Para WebSocket, remova a parte `https://` e use `wss://`, adicionando `/ws` no final:

```text
wss://algum-nome.loca.lt/ws
```

Teste o túnel com:

```bash
curl https://algum-nome.loca.lt/health
```

Se retornar o JSON do servidor, o endereço está público.

O endereço gratuito do localtunnel pode mudar quando o túnel for reiniciado. Quando mudar, será necessário atualizar o endereço no jogo e gerar/distribuir um APK novo. Para testes mais longos, depois podemos trocar para um túnel com endereço fixo.

## Parte D — configurar o jogo antes de exportar o APK

No projeto Godot, abra `config/multiplayer.json` e coloque:

```json
{
  "enabled": true,
  "server_url": "wss://algum-nome.loca.lt/ws",
  "room": "ANDRE3D",
  "player_name": "Jogador"
}
```

Cada pessoa pode usar o mesmo código de sala. Para separar partidas, use códigos diferentes, por exemplo `SALA1` e `SALA2`.

Troque o nome de cada jogador antes de gerar o APK correspondente. O endereço do servidor e o código da sala podem ser iguais para todos.

## Parte E — como testar

1. Inicie `npm start` no celular servidor.
2. Inicie o `localtunnel` em outra sessão.
3. Teste `/health` pelo navegador ou pelo Termux.
4. Configure `multiplayer.json` com `enabled: true` e o endereço `wss://.../ws`.
5. Exporte o APK.
6. Instale o APK em dois celulares.
7. Abra os dois usando o mesmo código de sala.
8. Cada celular deve mostrar o outro personagem na cena.

O status multiplayer aparece no alto da tela, informando se está conectando, conectado à sala ou desconectado.

## Limitações desta primeira etapa

- O servidor mantém salas apenas na memória; se o processo reiniciar, as salas somem.
- O servidor limita cada sala a 8 jogadores.
- Nesta etapa, sincronizamos o personagem a pé.
- A posição ainda é uma sincronização inicial para validar a rede; a próxima etapa deve tornar o servidor autoritativo.
- Motos, Hilux, entrada em veículos, sons e física compartilhada ainda precisam ser sincronizados entre os jogadores.
- O celular servidor precisa permanecer ligado, conectado à internet e com o Termux ativo.

## Reiniciar tudo

No celular servidor:

```bash
cd ~/andre3d-server
npm start
```

Em outra sessão:

```bash
npx localtunnel --port 8080
```

Se o endereço mudar, atualize `server_url` no projeto e gere um novo APK.

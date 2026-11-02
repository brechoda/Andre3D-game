# Andre 3D — mapas externos por região

O APK base não inclui `assets/maps`. O mapa usa pacotes Godot PCK regionais para reduzir o download inicial:

- `Andre3D-map-industrial.pck` — **INDUSTRIAL**, mapa principal e menor pacote medido (baixado automaticamente).
- `Andre3D-map-center.pck` — **CENTRO**, pacote opcional.

Ao abrir o jogo, somente o mapa principal é baixado. No menu, ao escolher CENTRO, o jogo baixa o pacote selecionado, valida o tamanho e o SHA-256 e o monta sem reinstalar o APK. Os pacotes já baixados ficam disponíveis em partidas futuras.

## Android

1. Instale o APK base.
2. Abra o jogo conectado à internet para baixar automaticamente `Andre3D-map-industrial.pck`.
3. Escolha CENTRO no seletor `MAPA DE ENTRADA` para baixá-lo opcionalmente.

Para instalação manual, copie o PCK correspondente para:

```text
Android/data/com.manus.andre3d.next/files/content/
```

O caminho acima corresponde ao `user://content/` do Godot. Em desenvolvimento, por ADB:

```bash
adb push Andre3D-map-industrial.pck /sdcard/Android/data/com.manus.andre3d.next/files/content/
adb push Andre3D-map-center.pck /sdcard/Android/data/com.manus.andre3d.next/files/content/
```

O menu continua funcionando sem os pacotes opcionais. Se CENTRO não estiver instalado, ele só será baixado quando for escolhido.

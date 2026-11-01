# Andre 3D — instalação do mapa externo

O APK leve não inclui `assets/maps`. Para jogar, instale também `Andre3D-map.pck`.

## Android

1. Instale o APK base.
2. Crie a pasta `Android/data/com.manus.andre3d.next/files/content/`.
3. Copie `Andre3D-map.pck` para essa pasta.
4. Abra o jogo novamente.

O caminho acima corresponde ao `user://content/` do Godot. O jogo também aceita o mesmo pacote com extensão `.obb`, mas o conteúdo continua sendo um pacote Godot PCK.

Se o gerenciador de arquivos bloquear `Android/data`, copie primeiro o arquivo para o armazenamento interno do app usando um explorador compatível ou, em desenvolvimento, via ADB:

```bash
adb push Andre3D-map.pck /sdcard/Android/data/com.manus.andre3d.next/files/content/
```

O jogo mostra uma mensagem no menu quando o pacote não foi encontrado. O APK base e o pacote do mapa devem ser distribuídos juntos.

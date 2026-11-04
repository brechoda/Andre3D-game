# Andre 3D — Centro

A versão Android atual oferece somente a região **CENTRO** de Liberty City. INDUSTRIAL e COSTA VISTA não estão disponíveis no menu nem na distribuição remota. O kit-fonte de assets `assets/maps/costa_vista` permanece no repositório, mas não é instanciado nem incluído no APK.

O PCK do Centro é baixado sob demanda, validado pelo manifesto do servidor e montado ao entrar na região. O APK principal exclui `assets/maps/*`.

Arquivo: `Andre3D-map-center.pck`

Release do PCK: `map-v2.2.0-regions` (62.817.264 bytes; SHA-256 `1ccc94887ffdc3318813cea0896d366dc6373a9705da5a74d79083dcf7caa356`).

Manifesto ativo: `https://andre3d-multiplayer-server.onrender.com/updates/manifest.json`. Build Android atual: `2.2.8`; a compilação CI passou, mas ainda é necessário testar download/montagem, controles e desempenho em um aparelho real.

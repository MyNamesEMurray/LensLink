# App Store listing: localized

Every App Store Connect field for the six localizations, translated from
the English listing in [`APP_STORE.md`](APP_STORE.md). Paste each block
into that localization's field. The terms follow the glossary in
[`LOCALIZATION.md`](LOCALIZATION.md), and the app's own labels are
quoted exactly as its translations show them. Keywords never repeat the
words of the name or subtitle, which search already matches.

Keep this file in step with `APP_STORE.md`: when the English listing
changes, the translations here change with it. Release notes are per
version; the ones here are for 1.17.0.

**Name:** LensLink Camera in every localization (the brand is not
translated).

**Spanish:** use the Spanish (Mexico) localization: the app's Spanish
is Latin American. If Spanish (Spain) is added too, paste the same text
with these changes: subtitle `Cámara del móvil para OBS`; "computadora"
→ "ordenador" (promotional text and description); "video" → "vídeo" and
"mantén presionado" → "mantén pulsado" (description; in What's New,
"presionada" and "mantenlo presionado" become "pulsada" and "mantenlo
pulsado").

The French text carries no-break spaces before colons and inside « »,
as French typography requires; keep them when pasting.

## German (Deutsch)

**Subtitle:**

```text
Handykamera für OBS Studio
```

**Promotional text:**

```text
Streame die Kamera deines iPhone oder iPad per WLAN oder USB zu OBS Studio: bis 4K60, HEVC, 10-Bit-HDR, mit Live-Steuerung von deinem Computer aus.
```

**Keywords:**

```text
webcam,streaming,virtuelle,4k,hevc,hdr,usb,wlan,aufnahme,livestream,übertragung,video,smartphone
```

**Description:**

```text
LensLink Camera macht dein iPhone oder iPad zur Kamera für OBS Studio. Smartphone befestigen, App öffnen, und schon erscheint es in OBS als Videoquelle, per WLAN oder USB-Kabel, mit der Bildqualität, die die Kamera deines Smartphones tatsächlich liefern kann.

Das Bild zuerst
Bis 4K mit 60 fps, HEVC oder H.264, dazu 120 und 240 fps, wo die Kamera sie bietet
10-Bit-HDR (HLG) und Apple Log auf unterstützten Geräten
Qualität „Ausgewogen“ oder „Maximal“: „Maximal“ findet heraus, wie viel deine Verbindung tragen kann
Jedes Objektiv, mit den Objektivtasten der Kamera-App

Bedienung, die nicht im Weg ist
Tippen zum Fokussieren, halten, um Fokus und Belichtung an eine Stelle zu heften, ziehen für die Helligkeit, mit zwei Fingern zoomen
Eine Einstellleiste für Fokus, Weißabgleich, Belichtung, ISO und Verschluss, mit Autofokus, der Gesichter bevorzugt
Dieselben Bedienelemente im Browser-Steuerfeld auf deinem Computer und direkt in OBS
Kameraeinstellungen merken: Ein einmal eingestelltes Bild bleibt eingestellt

Für die Produktion gemacht
Fernstart: Scharf schalten, und OBS startet die Kamera für dich
Tally-Licht: Ein farbiger Rahmen zeigt, wann du auf Sendung bist
Pausieren mit einem Standbild statt eines eingefrorenen Bildes
Streamt auf iPads, die es unterstützen, neben anderen Apps weiter
Automatische Lippensynchronität: Das Plugin misst die Latenz und gleicht dein echtes Mikrofon an
Virtueller Greenscreen, direkt auf dem Smartphone
Spiegle deinen ganzen Bildschirm samt App-Ton
Siri und Kurzbefehle

Privat von Grund auf
Auf dem Smartphone wird nichts aufgezeichnet, und nichts verlässt dein lokales Netzwerk. Kein Konto, keine Anmeldung, keine Analysedaten.

Erfordert OBS Studio und das kostenlose Open-Source-Plugin LensLink für Mac, Windows oder Linux: https://lenslink.cam
```

**What's New (1.17.0):**

```text
Mehr Kontrolle über Fokus, Belichtung und Weißabgleich, und eine aufgeräumtere Bedienung.

• Weißabgleich auf weißem Papier kalibrieren: Tippe beim WA-Chip auf die Pipette und dann im Bild auf das Papier. Das korrigiert auch den Grün- oder Magentastich von LED- und Leuchtstofflampen.
• Auf iPhones mit 48-MP-Hauptkamera nutzt eine 2×-Objektivtaste die volle Detailschärfe des Sensors.
• Halte den Finger auf dem Bild, um Fokus und Belichtung an diese Stelle des Bildausschnitts zu heften: Wohin du das Smartphone auch richtest, sie passen sich weiter an das an, was dort ist, bis ein Tippen ins Bild sie löst.
• Das Schloss in der Einstellleiste sperrt die gewählte Einstellung auf dem Wert, den die Automatik gerade nutzt. Halte es gedrückt, um alles zu sperren oder zu entsperren.
• Natürliche Bewegungsunschärfe, standardmäßig an: Die Belichtungsautomatik hält den Verschluss bei der halben Bilddauer oder schneller (1/60 bei 30 fps) und erhöht bei wenig Licht lieber die ISO, als Bewegungen zu verwischen. Ausschalten kannst du sie in den Optionen oder mit der Taste beim Verschl.-Chip.
• Die Einstellleiste hat die Chips Fokus, WA, EV, ISO und Verschl., und die Regler für EV, ISO und Verschluss rasten in Stufen ein.
• Der Zoom wandert in die Objektivreihe: Tippe auf die gelbe Objektivtaste für einen Zoomregler und erneut, um den Zoom zurückzusetzen.
• Der Greenscreen hat eine eigene Taste neben den Objektivtasten. Halte sie gedrückt, um den Greenscreen ein- oder auszuschalten; wo die Tiefenunterstützung läuft, öffnet ein Tippen den Motiv-Regler.
• Der Motiv-Abstand startet jetzt auf Auto und hält die Grenze knapp hinter dir.
• Der Greenscreen zeigt, wo die Tiefenunterstützung wirkt: Die Zeile Greenscreen und die Format-Menüs markieren sie mit Tiefe, und die Motiv-Taste wird gepunktet, solange sie läuft. Der Zoom tritt dann zurück, weil die Kamera mit Tiefe nicht zoomen kann.
• Die Optionen sind in Kamera, Live-Bildschirm, Fernstart und Erweitert gegliedert, und die Computer-Karte zeigt jetzt einfach OBS verbunden, Bereit oder Scharf geschaltet.
• Aktualisiere auch das OBS-Plugin auf 1.17.0: Das Browser-Steuerfeld bekommt die Weißabgleich-Kalibrierung, die natürliche Bewegungsunschärfe und den automatischen Motiv-Abstand.
```

## Spanish, Mexico (Español)

**Subtitle:**

```text
Cámara del celular para OBS
```

**Promotional text:**

```text
Transmite la cámara de tu iPhone o iPad a OBS Studio por Wi-Fi o USB: hasta 4K60, HEVC y HDR de 10 bits, con controles en vivo desde tu computadora.
```

**Keywords:**

```text
webcam,streaming,transmisión,virtual,4k,hevc,hdr,usb,wifi,captura,en vivo,directo,video,móvil,live
```

**Description:**

```text
LensLink Camera convierte tu iPhone o iPad en una cámara para OBS Studio. Monta el teléfono, abre la app y aparecerá en OBS como fuente de video por Wi-Fi o con un cable USB, con la calidad de imagen que la cámara del teléfono realmente puede ofrecer.

La imagen, primero
Hasta 4K a 60 fps, HEVC o H.264, con 120 y 240 fps donde la cámara los ofrece
HDR de 10 bits (HLG) y Apple Log en dispositivos compatibles
Calidad Equilibrada o Máxima: Máxima encuentra lo máximo que tu conexión puede transmitir
Todas las lentes, con los botones de lente de la app Cámara

Controles que no estorban
Toca para enfocar, mantén presionado para fijar el enfoque y la exposición en un punto, arrastra para ajustar el brillo, pellizca para hacer zoom
Una sola bandeja de ajustes para enfoque, balance de blancos, exposición, ISO y obturador, con autoenfoque que prioriza los rostros
Los mismos controles en un panel del navegador en tu computadora, y en el propio OBS
Recordar ajustes de cámara: una toma ajustada una vez se queda así

Hecha para producción
Inicio remoto: ármalo y OBS inicia la cámara por ti
Luz tally: un borde de color indica cuándo estás al aire
Pausa con una imagen fija en lugar de un cuadro congelado
Sigue transmitiendo junto a otras apps en los iPad compatibles
Sincronía labial automática: el plugin mide la latencia y alinea tu micrófono real
Pantalla verde virtual, directamente en el teléfono
Duplica toda tu pantalla con el audio de las apps
Siri y Atajos

Privada por diseño
No se graba nada en el teléfono y nada sale de tu red local. Sin cuenta, sin inicio de sesión, sin analíticas.

Requiere OBS Studio y el plugin LensLink, gratuito y de código abierto, para Mac, Windows o Linux: https://lenslink.cam
```

**What's New (1.17.0):**

```text
Más control sobre el enfoque, la exposición y el balance de blancos, y controles más ordenados.

• Calibra el balance de blancos con papel blanco: toca el cuentagotas en el chip WB y luego toca el papel en la imagen. También corrige el tono verde o magenta de las luces LED y fluorescentes.
• En los iPhone con cámara principal de 48 MP, un botón de lente 2× aprovecha todo el detalle del sensor.
• Mantén presionada la imagen para fijar el enfoque y la exposición en esa zona del encuadre: apuntes donde apuntes el teléfono, siguen ajustándose a lo que haya ahí, hasta que un toque en la imagen los libera.
• El candado de la bandeja de ajustes bloquea el ajuste seleccionado en lo que el modo automático hace en ese momento. Mantenlo presionado para bloquear o desbloquear todo.
• Desenfoque de movimiento natural, activado de forma predeterminada: la exposición automática mantiene el obturador a la mitad del intervalo entre fotogramas o más rápido (1/60 a 30 fps) y, con poca luz, sube el ISO en lugar de difuminar el movimiento. Desactívalo en Opciones o con el botón del chip Obtur.
• La bandeja tiene los chips Enfoque, WB, EV, ISO y Obtur., y los diales de EV, ISO y obturador avanzan por pasos.
• El zoom pasa a la fila de lentes: toca el botón de lente amarillo para abrir un dial de zoom, y vuelve a tocarlo para restablecer el zoom.
• La pantalla verde tiene su propio botón junto a los botones de lente. Mantenlo presionado para activar o desactivar la pantalla verde; donde funciona la asistencia de profundidad, un toque abre el dial Sujeto.
• La distancia del sujeto ahora empieza en Auto, que mantiene el límite justo detrás de ti.
• La pantalla verde indica dónde funciona la asistencia de profundidad: la fila Pantalla verde y los menús de Formato la marcan con Profundidad, y el botón Sujeto se vuelve de puntos mientras está activa. El zoom se oculta entonces, porque la cámara no puede hacer zoom con profundidad.
• Las opciones se agrupan en Cámara, Pantalla En vivo, Inicio remoto y Avanzado, y la tarjeta de la computadora ahora dice simplemente OBS conectado, Listo o Armado.
• Actualiza también el plugin de OBS a 1.17.0: su panel de control en el navegador incorpora la calibración del balance de blancos, el desenfoque de movimiento natural y la distancia del sujeto en Auto.
```

## French (Français)

**Subtitle:**

```text
Caméra de téléphone pour OBS
```

**Promotional text:**

```text
Diffusez la caméra de votre iPhone ou iPad vers OBS Studio en Wi-Fi ou en USB : jusqu’à 4K60, HEVC, HDR 10 bits, avec des commandes en direct depuis votre ordinateur.
```

**Keywords:**

```text
webcam,streaming,virtuelle,4k,hevc,hdr,usb,wifi,capture,direct,diffusion,vidéo,smartphone,portable
```

**Description:**

```text
LensLink Camera transforme votre iPhone ou iPad en caméra pour OBS Studio. Fixez le téléphone, ouvrez l’app, et il apparaît dans OBS comme source vidéo, en Wi-Fi ou par câble USB, avec la qualité d’image dont sa caméra est réellement capable.

L’image avant tout
Jusqu’à la 4K à 60 fps, en HEVC ou H.264, avec 120 et 240 fps quand la caméra les propose
HDR 10 bits (HLG) et Apple Log sur les appareils compatibles
Qualité Équilibrée ou Maximale : Maximale trouve le débit le plus élevé que votre connexion peut tenir
Tous les objectifs, avec les boutons d’objectif de l’app Appareil photo

Des commandes qui se font oublier
Touchez pour faire la mise au point, maintenez pour épingler la mise au point et l’exposition à un endroit, faites glisser pour la luminosité, pincez pour zoomer
Un seul tiroir de réglages pour la mise au point, la balance des blancs, l’exposition, l’ISO et l’obturateur, avec un autofocus qui privilégie les visages
Les mêmes commandes dans un panneau web sur votre ordinateur, et dans OBS lui-même
Mémoriser les réglages de la caméra : un plan réglé une fois le reste

Conçue pour la production
Démarrage à distance : armez-le, et OBS démarre la caméra pour vous
Voyant tally : une bordure colorée indique quand vous êtes à l’antenne
Mise en pause avec une image d’attente plutôt qu’une image gelée
Continue de diffuser à côté d’autres apps sur les iPad compatibles
Synchronisation labiale automatique : le plugin mesure la latence et aligne votre vrai micro
Écran vert virtuel, directement sur le téléphone
Recopie de tout l’écran avec le son des apps
Siri et Raccourcis

Confidentialité dès la conception
Rien n’est enregistré sur le téléphone, et rien ne quitte votre réseau local. Pas de compte, pas de connexion, pas de statistiques d’utilisation.

Nécessite OBS Studio et le plugin LensLink, gratuit et open source, pour Mac, Windows ou Linux : https://lenslink.cam
```

**What's New (1.17.0):**

```text
Plus de contrôle sur la mise au point, l’exposition et la balance des blancs, et des commandes plus claires.

• Calibrez la balance des blancs sur une feuille blanche : touchez la pipette de la puce BB, puis touchez le papier dans l’image. Cela corrige aussi la dominante verte ou magenta des éclairages LED et fluorescents.
• Sur les iPhone dotés d’une caméra principale de 48 Mpx, un bouton d’objectif 2× exploite tout le détail du capteur.
• Maintenez le doigt sur l’image pour épingler la mise au point et l’exposition à cette zone du cadre : où que vous pointiez le téléphone, elles continuent de s’ajuster à ce qui s’y trouve, jusqu’à ce qu’un toucher sur l’image les libère.
• Le cadenas du tiroir de réglages verrouille le réglage sélectionné sur ce que fait l’automatique à cet instant. Maintenez-le pour tout verrouiller ou tout déverrouiller.
• Flou de mouvement naturel, activé par défaut : l’exposition automatique garde une vitesse d’au moins la moitié de l’intervalle entre images (1/60 à 30 fps) et monte l’ISO en faible lumière plutôt que d’étaler le mouvement. Désactivez-le dans Options ou avec le bouton de la puce Vitesse.
• Le tiroir propose les puces MAP, BB, EV, ISO et Vitesse, et les molettes EV, ISO et Vitesse avancent par crans.
• Le zoom passe dans la rangée d’objectifs : touchez le bouton d’objectif jaune pour une molette de zoom, et touchez-le de nouveau pour réinitialiser le zoom.
• L’écran vert a son propre bouton à côté des boutons d’objectif. Maintenez-le pour activer ou désactiver l’écran vert ; là où l’assistance profondeur fonctionne, un toucher ouvre la molette Sujet.
• La distance du sujet démarre désormais en Auto, qui garde le seuil juste derrière vous.
• L’écran vert indique où l’assistance profondeur fonctionne : la ligne Écran vert et les menus Format la signalent par Profondeur, et le bouton Sujet passe en pointillés pendant qu’elle tourne. Le zoom s’efface alors, car la caméra ne peut pas zoomer avec la profondeur.
• Les options sont regroupées en Caméra, Écran de direct, Démarrage à distance et Avancé, et la carte de l’ordinateur affiche désormais simplement OBS connecté, Prêt ou Armé.
• Mettez aussi à jour le plugin OBS en 1.17.0 : son panneau de contrôle web reçoit la calibration de la balance des blancs, le flou de mouvement naturel et la distance du sujet en Auto.
```

## Japanese (日本語)

**Subtitle:**

```text
OBS Studio用スマホカメラ
```

**Promotional text:**

```text
iPhoneやiPadのカメラを、Wi-FiまたはUSBでOBS Studioにストリーミング。最大4K60、HEVC、10ビットHDRに対応し、コンピュータからライブで操作できます。
```

**Keywords:**

```text
ウェブカメラ,webカメラ,配信,ライブ配信,仮想カメラ,4k,hevc,hdr,usb,wifi,キャプチャ,ストリーミング,生配信,実況,ビデオ
```

**Description:**

```text
LensLink Cameraは、iPhoneやiPadをOBS Studio用のカメラにします。スマートフォンを固定してアプリを開くだけで、Wi-FiまたはUSBケーブル経由でOBSにビデオソースとして表示されます。画質は、スマートフォンのカメラ本来の実力そのままです。

まずは画質
最大4K・60 fps、HEVCまたはH.264。カメラが対応していれば120 fpsと240 fpsも使えます
対応デバイスでは10ビットHDR（HLG）とApple Log
画質は「バランス」と「最高」から選択。「最高」は接続が送れる上限を自動で見つけます
すべてのレンズを、カメラAppと同じレンズボタンで

じゃまにならない操作
タップでフォーカス、長押しでフォーカスと露出をその位置に固定、ドラッグで明るさ調整、ピンチでズーム
フォーカス、ホワイトバランス、露出、ISO、シャッターをまとめた調整トレイ。顔を優先するオートフォーカス付き
同じ操作項目を、コンピュータのブラウザパネルやOBS内でも
カメラ設定を記憶：一度決めた設定はそのまま

本番のための機能
リモート開始：有効にすると、OBSがカメラを開始
タリーランプ：色付きの枠でオンエア中かどうかがわかります
一時停止中は、固まった映像ではなく一時停止用の静止画を表示
対応するiPadでは、ほかのアプリと並べてもストリーミングを継続
自動リップシンク：プラグインが遅延を測定し、実際に使っているマイクとタイミングを合わせます
スマートフォン上で動作するバーチャルグリーンバック
アプリの音声ごと、画面全体をミラーリング
Siriとショートカット

プライバシーを最優先に設計
スマートフォンには何も録画されず、データがローカルネットワークの外に出ることもありません。アカウント不要、サインイン不要、アナリティクスもありません。

OBS Studioと、Mac、Windows、Linux用の無料のオープンソースLensLinkプラグインが必要です：https://lenslink.cam
```

**What's New (1.17.0):**

```text
フォーカス、露出、ホワイトバランスをより細かく操作できるようになり、操作画面もすっきりしました。

• 白い紙でホワイトバランスをキャリブレーション：WBのチップでスポイトをタップし、映像の中の紙をタップします。LEDや蛍光灯による緑やマゼンタの色かぶりも補正されます。
• 48MPのメインカメラを搭載したiPhoneでは、2×のレンズボタンでセンサーの細部まで生かせます。
• 映像を長押しすると、フォーカスと露出を画面内のその位置に固定します。スマートフォンをどこに向けても、その位置に映るものに合わせて調整し続け、映像をタップすると解除されます。
• 調整トレイのロックボタンをタップすると、選択中の設定を自動が今使っている値で固定します。長押しすると、すべての設定をまとめてロックまたは解除します。
• 自然なモーションブラー（初期設定でオン）：自動露出でシャッター速度をフレーム間隔の半分以上の速さ（30fpsで1/60）に保ち、暗い場所では動きをぶれさせずにISOを上げます。オプション、またはSSのチップのボタンでオフにできます。
• 調整トレイのチップはピント、WB、EV、ISO、SSになり、EV、ISO、SSのダイヤルは段階ごとに止まるようになりました。
• ズームはレンズボタンの列に移りました。黄色のレンズボタンをタップするとズームダイヤルが開き、もう一度タップするとズームがリセットされます。
• グリーンバック専用のボタンがレンズボタンの横に加わりました。長押しでグリーンバックのオン/オフを切り替えます。深度アシストが動作しているときは、タップで被写体ダイヤルが開きます。
• 被写体の距離は自動で始まるようになり、カットオフをあなたのすぐ後ろに保ちます。
• 深度アシストが使える場所がわかるようになりました。グリーンバックの行とフォーマットのメニューに「深度」と表示され、動作中は被写体ボタンがドット表示になります。深度の使用中はカメラがズームできないため、ズームは表示されません。
• オプションがカメラ、ライブ画面、リモート開始、詳細にまとまり、コンピュータのカードは「OBS接続済み」「準備完了」「リモート開始有効」とシンプルに表示されます。
• OBSプラグインも1.17.0にアップデートしてください。ブラウザコントロールパネルで、ホワイトバランスのキャリブレーション、自然なモーションブラー、被写体の距離の自動が使えるようになります。
```

## Portuguese, Brazil (Português do Brasil)

**Subtitle:**

```text
Câmera de celular para o OBS
```

**Promotional text:**

```text
Transmita a câmera do seu iPhone ou iPad para o OBS Studio por Wi-Fi ou USB: até 4K60, HEVC e HDR de 10 bits, com controles ao vivo pelo computador.
```

**Keywords:**

```text
webcam,streaming,transmissão,virtual,4k,hevc,hdr,usb,wifi,captura,ao vivo,vídeo,smartphone,espelhar
```

**Description:**

```text
O LensLink Camera transforma seu iPhone ou iPad em uma câmera para o OBS Studio. Prenda o celular, abra o app e ele aparece no OBS como fonte de vídeo por Wi-Fi ou por cabo USB, com a qualidade de imagem que a câmera do celular realmente consegue entregar.

Imagem em primeiro lugar
Até 4K a 60 fps, HEVC ou H.264, com 120 e 240 fps quando a câmera oferece
HDR de 10 bits (HLG) e Apple Log em dispositivos compatíveis
Qualidade Equilibrada ou Máxima: a Máxima descobre o máximo que a sua conexão aguenta
Todas as lentes, com os botões de lente do app Câmera

Controles que não atrapalham
Toque para focar, mantenha pressionado para fixar foco e exposição em um ponto, arraste para o brilho, faça pinça para dar zoom
Uma só bandeja de ajustes para foco, equilíbrio de branco, exposição, ISO e obturador, com foco automático que prioriza rostos
Os mesmos controles em um painel no navegador do seu computador, e no próprio OBS
Memorizar ajustes da câmera: uma cena ajustada uma vez continua ajustada

Feito para produção
Início remoto: arme e o OBS inicia a câmera para você
Luz tally: uma borda colorida mostra quando você está no ar
Pausa com uma imagem de espera em vez de um quadro congelado
Continua transmitindo ao lado de outros apps nos iPads compatíveis
Sincronia labial automática: o plugin mede a latência e alinha o seu microfone de verdade
Tela verde virtual, direto no celular
Espelhe a tela inteira com o áudio dos apps
Siri e Atalhos

Privado desde a concepção
Nada é gravado no celular, e nada sai da sua rede local. Sem conta, sem login, sem análises.

Requer o OBS Studio e o plugin LensLink, gratuito e de código aberto, para Mac, Windows ou Linux: https://lenslink.cam
```

**What's New (1.17.0):**

```text
Mais controle sobre foco, exposição e equilíbrio de branco, e controles mais organizados.

• Calibre o equilíbrio de branco com papel branco: toque no conta-gotas no chip WB e depois toque no papel na imagem. Isso também corrige o tom verde ou magenta de luzes LED e fluorescentes.
• Nos iPhones com câmera principal de 48 MP, um botão de lente 2× aproveita todo o detalhe do sensor.
• Mantenha pressionada a imagem para fixar o foco e a exposição naquela área do enquadramento: para onde quer que você aponte o celular, eles continuam se ajustando ao que estiver ali, até que um toque na imagem os libere.
• O cadeado da bandeja de ajustes trava o ajuste selecionado no que o automático está fazendo agora. Mantenha pressionado para travar ou destravar tudo.
• Desfoque de movimento natural, ligado por padrão: a exposição automática mantém o obturador em metade do intervalo entre quadros ou mais rápido (1/60 a 30 fps) e, com pouca luz, aumenta o ISO em vez de borrar o movimento. Desligue em Opções ou no botão do chip Obtur.
• A bandeja tem os chips Foco, WB, EV, ISO e Obtur., e os dials de EV, ISO e obturador avançam em passos.
• O zoom foi para a fileira de lentes: toque no botão de lente amarelo para abrir um dial de zoom, e toque de novo para redefinir o zoom.
• A tela verde ganhou um botão próprio ao lado dos botões de lente. Mantenha pressionado para ligar ou desligar a tela verde; onde a assistência de profundidade funciona, um toque abre o dial Assunto.
• A distância do assunto agora começa no Auto, que mantém o limite logo atrás de você.
• A tela verde mostra onde a assistência de profundidade funciona: a linha Tela verde e os menus de Formato a marcam com Profundidade, e o botão Assunto fica pontilhado enquanto ela está ativa. O zoom some nessa hora, porque a câmera não consegue dar zoom com profundidade.
• As opções estão agrupadas em Câmera, Tela Ao vivo, Início remoto e Avançado, e o cartão do computador agora diz apenas OBS conectado, Pronto ou Armado.
• Atualize também o plugin do OBS para a 1.17.0: o painel de controle no navegador ganha a calibração do equilíbrio de branco, o desfoque de movimento natural e a distância do assunto no Auto.
```

## Chinese, Simplified (简体中文)

**Subtitle:**

```text
适用于 OBS Studio 的手机摄像头
```

**Promotional text:**

```text
通过 Wi-Fi 或 USB 将 iPhone 或 iPad 的摄像头画面传输到 OBS Studio：最高 4K60、HEVC、10 位 HDR，还能在电脑上实时控制。
```

**Keywords:**

```text
网络摄像头,直播,推流,虚拟摄像头,4k,hevc,hdr,usb,wifi,采集,相机,录屏,串流,视频,投屏
```

**Description:**

```text
LensLink Camera 可以把你的 iPhone 或 iPad 变成 OBS Studio 的摄像头。固定好手机，打开 App，它就会通过 Wi-Fi 或 USB 线作为视频来源出现在 OBS 中，画质就是手机摄像头真正能达到的水平。

画质优先
最高 4K 60 fps，支持 HEVC 或 H.264；摄像头支持时还可使用 120 fps 和 240 fps
在支持的设备上提供 10 位 HDR（HLG）和 Apple Log
画质可选“均衡”或“最高”：“最高”会找出你的连接所能承载的上限
每一颗镜头都能用，镜头按钮与相机 App 相同

不碍事的控制
轻点对焦，按住把对焦和曝光固定在该位置，拖动调节亮度，双指捏合变焦
一个调节栏集中对焦、白平衡、曝光、ISO 和快门，并提供人脸优先的自动对焦
同样的控制项也出现在电脑上的浏览器面板中，以及 OBS 里
记住摄像头设置：调好一次，就一直保持

为制作而生
远程启动：开启后，由 OBS 启动摄像头
Tally 灯：彩色边框提示你是否正在播出
暂停时显示暂停画面，而不是卡住的画面
在支持的 iPad 上，与其他 App 并排使用时也能继续推流
自动音画同步：插件测量延迟，并让你实际使用的麦克风与画面对齐
虚拟绿幕，直接在手机上完成
连同 App 声音一起镜像整个屏幕
Siri 与快捷指令

隐私至上的设计
手机上不会录制任何内容，也没有任何数据离开你的本地网络。无需账户，无需登录，没有数据分析。

需要 OBS Studio 以及适用于 Mac、Windows 或 Linux 的免费开源 LensLink 插件：https://lenslink.cam
```

**What's New (1.17.0):**

```text
对焦、曝光和白平衡的控制更细致，操作界面也更简洁。

• 用白纸校准白平衡：在“白平衡”按钮下轻点吸管，再轻点画面中的白纸。LED 灯和荧光灯带来的偏绿或偏洋红也能一并校正。
• 在配备 4800 万像素主摄的 iPhone 上，新的 2× 镜头按钮可发挥传感器的全部细节。
• 按住画面可把对焦和曝光固定在画面的该区域：无论手机指向哪里，都会持续针对该区域里的内容调整，直到轻点画面将其解除。
• 调节栏新增锁按钮：轻点会把所选设置固定在自动当前使用的值；按住可一次锁定或解锁全部设置。
• 自然动态模糊，默认开启：自动曝光将快门保持在帧间隔的一半或更快（30 fps 时为 1/60），光线暗时提高 ISO，而不是让动作拖影。可在“选项”中或用“快门”按钮下的按钮关闭。
• 调节栏的按钮改为“对焦”“白平衡”“EV”“ISO”“快门”，EV、ISO 和快门转盘会按档位停顿。
• 变焦移到了镜头按钮一行：轻点黄色的镜头按钮打开变焦转盘，再次轻点即可重置变焦。
• 绿幕在镜头按钮旁有了专属按钮。按住可开启或关闭绿幕；深度辅助运行时，轻点可打开“主体”转盘。
• “主体”距离现在默认为自动，会把截止距离保持在你身后不远处。
• 绿幕会标出深度辅助可用的地方：绿幕一行和格式菜单会标注“深度”，深度辅助运行时“主体”按钮变为点阵。此时摄像头无法变焦，因此变焦会隐藏。
• 选项分为摄像头、直播界面、远程启动和高级几组，电脑卡片现在只显示“OBS 已连接”“就绪”或“远程启动已开启”。
• 也请把 OBS 插件更新到 1.17.0：浏览器控制面板新增白平衡校准、自然动态模糊和自动主体距离。
```

# App Store listing: localized

Every App Store Connect field for the six localizations, translated from
the English listing in [`APP_STORE.md`](APP_STORE.md). Paste each block
into that localization's field. The terms follow the glossary in
[`LOCALIZATION.md`](LOCALIZATION.md), and the app's own labels are
quoted exactly as its translations show them. Keywords never repeat the
words of the name or subtitle, which search already matches.

Keep this file in step with `APP_STORE.md`: when the English listing
changes, the translations here change with it. Release notes are per
version; the ones here are for 1.16.2, which also covers 1.16.1 (its
App Store version was renamed to 1.16.2 before it was submitted).

**Name:** LensLink Camera in every localization (the brand is not
translated).

**Spanish:** use the Spanish (Mexico) localization: the app's Spanish
is Latin American. If Spanish (Spain) is added too, paste the same text
with these changes: subtitle `Cámara del móvil para OBS`; "computadora"
→ "ordenador" (promotional text and description); "video" → "vídeo" and
"mantén presionado" → "mantén pulsado" (description).

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
Tippen zum Fokussieren, halten, um Fokus und Belichtung zu sperren, ziehen für die Helligkeit, mit zwei Fingern zoomen
Eine Einstellleiste für Belichtung, Verschluss, Weißabgleich und Fokus, mit Autofokus, der Gesichter bevorzugt
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

**What's New (1.16.2):**

```text
Feinschliff für den Hauptbildschirm und das Tally-Licht.

• Zwischen den Tasten „Kamera starten“, „Fernstart scharf schalten“ und „Bildschirm spiegeln“ sind keine dünnen Linien mehr zu sehen.
• Der Rahmen des Tally-Lichts folgt jetzt immer den abgerundeten Ecken deines Bildschirms, auch nachdem du auf dem iPad die Größe des LensLink-Fensters geändert hast.
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
Toca para enfocar, mantén presionado para bloquear el enfoque y la exposición, arrastra para ajustar el brillo, pellizca para hacer zoom
Una sola bandeja de ajustes para exposición, obturador, balance de blancos y enfoque, con autoenfoque que prioriza los rostros
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

**What's New (1.16.2):**

```text
Mejoras en la pantalla principal y en la luz tally.

• Los botones “Iniciar cámara”, “Armar inicio remoto” y “Duplicar pantalla” ya no tienen líneas delgadas entre ellos.
• El borde de la luz tally ahora sigue siempre las esquinas redondeadas de tu pantalla, incluso después de cambiar el tamaño de la ventana de LensLink en el iPad.
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
Touchez pour faire la mise au point, maintenez pour verrouiller la mise au point et l’exposition, faites glisser pour la luminosité, pincez pour zoomer
Un seul tiroir de réglages pour l’exposition, l’obturateur, la balance des blancs et la mise au point, avec un autofocus qui privilégie les visages
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

**What's New (1.16.2):**

```text
Finitions pour l’écran principal et le voyant tally.

• Les boutons « Démarrer la caméra », « Armer le démarrage à distance » et « Recopier l’écran » ne sont plus séparés par de fines lignes.
• Le contour du voyant tally suit désormais toujours les coins arrondis de votre écran, y compris après avoir redimensionné la fenêtre de LensLink sur iPad.
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
タップでフォーカス、長押しでフォーカスと露出をロック、ドラッグで明るさ調整、ピンチでズーム
露出、シャッター、ホワイトバランス、フォーカスをまとめた調整トレイ。顔を優先するオートフォーカス付き
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

**What's New (1.16.2):**

```text
メイン画面とタリーランプの表示を改善しました。

• 「カメラを開始」「リモート開始を有効にする」「画面をミラーリング」の各ボタンの間に細い線が表示されなくなりました。
• タリーランプの枠が、iPadでLensLinkのウインドウサイズを変更した後も含め、常に画面の角の丸みに沿うようになりました。
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
Toque para focar, mantenha pressionado para travar foco e exposição, arraste para o brilho, faça pinça para dar zoom
Uma só bandeja de ajustes para exposição, obturador, equilíbrio de branco e foco, com foco automático que prioriza rostos
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

**What's New (1.16.2):**

```text
Ajustes na tela principal e na luz tally.

• Os botões “Iniciar câmera”, “Armar início remoto” e “Espelhar tela” não têm mais linhas finas entre eles.
• A borda da luz tally agora sempre acompanha os cantos arredondados da sua tela, inclusive depois de redimensionar a janela do LensLink no iPad.
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
轻点对焦，按住锁定对焦和曝光，拖动调节亮度，双指捏合变焦
一个调节栏集中曝光、快门、白平衡和对焦，并提供人脸优先的自动对焦
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

**What's New (1.16.2):**

```text
主界面和 Tally 灯的细节改进。

• “启动摄像头”“开启远程启动”和“镜像屏幕”按钮之间不再出现细线。
• Tally 灯的边框现在始终贴合屏幕的圆角，包括在 iPad 上调整 LensLink 窗口大小之后。
```

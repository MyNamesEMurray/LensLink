# App Store listing: localized

Every App Store Connect field for the six localizations, translated from
the English listing in [`APP_STORE.md`](APP_STORE.md). Paste each block
into that localization's field. The terms follow the glossary in
[`LOCALIZATION.md`](LOCALIZATION.md), and the app's own labels are
quoted exactly as its translations show them. Keywords never repeat the
words of the name or subtitle, which search already matches.

Keep this file in step with `APP_STORE.md`: when the English listing
changes, the translations here change with it. Release notes are per
version; the ones here are for 1.16.0, which also covers 1.15.2 (pulled
from review before it shipped).

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

**What's New (1.16.0):**

```text
Du entscheidest jetzt, wann OBS deine Kamera starten darf, und 4K mit der Qualität „Maximal“ hat deutlich weniger Latenz.

• Fernstart scharf schalten: Das Öffnen von LensLink erlaubt OBS nicht mehr, die Kamera von selbst zu starten. Richte dein Bild ein und tippe dann auf „Fernstart scharf schalten“ unter „Kamera starten“. Bis dahin sieht OBS dein Smartphone, kann die Kamera aber nicht starten. Scharf bleibt es, bis du auf „Fernstart unscharf schalten“ tippst, den Stream auf dem Smartphone stoppst oder die App verlässt.
• Für ein Smartphone, das außer Reichweite montiert ist: Schalte unter „Optionen“ die Option „Fernstart beim Öffnen scharf schalten“ ein.
• Weniger Latenz in 4K mit der Qualität „Maximal“: Bei 4K30 auf einem iPhone 15 Pro sinkt sie von etwa 107 ms auf 60 ms, ohne sichtbaren Unterschied in der Bildqualität.
• Die Dokumentation in der App ist jetzt nach Themen geordnet, vom Verbinden bis zu den Bedienungshilfen, mit einem Link zur vollständigen Anleitung im Web.
• Aktualisiere auch das OBS-Plugin auf 1.16.0: Es zeigt an, wenn der Fernstart nicht scharf geschaltet ist, und startet die Kamera, sobald du ihn scharf schaltest.
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

**What's New (1.16.0):**

```text
Ahora tú decides cuándo OBS puede iniciar tu cámara, y el 4K con calidad Máxima tiene mucha menos latencia.

• Armar inicio remoto: abrir LensLink ya no permite que OBS inicie la cámara por sí solo. Prepara tu toma y luego toca “Armar inicio remoto”, debajo de Iniciar cámara. Hasta entonces, OBS puede ver tu teléfono pero no iniciar la cámara. Queda armado hasta que tocas “Desarmar inicio remoto”, detienes la transmisión en el teléfono o sales de la app.
• Para un teléfono montado fuera de tu alcance, activa “Armar el inicio remoto al abrir” en Opciones.
• Menos latencia en 4K con calidad Máxima: a 4K30 en un iPhone 15 Pro baja de unos 107 ms a 60 ms, sin diferencia visible en la calidad de imagen.
• La documentación de la app ahora está organizada por temas, desde la conexión hasta la accesibilidad, con un enlace a la guía completa en línea.
• Actualiza también el plugin de OBS a la versión 1.16.0: muestra cuándo el inicio remoto no está armado e inicia la cámara en cuanto lo armas.
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

**What's New (1.16.0):**

```text
Vous décidez désormais quand OBS peut démarrer votre caméra, et la 4K en qualité Maximale a nettement moins de latence.

• Armer le démarrage à distance : ouvrir LensLink ne permet plus à OBS de démarrer la caméra de lui-même. Réglez votre plan, puis touchez « Armer le démarrage à distance », sous Démarrer la caméra. Jusque-là, OBS voit votre téléphone mais ne peut pas démarrer la caméra. Il reste armé jusqu’à ce que vous touchiez « Désarmer le démarrage à distance », arrêtiez le flux sur le téléphone ou quittiez l’app.
• Pour un téléphone fixé hors de portée, activez « Armer le démarrage à distance à l’ouverture » dans Options.
• Moins de latence en 4K avec la qualité Maximale : en 4K30 sur un iPhone 15 Pro, elle passe d’environ 107 ms à 60 ms, sans différence visible de qualité d’image.
• La documentation de l’app est désormais organisée par thèmes, de la connexion à l’accessibilité, avec un lien vers le guide complet en ligne.
• Mettez aussi à jour le plugin OBS en 1.16.0 : il indique quand le démarrage à distance n’est pas armé et démarre la caméra dès que vous l’armez.
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

**What's New (1.16.0):**

```text
OBSがカメラを開始できるタイミングを自分で決められるようになりました。また、画質「最高」の4Kで遅延が大幅に減りました。

• リモート開始を有効にする：LensLinkを開いただけでOBSがカメラを開始することはなくなりました。撮影の準備をしてから、「カメラを開始」の下にある「リモート開始を有効にする」をタップします。それまではOBSからスマートフォンは見えますが、カメラを開始することはできません。有効な状態は、「リモート開始を解除」をタップするか、スマートフォンでストリームを停止するか、アプリを離れるまで続きます。
• 手の届かない場所に固定したスマートフォンでは、オプションの「開いたときにリモート開始を有効にする」をオンにしてください。
• 画質「最高」での4Kの遅延を短縮：iPhone 15 Proの4K30では約107msから60msに下がり、画質に目に見える違いはありません。
• アプリ内のドキュメントをトピック別に整理しました。接続からアクセシビリティまでを扱い、オンラインの完全なガイドへのリンクもあります。
• OBSプラグインも1.16.0にアップデートしてください。リモート開始が有効になっていないことを表示し、有効にした時点でカメラを開始します。
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

**What's New (1.16.0):**

```text
Agora você decide quando o OBS pode iniciar sua câmera, e o 4K com qualidade Máxima tem bem menos latência.

• Armar início remoto: abrir o LensLink não permite mais que o OBS inicie a câmera sozinho. Prepare sua cena e depois toque em “Armar início remoto”, abaixo de Iniciar câmera. Até lá, o OBS vê o seu celular, mas não pode iniciar a câmera. Ele fica armado até você tocar em “Desarmar início remoto”, parar a transmissão no celular ou sair do app.
• Para um celular montado fora de alcance, ative “Armar início remoto ao abrir” em Opções.
• Menos latência em 4K com qualidade Máxima: em 4K30 num iPhone 15 Pro, ela cai de cerca de 107 ms para 60 ms, sem diferença visível na qualidade da imagem.
• A documentação do app agora está organizada por tópicos, da conexão à acessibilidade, com um link para o guia completo online.
• Atualize também o plugin do OBS para a versão 1.16.0: ele mostra quando o início remoto não está armado e inicia a câmera assim que você o arma.
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

**What's New (1.16.0):**

```text
现在由你决定 OBS 何时可以启动摄像头，并且画质“最高”下的 4K 延迟大幅降低。

• 开启远程启动：打开 LensLink 后，OBS 不会再自行启动摄像头。先调好画面，再轻点“启动摄像头”下方的“开启远程启动”。在此之前，OBS 能看到你的手机，但无法启动摄像头。开启状态会一直保持，直到你轻点“关闭远程启动”、在手机上停止推流或离开 App。
• 如果手机固定在够不着的位置，请在“选项”中打开“打开 App 时开启远程启动”。
• 画质“最高”下的 4K 延迟更低：在 iPhone 15 Pro 上以 4K30 推流时，延迟从约 107 ms 降至 60 ms，画质没有可见差异。
• App 内的文档现已按主题整理，从连接到辅助功能都有介绍，并附有完整在线指南的链接。
• 也请将 OBS 插件更新到 1.16.0：它会显示远程启动尚未开启，并在你开启后立即启动摄像头。
```

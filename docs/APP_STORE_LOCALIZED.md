# App Store listing: localized

Every App Store Connect field for the six localizations, translated from
the English listing in [`APP_STORE.md`](APP_STORE.md). Paste each block
into that localization's field. The terms follow the glossary in
[`LOCALIZATION.md`](LOCALIZATION.md), and the app's own labels are
quoted exactly as its translations show them. Keywords never repeat the
words of the name or subtitle, which search already matches.

Keep this file in step with `APP_STORE.md`: when the English listing
changes, the translations here change with it. Release notes are per
version; the ones here are for 1.15.1.

**Name:** LensLink Camera in every localization (the brand is not
translated).

**Spanish:** use the Spanish (Mexico) localization: the app's Spanish
is Latin American. If Spanish (Spain) is added too, paste the same text
with these changes: subtitle `Cámara del móvil para OBS`; "computadora"
→ "ordenador" (promotional text and description); "video" → "vídeo" and
"mantén presionado" → "mantén pulsado" (description); "ícono" →
"icono" (What's New).

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
Fernstart: OBS startet die Kamera, während die App bereitsteht
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

**What's New (1.15.1):**

```text
LensLink spricht jetzt deine Sprache, funktioniert besser mit Bedienungshilfen und hat ein neues Symbol.

• Sechs neue Sprachen: Deutsch, Spanisch, Französisch, Japanisch, brasilianisches Portugiesisch und vereinfachtes Chinesisch. LensLink folgt der Sprache deines iPhone oder iPad, und auch das OBS-Plugin und das Browser-Steuerfeld sind übersetzt.
• Bedienungshilfen: Jedes Bedienelement hat eine VoiceOver-Beschriftung und Namen für die Sprachsteuerung. VoiceOver sagt an, wenn du live gehst, pausierst oder die Verbindung zu OBS verlierst. Außerdem unterstützt die App „Ohne Farbe unterscheiden“, „Transparenz reduzieren“, „Kontrast erhöhen“, „Bewegung reduzieren“ und größere Schriftgrößen.
• Objektivtasten für die Frontkamera: Auf iPads mit Ultraweitwinkel-Frontkamera wechselst du die Frontobjektive direkt auf dem Live-Bildschirm, genau wie die Objektive auf der Rückseite. Die Ultraweitwinkel-Frontkamera heißt jetzt „Frontkamera (Ultraweitwinkel)“ statt ein zweites Mal „Frontkamera“.
• Tippe auf das Objektiv, das du gerade verwendest, um seinen Zoom zurückzusetzen, genau wie in der Kamera-App.
• Die Bildschirmspiegelung kann jetzt mit 30 fps laufen, um Akku und WLAN-Bandbreite zu sparen. Wähle das in OBS in den Eigenschaften der Quelle LensLink Screen (erfordert das Plugin 1.15.1).
• Ein neues App-Symbol mit heller und dunkler Variante und voller Liquid-Glass-Unterstützung ab iOS 26.
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
Inicio remoto: OBS inicia la cámara mientras la app está en espera
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

**What's New (1.15.1):**

```text
LensLink ahora habla tu idioma, funciona mejor con las funciones de accesibilidad y tiene un ícono nuevo.

• Seis idiomas nuevos: alemán, español, francés, japonés, portugués de Brasil y chino simplificado. LensLink usa el idioma de tu iPhone o iPad, y el plugin de OBS y el panel de control en el navegador también están traducidos.
• Accesibilidad: cada control tiene una etiqueta de VoiceOver y nombres para Control por voz. VoiceOver anuncia cuando sales en vivo, pausas o pierdes la conexión con OBS. La app también es compatible con Diferenciar sin color, Reducir transparencia, Aumentar contraste, Reducir movimiento y tamaños de texto más grandes.
• Botones de lente para la cámara frontal: en los iPad con cámara frontal ultra gran angular, cambia de lente frontal directamente desde la pantalla En vivo, igual que con las lentes traseras. La cámara frontal ultra gran angular ahora aparece como “Frontal (ultra gran angular)” en lugar de un segundo “Frontal”.
• Toca la lente que ya estás usando para restablecer su zoom, como en la app Cámara.
• El duplicado de pantalla ahora puede funcionar a 30 fps para ahorrar batería y ancho de banda Wi-Fi. Elígelo en las propiedades de la fuente LensLink Screen en OBS (requiere el plugin 1.15.1).
• Un ícono nuevo, con versiones clara y oscura y compatibilidad total con Liquid Glass en iOS 26 y posteriores.
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
Démarrage à distance : OBS démarre la caméra pendant que l’app est en veille
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

**What's New (1.15.1):**

```text
LensLink parle désormais votre langue, fonctionne mieux avec les fonctionnalités d’accessibilité et arbore une nouvelle icône.

• Six nouvelles langues : allemand, espagnol, français, japonais, portugais du Brésil et chinois simplifié. LensLink suit la langue de votre iPhone ou iPad, et le plugin OBS ainsi que le panneau de contrôle web sont eux aussi traduits.
• Accessibilité : chaque commande a une étiquette VoiceOver et des noms pour le Contrôle vocal. VoiceOver annonce le passage en direct, la mise en pause et la perte de connexion avec OBS. L’app prend aussi en charge Différencier sans couleur, Réduire la transparence, Augmenter le contraste, Réduire les animations et les grandes tailles de texte.
• Boutons d’objectif pour la caméra avant : sur les iPad dotés d’une caméra avant ultra grand-angle, changez d’objectif avant directement depuis l’écran de direct, comme pour les objectifs arrière. La caméra avant ultra grand-angle s’appelle désormais « Avant (ultra grand-angle) » au lieu d’un second « Avant ».
• Touchez l’objectif que vous utilisez déjà pour réinitialiser son zoom, comme dans l’app Appareil photo.
• La recopie de l’écran peut désormais fonctionner à 30 fps pour économiser la batterie et la bande passante Wi-Fi. Choisissez cette option dans les propriétés de la source LensLink Screen dans OBS (nécessite le plugin 1.15.1).
• Une nouvelle icône, avec des versions claire et sombre et une prise en charge complète de Liquid Glass sous iOS 26 et versions ultérieures.
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
リモート開始：アプリが待機している間に、OBSからカメラを開始
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

**What's New (1.15.1):**

```text
LensLinkが多言語に対応しました。アクセシビリティ機能への対応も強化し、アイコンも一新しました。

• 6つの言語を追加：ドイツ語、スペイン語、フランス語、日本語、ポルトガル語（ブラジル）、簡体字中国語。LensLinkはiPhoneやiPadの言語設定に従って表示されます。OBSプラグインとブラウザコントロールパネルも翻訳されています。
• アクセシビリティ：すべての操作項目にVoiceOverのラベルと音声コントロール用の名前が付きました。ライブの開始、一時停止、OBSとの接続が切れたときは、VoiceOverが読み上げます。「カラー以外で区別」「透明度を下げる」「コントラストを上げる」「視差効果を減らす」と、より大きな文字サイズにも対応しました。
• 前面カメラのレンズボタン：前面に超広角カメラを搭載したiPadでは、背面のレンズと同じように、ライブ画面から前面のレンズを直接切り替えられます。前面の超広角カメラは、2つ目の「前面」ではなく「前面（超広角）」と表示されるようになりました。
• 使用中のレンズボタンをタップすると、カメラAppと同じようにズームがリセットされます。
• 画面ミラーリングを30 fpsで実行して、バッテリーとWi-Fiの帯域幅を節約できるようになりました。OBSのLensLink Screenソースのプロパティで選択してください（プラグイン1.15.1が必要です）。
• 新しいAppアイコン。ライトとダークのバージョンがあり、iOS 26以降ではLiquid Glassに完全対応します。
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
Início remoto: o OBS inicia a câmera enquanto o app está em espera
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

**What's New (1.15.1):**

```text
O LensLink agora fala o seu idioma, funciona melhor com os recursos de acessibilidade e tem um ícone novo.

• Seis novos idiomas: alemão, espanhol, francês, japonês, português do Brasil e chinês simplificado. O LensLink segue o idioma do seu iPhone ou iPad, e o plugin do OBS e o painel de controle no navegador também foram traduzidos.
• Acessibilidade: todos os controles têm rótulo do VoiceOver e nomes para o Controle por Voz. O VoiceOver avisa quando você entra ao vivo, pausa ou perde a conexão com o OBS. O app também é compatível com Diferenciar Sem Cor, Reduzir Transparência, Aumentar Contraste, Reduzir Movimento e tamanhos de texto maiores.
• Botões de lente para a câmera frontal: nos iPads com câmera frontal ultra-angular, troque de lente frontal direto na tela Ao vivo, como já acontece com as lentes traseiras. A câmera frontal ultra-angular agora aparece como “Frontal (ultra-angular)” em vez de um segundo “Frontal”.
• Toque na lente que você já está usando para redefinir o zoom dela, como no app Câmera.
• O espelhamento de tela agora pode rodar a 30 fps para economizar bateria e banda do Wi-Fi. Escolha essa opção nas propriedades da fonte LensLink Screen no OBS (requer o plugin 1.15.1).
• Um ícone novo, com versões clara e escura e suporte completo ao Liquid Glass no iOS 26 ou posterior.
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
远程启动：App 待机时，由 OBS 启动摄像头
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

**What's New (1.15.1):**

```text
LensLink 现已支持多种语言，对辅助功能的支持更加完善，并换上了全新图标。

• 新增六种语言：德语、西班牙语、法语、日语、葡萄牙语（巴西）和简体中文。LensLink 会跟随 iPhone 或 iPad 的语言设置，OBS 插件和浏览器控制面板也已翻译。
• 辅助功能：每个控件都有旁白标签和语音控制名称。开始直播、暂停或与 OBS 断开连接时，旁白会进行播报。App 还支持“不使用颜色区分”“降低透明度”“增强对比度”“减弱动态效果”以及更大的字体。
• 前置镜头按钮：在配有前置超广角摄像头的 iPad 上，可以像切换后置镜头一样，直接在直播界面切换前置镜头。前置超广角摄像头现在显示为“前置（超广角）”，而不再是第二个“前置”。
• 轻点当前正在使用的镜头，即可重置其变焦，与“相机” App 相同。
• 屏幕镜像现在可以以 30 fps 运行，以节省电量和 Wi-Fi 带宽。请在 OBS 中 LensLink Screen 来源的设置里选择（需要 1.15.1 版插件）。
• 全新 App 图标，提供浅色和深色版本，并在 iOS 26 及更高版本上全面支持液态玻璃效果。
```

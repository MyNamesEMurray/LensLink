# Localization

LensLink ships in seven languages on every surface: the iOS app (and its
broadcast extension), the OBS plugin, the browser control panel, and the
website. English is the source language everywhere; the others are
translations of it.

| Language | iOS (`.lproj`) | OBS plugin (`.ini`) | Website (URL prefix) |
|---|---|---|---|
| English (source) | `en` | `en-US` | *(root)* |
| German | `de` | `de-DE` | `/de/` |
| Spanish | `es` | `es-ES` | `/es/` |
| French | `fr` | `fr-FR` | `/fr/` |
| Japanese | `ja` | `ja-JP` | `/ja/` |
| Portuguese (Brazil) | `pt-BR` | `pt-BR` | `/pt-br/` |
| Chinese (Simplified) | `zh-Hans` | `zh-CN` | `/zh-hans/` |

Why these six: they are the largest non-English OBS user communities and
App Store markets, and together they cover most streamers who would not
otherwise read an English UI. Spanish is written to read naturally in both
Spain and Latin America (iOS and OBS each ship a single Spanish locale that
all Spanish speakers fall back to).

The one check for all of it:

```bash
python3 tools/check-l10n.py            # ios, plugin, site
python3 tools/check-l10n.py plugin     # one surface
```

CI runs it on every pull request that touches `ios-app/`, `obs-plugin/`
or `site/` (the **Localization** job).

## How each surface works

### iOS app and broadcast extension

Standard Apple `.strings` files, with the English text as the key:

```
ios-app/Sources/Localization/<lang>.lproj/Localizable.strings   app UI, intents, VoiceOver text
ios-app/Sources/Localization/<lang>.lproj/InfoPlist.strings     permission prompts
ios-app/Sources/Localization/<lang>.lproj/AppShortcuts.strings  Siri phrases
ios-app/BroadcastExtension/<lang>.lproj/Localizable.strings     extension messages
ios-app/BroadcastExtension/<lang>.lproj/InfoPlist.strings       extension prompt
```

The app follows the phone's language (Settings → General → Language &
Region, or per app in Settings → LensLink → Language).

In Swift:

- A plain literal given straight to a SwiftUI API (`Text("Live")`,
  `Toggle("Green screen", …)`, `.navigationTitle("Format")`) is localized
  by SwiftUI itself.
- Everything else goes through `L("English text")`
  (`Sources/Localization.swift`): computed labels, strings handed to our
  own row views, ternaries, error messages the user sees.
- Never interpolate into a localized string. Use a format key with
  positional arguments: `L("Battery %lld percent", level)`,
  `L("%1$@ at %2$lld fps", res, fps)`.
- Values that cross the wire stay English: lens labels, codec names and
  every other STATE/CONTROL value. The UI shows a translated
  `displayLabel` instead.
- Logs and diagnostic dumps meant for bug reports stay English.

`en.lproj/Localizable.strings` lists every key (value = key) with a
comment saying where it appears. The checker extracts keys from the
Swift sources and fails on a key that is used but missing, listed but
unused, or translated with different format specifiers.

### OBS plugin

OBS's own locale system: `obs-plugin/data/locale/<locale>.ini`, one
`Key="Value"` per line, looked up with `obs_module_text()` (`T_()` in
`ios-camera-source.c`). OBS picks the file matching its UI language
(Settings → General → Language) and falls back to `en-US.ini` per key,
so a missing key shows English rather than breaking.

Values are concatenated, never used as printf formats, so a translation
can never crash OBS. Keep a leading `" · "` or other padding exactly
where `en-US.ini` has it; the checker enforces it. Never put a bare
double quote inside a value.

### Browser control panel

The panel at `localhost:9980` is part of the plugin and speaks the same
language as OBS. Its strings are the `Web.*` keys in the same `.ini`
files: when the page is requested, the plugin injects them into the page
as a JSON object, and the page fills its labels from it. Lens names
arrive from the phone in English (they are wire values) and are
translated in the page through `Web.Lens.*` keys.

The status pill's color comes from the `tone` field of `/api/status`
(`idle`, `wait`, `ready`, `live`, `error`), never from the status text,
so it is correct in every language.

The page is built once per OBS session, so an edited `.ini` shows up in
the panel after OBS restarts.

### Website

English pages stay where they are (`site/pages/`, served at the root).
Translations mirror them under `site/translations/<prefix>/` and are
served under `/<prefix>/`. Shell strings (navigation, footer, sidebar,
notices, strings the page scripts need) live in `site/i18n/<prefix>.json`,
with `en.json` as the source.

Each translated page records which English revision it was translated
from (`source:` in its front matter, a hash of the English file). When
the English page changes, the build keeps serving the translation but
adds a notice pointing readers to the English page, and the checker
lists it as stale (a warning, not an error). A page with no translation
is served in English inside the translated navigation, with a notice.
`site/README.md` has the details.

## Changing English text

| You change | Then |
|---|---|
| An app string | Edit the Swift source, then the same key in `en.lproj/Localizable.strings` and every other `.lproj`. A changed English string is a new key: add it everywhere and delete the old one. |
| A plugin or web panel string | Edit `en-US.ini`, then the same key in every other `.ini`. If the meaning changed, update the translations too (or delete them; OBS falls back to English). |
| A website page | Edit the English page. Its translations become stale until someone updates them and their `source:` hash. |
| A website shell string | Edit `site/i18n/en.json` and every other `site/i18n/*.json`. |

If you can't translate a string yourself, add the English text in the
other languages' files rather than leaving the key out, and say so in
the pull request so a speaker can follow up. The checker requires every
iOS key in every language because iOS, unlike OBS, shows the raw key
when one is missing.

## Adding a language

1. iOS: copy each `en.lproj` folder to `<lang>.lproj` and translate the
   values. XcodeGen picks the folders up; nothing else to register.
2. Plugin: copy `en-US.ini` to `<locale>.ini` (OBS's locale name, as in
   OBS's own `data/locale` folder) and translate the values.
3. Website: add the language to `LANGS` in `site/build.py`, copy
   `site/i18n/en.json`, and translate pages into
   `site/translations/<prefix>/`.
4. Add the language to the table at the top of this file and a column
   to the glossary below.
5. `python3 tools/check-l10n.py` must pass.

## Style for translators

- Follow the English rules in `docs/UI_DESIGN.md` §3 (Microcopy) where
  they are not English-specific: sentence case where the language uses
  it, no exclamation marks, no "please", numbers as numerals.
- Address the reader the way the platform does: German *du*, Spanish
  *tú*, French *vous*, Japanese です・ます, Portuguese *você*, Chinese 你.
- Punctuation follows the target language, not the English source. The
  English copy uses dashes for asides and in *state — action* lines
  ("Streaming — tap to wake"); render those with what reads naturally in
  the language (German " – " or a colon, Spanish and Portuguese a colon
  or comma, Japanese and Chinese full-width punctuation such as 、。：（）).
  French puts a no-break space before `: ; ? !`.
- Chinese puts a space between Chinese and Latin text or numbers
  ("OBS 已连接"); Japanese does not ("OBSに接続済み").
- Never translate product and technical names: LensLink, LensLink
  Camera, LensLink Screen, OBS, OBS Studio, iPhone, iPad, Wi-Fi (German
  says WLAN, as iOS and OBS do there), USB,
  HEVC, H.264, HDR, HLG, Apple Log, ISO, AE, AWB, AF, fps, ms, Mb/s,
  resolution names (1080p, 4K).
- Name things on other people's screens exactly as they appear there in
  that language: OBS menus and panels as OBS's own translation shows
  them, iOS settings as iOS shows them. If you are not sure of OBS's
  exact wording, keep the English name.
- Keep placeholders, markup and structure exactly: `%@`, `%lld`,
  `%1$@`, `${applicationName}`, `**bold**`, HTML tags and attributes,
  `{{REPO}}`, heading structure, `href`s and `id`s.

## Glossary

The canonical terms. Every surface in a language uses the same word for
the same thing; when a term here reads wrong in context, change it here
and everywhere at once rather than drifting.

### Status and sync words

| English | de | es | fr | ja | pt-BR | zh-Hans |
|---|---|---|---|---|---|---|
| Not connected | Nicht verbunden | No conectado | Non connecté | 未接続 | Não conectado | 未连接 |
| Waiting for OBS… | Warten auf OBS … | Esperando a OBS… | En attente d’OBS… | OBSを待機中… | Aguardando o OBS… | 正在等待 OBS… |
| OBS connected — ready | OBS verbunden – bereit | OBS conectado: listo | OBS connecté – prêt | OBS接続済み・準備完了 | OBS conectado: pronto | OBS 已连接，就绪 |
| Live | Live | En vivo | En direct | ライブ | Ao vivo | 直播中 |
| Paused | Pausiert | En pausa | En pause | 一時停止中 | Pausado | 已暂停 |
| Measuring sync | Synchronisation wird gemessen | Midiendo la sincronía | Mesure de la synchro | 同期を測定中 | Medindo a sincronia | 正在测量同步 |
| Sync locked | Synchronisation fixiert | Sincronía fijada | Synchro verrouillée | 同期ロック済み | Sincronia travada | 同步已锁定 |
| Recalibrating | Wird neu kalibriert | Recalibrando | Recalibrage | 再キャリブレーション中 | Recalibrando | 正在重新校准 |
| Calibrate / auto-calibrate | Kalibrieren / Automatisch kalibrieren | Calibrar / Calibración automática | Calibrer / Calibration auto | キャリブレーション / 自動キャリブレーション | Calibrar / Calibrar automaticamente | 校准 / 自动校准 |
| On air | Auf Sendung | Al aire | À l’antenne | オンエア | No ar | 播出中 |
| In preview | In der Vorschau | En vista previa | En aperçu | プレビュー中 | Na pré-visualização | 预览中 |
| Connection lost | Verbindung verloren | Conexión perdida | Connexion perdue | 接続が切れました | Conexão perdida | 连接已断开 |
| Low battery | Akku schwach | Batería baja | Batterie faible | バッテリー残量低下 | Bateria fraca | 电量不足 |

### Features and controls

| English | de | es | fr | ja | pt-BR | zh-Hans |
|---|---|---|---|---|---|---|
| Flashlight (never "Torch") | Taschenlampe | Linterna | Lampe torche | フラッシュライト | Lanterna | 手电筒 |
| Green screen | Greenscreen | Pantalla verde | Écran vert | グリーンバック | Tela verde | 绿幕 |
| Lip sync / lip-sync | Lippensynchronität | Sincronía labial | Synchronisation labiale | リップシンク | Sincronia labial | 音画同步 |
| Auto lip-sync reference | Automatische Lippensynchron-Referenz | Referencia de sincronía labial automática | Référence de synchro labiale auto | 自動リップシンク用リファレンス | Referência automática de sincronia labial | 自动音画同步参考 |
| Remote start | Fernstart | Inicio remoto | Démarrage à distance | リモート開始 | Início remoto | 远程启动 |
| Auto-start | Autostart | Inicio automático | Démarrage auto | 自動開始 | Início automático | 自动启动 |
| Standby | Bereitschaft | En espera | Veille | スタンバイ | Em espera | 待机 |
| Start Camera | Kamera starten | Iniciar cámara | Démarrer la caméra | カメラを開始 | Iniciar câmera | 启动摄像头 |
| Stop camera | Kamera stoppen | Detener cámara | Arrêter la caméra | カメラを停止 | Parar câmera | 停止摄像头 |
| Pause / Resume | Pausieren / Fortsetzen | Pausar / Reanudar | Mettre en pause / Reprendre | 一時停止 / 再開 | Pausar / Retomar | 暂停 / 继续 |
| Mirror Screen | Bildschirm spiegeln | Duplicar pantalla | Recopier l’écran | 画面をミラーリング | Espelhar tela | 镜像屏幕 |
| Screen mirroring | Bildschirmspiegelung | Duplicado de pantalla | Recopie de l’écran | 画面ミラーリング | Espelhamento de tela | 屏幕镜像 |
| Clean feed | Sauberes Bild | Imagen limpia | Image seule | クリーン表示 | Imagem limpa | 纯净画面 |
| Dim screen | Bildschirm abdunkeln | Atenuar pantalla | Assombrir l’écran | 画面を暗くする | Escurecer tela | 调暗屏幕 |
| Tally light | Tally-Licht | Luz tally | Voyant tally | タリーランプ | Luz tally | Tally 灯 |
| Stats | Statistik | Estadísticas | Statistiques | 統計 | Estatísticas | 统计 |
| Browser control panel | Browser-Steuerfeld | Panel de control en el navegador | Panneau de contrôle web | ブラウザコントロールパネル | Painel de controle no navegador | 浏览器控制面板 |
| Options | Optionen | Opciones | Options | オプション | Opções | 选项 |
| Documentation | Dokumentation | Documentación | Documentation | ドキュメント | Documentação | 文档 |
| Diagnostics | Diagnose | Diagnóstico | Diagnostic | 診断 | Diagnóstico | 诊断 |
| Report a problem | Problem melden | Informar de un problema | Signaler un problème | 問題を報告 | Relatar um problema | 报告问题 |

### Camera and image

| English | de | es | fr | ja | pt-BR | zh-Hans |
|---|---|---|---|---|---|---|
| Camera | Kamera | Cámara | Caméra | カメラ | Câmera | 摄像头 |
| Lens | Objektiv | Lente | Objectif | レンズ | Lente | 镜头 |
| Front | Frontkamera | Frontal | Avant | 前面 | Frontal | 前置 |
| Front (Ultra Wide) | Frontkamera (Ultraweitwinkel) | Frontal (ultra gran angular) | Avant (ultra grand-angle) | 前面（超広角） | Frontal (ultra-angular) | 前置（超广角） |
| Main (Wide) | Haupt (Weitwinkel) | Principal (gran angular) | Principal (grand-angle) | メイン（広角） | Principal (grande-angular) | 主摄（广角） |
| Ultra Wide (0.5×) | Ultraweitwinkel (0,5×) | Ultra gran angular (0,5×) | Ultra grand-angle (0,5×) | 超広角（0.5×） | Ultra-angular (0,5×) | 超广角（0.5×） |
| Telephoto | Tele | Teleobjetivo | Téléobjectif | 望遠 | Teleobjetiva | 长焦 |
| Flip camera | Kamera wechseln | Cambiar de cámara | Changer de caméra | カメラを切り替え | Alternar câmera | 切换摄像头 |
| Zoom | Zoom | Zoom | Zoom | ズーム | Zoom | 变焦 |
| Exposure | Belichtung | Exposición | Exposition | 露出 | Exposição | 曝光 |
| Focus | Fokus | Enfoque | Mise au point | フォーカス | Foco | 对焦 |
| White balance | Weißabgleich | Balance de blancos | Balance des blancs | ホワイトバランス | Equilíbrio de branco | 白平衡 |
| Shutter | Verschluss | Obturador | Obturateur | シャッター | Obturador | 快门 |
| Subject (green-screen distance) | Motiv | Sujeto | Sujet | 被写体 | Assunto | 主体 |
| Dial chips, short forms (Exposure / Shutter / WB / Focus) | Belicht. / Verschl. / WA / Fokus | Expos. / Obtur. / WB / Enfoque | Expo / Vitesse / BB / MAP | 露出 / SS / WB / ピント | EV / Obtur. / WB / Foco | 曝光 / 快门 / 白平衡 / 对焦 |
| Auto / Manual / Lock | Auto / Manuell / Sperren | Auto / Manual / Bloquear | Auto / Manuel / Verrouiller | 自動 / マニュアル / ロック | Auto / Manual / Travar | 自动 / 手动 / 锁定 |
| All (no cutoff) | Alle | Todo | Tout | すべて | Tudo | 全部 |
| Format | Format | Formato | Format | フォーマット | Formato | 格式 |
| Resolution | Auflösung | Resolución | Résolution | 解像度 | Resolução | 分辨率 |
| Frame rate | Bildrate | Velocidad de fotogramas | Fréquence d’images | フレームレート | Taxa de quadros | 帧率 |
| Codec | Codec | Códec | Codec | コーデック | Codec | 编码格式 |
| Quality: Balanced / Maximum | Qualität: Ausgewogen / Maximal | Calidad: Equilibrada / Máxima | Qualité : Équilibrée / Maximale | 画質：バランス / 最高 | Qualidade: Equilibrada / Máxima | 画质：均衡 / 最高 |
| Color: Standard | Farbe: Standard | Color: Estándar | Couleur : Standard | カラー：標準 | Cor: Padrão | 色彩：标准 |
| Beta | Beta | Beta | Bêta | ベータ | Beta | 测试版 |

### Devices, OBS and iOS

| English | de | es | fr | ja | pt-BR | zh-Hans |
|---|---|---|---|---|---|---|
| the phone | das Smartphone | el teléfono | le téléphone | スマートフォン | o celular | 手机 |
| the computer | der Computer | la computadora | l’ordinateur | コンピュータ | o computador | 电脑 |
| Phone (the source's field) | Telefon | Teléfono | Téléphone | スマートフォン | Celular | 手机 |
| Connection | Verbindung | Conexión | Connexion | 接続 | Conexão | 连接 |
| USB cable | USB-Kabel | Cable USB | Câble USB | USBケーブル | Cabo USB | USB 线 |
| source (OBS) | Quelle | fuente | source | ソース | fonte | 来源 |
| Sources (OBS panel, in menu paths) | Quellen | Fuentes | Sources | ソース | Fontes | 源 |
| View menu (OBS) | Ansicht | Vista | Afficher | 表示 | Visualizar | 视图 |
| Wi-Fi | WLAN | Wi-Fi | Wi-Fi | Wi-Fi | Wi-Fi | Wi-Fi |
| tap (touch) | tippen | tocar | toucher | タップ | tocar | 轻点 |
| Properties (OBS) | Eigenschaften | Propiedades | Propriétés | プロパティ | Propriedades | 设置 |
| Tools menu (OBS) | Werkzeuge | Herramientas | Outils | ツール | Ferramentas | 工具 |
| filter (OBS) | Filter | filtro | filtre | フィルタ | filtro | 滤镜 |
| dock (OBS) | Dock | panel | dock | ドック | painel | 停靠窗口 |
| Settings (iOS app) | Einstellungen | Configuración | Réglages | 設定 | Ajustes | 设置 |
| LensLink Settings (plugin, Tools menu), settings in general | LensLink-Einstellungen | Ajustes de LensLink | Paramètres LensLink | LensLink設定 | Configurações do LensLink | LensLink 设置 |
| Local Network (iOS permission) | Lokales Netzwerk | Red local | Réseau local | ローカルネットワーク | Rede Local | 本地网络 |
| Trust (this computer) | Vertrauen | Confiar | Se fier | 信頼 | Confiar | 信任 |
| Control Center | Kontrollzentrum | Centro de control | Centre de contrôle | コントロールセンター | Central de Controle | 控制中心 |
| Low Power Mode | Stromsparmodus | Modo de bajo consumo | Mode Économie d’énergie | 低電力モード | Modo Pouca Energia | 低电量模式 |
| Sideload / sideloading | Sideloading | Instalación manual (sideload) | Installation manuelle (sideload) | サイドロード | Sideload | 侧载 |

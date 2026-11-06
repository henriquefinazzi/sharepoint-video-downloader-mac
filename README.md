<div align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="App icon">
  <h1>SharePoint Video Downloader for Mac</h1>
  <p>Download view-only SharePoint and Microsoft Stream videos from Safari with one click.</p>
  <p>
    <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/henriquefinazzi/sharepoint-video-downloader-mac" alt="Latest release"></a>
    <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPLv3-green" alt="GPLv3"></a>
  </p>
</div>

> 🇧🇷 [Leia em português](#português)

## How it works

1. Open a SharePoint or Stream video in Safari. The toolbar button turns **blue** when a video is detected
   (it's greyed out everywhere else).
2. Click it. The Mac app opens and downloads the video with `yt-dlp` and `ffmpeg`, merging video and audio
   into an `.mp4`.
3. Files go to `~/Downloads/SharePoint Videos` by default. You can pick another folder in the app.

You can also paste a video link straight into the app.

**Requirements:** macOS 14 or later, Safari, and [Homebrew](https://brew.sh). The app installs `yt-dlp` and
`ffmpeg` for you with one click if they're missing.

## Install

### Option A: download the DMG (easiest)

1. Download the latest `SharePointVideoDownloader-x.y.dmg` from [Releases](../../releases) and drag the app
   to **Applications**.
2. The app isn't signed with a paid Apple Developer ID, so macOS blocks the first launch. Double-click the app,
   click **OK**, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
   (Or run `xattr -dr com.apple.quarantine "/Applications/SharePoint Video Downloader.app"`.)
3. In Safari: **Settings → Advanced → Show features for web developers**, then
   **Settings → Developer → Allow unsigned extensions**.
   ⚠️ Safari turns this option off every time it quits, so you'll need to tick it again after restarting Safari.
4. **Settings → Extensions →** enable **SharePoint Video Downloader** and allow it on `sharepoint.com`.

### Option B: build it yourself (no Safari re-enabling)

Requires Xcode (from the App Store). Add any Apple ID in **Xcode → Settings → Accounts** — a free account is
enough. Then:

```bash
git clone https://github.com/henriquefinazzi/sharepoint-video-downloader-mac.git
cd sharepoint-video-downloader-mac
./scripts/install.sh
```

The script signs the app with your own Apple Development certificate and installs it to `~/Applications`, so
Safari keeps the extension enabled across restarts. Without a certificate it falls back to unsigned, like the DMG.
Then open the app once and enable the extension in **Safari → Settings → Extensions**.

> Install only one of the two options. Having both makes Safari list the extension twice.

## Troubleshooting

| Problem | Fix |
|---|---|
| Button stays grey on a video page | Wait for the player to load. Pages are re-checked for ~20 s after loading. |
| "Couldn't find the video on this page" | Reload the page and try again once the video starts playing. |
| Download fails with 401/403 | The page's access link expired. Reload the video page and click again. |
| Extension disappeared from Safari (DMG install) | Re-enable **Developer → Allow unsigned extensions**. |
| Extension listed twice | Remove one copy of the app (see the note above). |

## How it works under the hood

- **Safari extension** (`WebExtension/`) reads SharePoint's own `g_fileInfo` metadata on the page, turns the
  `transformUrl` into a DASH `videomanifest` URL, and sends it to the app via native messaging.
- **Extension handler** (`Extension/`) forwards it to the app through the `spvd://` URL scheme.
- **App** (`App/`, SwiftUI) runs `yt-dlp` with `ffmpeg` and shows progress.

The manifest URL carries a short-lived access token from your own logged-in session. Nothing is sent anywhere
except to Microsoft's servers, and links are kept only in memory while the app is open.

### For maintainers

- The Xcode project is generated from `project.yml`: `brew install xcodegen && xcodegen generate`.
- Icons are drawn by `swift scripts/make-icons.swift .`
- Release DMG (universal, unsigned): `./scripts/make-dmg.sh` → `dist/`.

## Disclaimer

Only download videos you're allowed to keep. Respect your organisation's policies and the rights of whoever
published the video. This project is not affiliated with or endorsed by Microsoft; SharePoint and Microsoft Stream
are trademarks of Microsoft.

## Credits & license

Based on the approach of [Sherif-Moheep/SharePointVideoDownloader](https://github.com/Sherif-Moheep/SharePointVideoDownloader)
(Windows + Chrome), which in turn credits
[brendangooden/ms-teams-sharepoint-downloader](https://github.com/brendangooden/ms-teams-sharepoint-downloader).
Downloads are powered by [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [FFmpeg](https://ffmpeg.org).

Licensed under the [GNU GPL v3](LICENSE).

---

## Português

Baixe vídeos "somente visualização" do SharePoint e do Microsoft Stream pelo Safari com um clique.

**Como usar:** abra o vídeo no Safari. Quando o botão da barra ficar **azul**, clique nele. O app baixa o vídeo
para `~/Downloads/SharePoint Videos` (dá para trocar a pasta no app).

**Requisitos:** macOS 14+, Safari e [Homebrew](https://brew.sh). O app instala o `yt-dlp` e o `ffmpeg` com um
clique, se faltarem.

### Opção A: DMG (mais fácil)
1. Baixe o `.dmg` em [Releases](../../releases) e arraste o app para **Aplicativos**.
2. Na primeira abertura o macOS bloqueia. Clique em **OK**, vá em **Ajustes do Sistema → Privacidade e Segurança**
   e clique em **Abrir Mesmo Assim**.
3. Safari → **Ajustes → Avançado → Mostrar recursos para desenvolvedores web**, depois
   **Ajustes → Desenvolvedor → Permitir extensões não assinadas**.
   ⚠️ O Safari desmarca essa opção sempre que é fechado.
4. **Ajustes → Extensões →** ative **SharePoint Video Downloader** e permita o acesso a `sharepoint.com`.

### Opção B: compilar (a extensão continua ativa ao reabrir o Safari)
Precisa do Xcode e de um Apple ID adicionado em **Xcode → Ajustes → Contas** (conta gratuita serve):

```bash
git clone https://github.com/henriquefinazzi/sharepoint-video-downloader-mac.git
cd sharepoint-video-downloader-mac
./scripts/install.sh
```

Use só uma das opções; com as duas, a extensão aparece duplicada no Safari.

Baixe só vídeos que você tem permissão para guardar. Projeto sem ligação com a Microsoft.

<h1 align="center">Cmux Mobile</h1>

<p align="center">
  <strong>Claude Code</strong>, <strong>Codex</strong>, <strong>cmux</strong> 세션을
  <strong>아무 폰에서나 — iOS <em>와</em> Android 둘 다</strong> 보고 조작합니다.
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>한국어</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License: MIT"/>
  <img src="https://img.shields.io/badge/platforms-iOS%20%7C%20Android%20%7C%20any%20browser-blue.svg" alt="Platforms"/>
  <img src="https://img.shields.io/badge/install-PWA-purple.svg" alt="PWA"/>
</p>

<p align="center">
  <img src="assets/hero.png" alt="Cmux Mobile" width="100%"/>
</p>

---

## 무엇인가요

**[lim-won/cmux-iphone](https://github.com/lim-won/cmux-iphone)**(MIT)를 포크해 모바일 클라이언트를
**크로스플랫폼**으로 만든 것입니다. 원본은 아이폰·애플워치용 네이티브 SwiftUI 앱이라 Android에서는
못 썼습니다. 이 포크는 브릿지에 이미 들어 있던 웹 클라이언트를 **설치형 PWA**로 만들어, 라이브 세션
미러·프롬프트 전송·권한 승인이 **Android Chrome에서도** 똑같이 동작합니다. Kotlin·Flutter 코드는
한 줄도 없습니다.

또한 모바일을 단순 뷰어가 아니라 **cmux 컨트롤러**로 만듭니다. cmux 워크스페이스가 **실제 이름**으로
보이고, 폰에서 라이브 터미널을 열어 입력하고, 키를 보내고, 새 세션을 만들 수 있습니다.

> **네이티브 Android 앱이 왜 없나요?** 브릿지가 이미 `GET /`에서 완전한 모바일 클라이언트(페어링,
> SSE 라이브 터미널 미러, 승인, 프롬프트 전송)를 서빙합니다. 쓰는 기술은 `fetch`·`EventSource`·
> `localStorage`뿐이고, 셋 다 Android Chrome과 iOS Safari에서 동일하게 동작합니다. 그래서 "Android
> 지원"은 *그 페이지를 Android에 서빙하고 설치 가능하게* 만드는 것입니다. 네이티브 iOS 앱은 iOS용
> 프리미엄 경로로 남고, 웹 클라이언트가 공용 경로입니다.

## 동작 방식

```
   폰 (브라우저 / iOS 앱)  ──HTTP POST──►  cmux-iphone 브릿지 (맥의 Node)
                          ◄──SSE 스트림──   GET / 에서 웹 클라이언트 서빙
                                            ├─ Claude Code  → 훅(hooks)
                                            ├─ cmux         → 컨트롤 소켓 RPC (라이브 미러)
                                            └─ Codex        → 로그 + 핀 고정 터미널
```

<p align="center">
  <img src="assets/architecture.png" alt="Architecture" width="100%"/>
</p>

모든 것이 **본인 기기 안에서만** 돌아갑니다 — 클라우드도 계정도 없습니다. 브릿지는 기본적으로
loopback 전용이며, 신뢰하는 LAN이나 Tailscale 테일넷으로만 노출합니다. 인증은 페어링 코드 +
기기별 토큰입니다.

> **설치하면 각자 자기 것입니다.** 레포는 코드일 뿐이라 주소도, 페어링 코드도, 비밀값도 들어 있지
> 않습니다. *본인이* setup을 돌리면 본인 맥이 **자기만의** 랜덤 페어링 코드를 생성하고 **본인 머신**
> 주소에 바인드합니다. 본인 폰은 **본인 맥**과 페어링합니다. 남의 것에 연결되지 않습니다.

## 설치

### 1. 브릿지 (맥에서)

```bash
cd skill/bridge
npm ci
node bin/cmux-iphone.js setup     # Claude Code 훅 설치(설정 백업 후) + 러너 자동 선택
node bin/cmux-iphone.js pair      # 본인의 6자리 페어링 코드 출력
```

`setup`은 멱등(여러 번 실행해도 안전)하며, `~/.claude/settings.json`을 백업한 뒤 자기 훅만 스코프해서
머지합니다. cmux가 있으면 브릿지를 cmux *안에서* 띄워 라이브 미러가 동작합니다.

### 2. 폰이 닿게 하기

브릿지는 기본이 loopback입니다. 접속할 경로에 맞게 노출합니다.

```bash
node bin/cmux-iphone.js status                 # 본인 LAN·Tailscale 주소 표시
node bin/cmux-iphone.js setup --bind 100.x.y.z # 본인 Tailscale IP에 바인드(암호화, 권장)
# 또는 --lan / --hotspot 으로 로컬 네트워크 전체(평문 — 신뢰 네트워크에서만)
```

- **같은 Wi-Fi:** `status`의 LAN 주소 중 하나 사용 (예: `http://192.168.x.x:7860/`).
- **어디서나:** 맥·폰에 [Tailscale](https://tailscale.com)을 같은 계정으로 설치 후 `100.x.y.z` 주소 사용.
- **폰 핫스팟/테더링:** `setup --hotspot` 실행 후 `status`가 알려주는 핫스팟 서브넷 주소로 접속.

### 3. 폰에서 접속

1. 브릿지 주소를 **Chrome(Android)** 또는 **Safari(iOS)**에서 엽니다.
2. **페어링 코드**(`cmux-iphone pair`)를 입력합니다.
3. 완료 — 라이브 터미널 미러·프롬프트·승인, 그리고 cmux 워크스페이스 뷰(▦)를 씁니다.

### 4. 앱으로 설치

- **iOS:** 공유 → **홈 화면에 추가** → 독립 실행(평문 HTTP에서도 됩니다).
- **Android:** 진짜 설치형 PWA를 원하면 HTTPS로 서빙 — `tailscale serve --bg --https=443 http://127.0.0.1:7860` 후 `https://<맥>.<테일넷>.ts.net/`을 열면 Chrome이 **앱 설치**를 띄웁니다.

크로스플랫폼 상세(Bonjour 자동 발견, 테더링, 보안 설계)는 [`ANDROID.md`](ANDROID.md)에 있습니다.
**네이티브 iOS 앱**(Xcode 빌드)과 브릿지 내부 구조는 [`README.upstream.md`](README.upstream.md)를
참고하세요.

## 이 포크가 추가한 것

| 파일 | 변경 |
|---|---|
| `skill/bridge/manifest.webmanifest`, `sw.js`, `icons/` | PWA 셸 — iOS/Android 설치 가능. SW는 `/events`·`/command`·`/status`·`/cmux/*`를 절대 캐시하지 않음 |
| `skill/bridge/webclient.html` | manifest/SW 주입 + **cmux 워크스페이스 뷰(▦)**: 실명, 라이브 터미널, 텍스트/키 입력, 새 세션 버튼 |
| `skill/bridge/server.js` | PWA 정적 라우트 + `POST /cmux/input · /cmux/key · /cmux/new` (전부 인증 게이트, `new` command는 allowlist — 폰에서 임의 셸 실행 불가) |
| `skill/bridge/cmux.js` | `newWorkspace()` + `ctrl-c` 키 |
| `skill/bridge/verify-pwa.sh`, `verify-cmux.sh` | 결정론 게이트(라우트, SW 우회, cmux 제어 + 거부 경로) |

네이티브 iOS 앱, 브릿지 코어, CLI는 원본과 동일합니다.

## 검증

```bash
bash skill/bridge/verify-pwa.sh    # 신택스, 업스트림 유닛 14/14, PWA 라우트 200, SW 우회
bash skill/bridge/verify-cmux.sh   # cmux tree/new/input/screen/key + 거부 경로 (브릿지 실행 중 필요)
```

## 라이선스 · 출처

MIT — [`LICENSE`](LICENSE) 참고. 이 프로젝트는
[lim-won/cmux-iphone](https://github.com/lim-won/cmux-iphone)(MIT)의 포크이며, 그 원본은
[shobhit99/claude-watch](https://github.com/shobhit99/claude-watch)(MIT)의 포크입니다. 원저작자
저작권을 보존했습니다([`NOTICE.md`](NOTICE.md) 참고). 중립 아이콘만 사용하며 "Claude"·"Codex"는 각각
Anthropic·OpenAI의 상표로 텍스트 라벨로만 표기합니다. Anthropic/OpenAI와 무관한 독립 커뮤니티
도구입니다.

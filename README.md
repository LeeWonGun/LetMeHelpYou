# Lecture Summary App

Flutter 클라이언트와 Django 기반 RAG 서버를 하나의 저장소에서 관리하는 강의 문서 요약 애플리케이션입니다. Android를 기본 실행 환경으로 개발했으며, 현재 공개 범위는 운영 배포가 아닌 로컬 포트폴리오 시연 환경을 기준으로 합니다.

## 프로젝트 구성

```text
lecture-summary-app/
├── frontend-flutter/  # Flutter 애플리케이션
└── backend-rag/       # Django/Python RAG 서버
```

## 시스템 구조

```text
Flutter Client
  └─ Django REST API / Simple JWT
       ├─ MySQL: 문서 및 Chunk 메타데이터
       ├─ media: 업로드 PDF와 생성 이미지
       ├─ OpenAI API: Embedding 및 응답 생성
       └─ FAISS: 문서별 벡터 인덱스
```

## RAG 처리 흐름

```text
PDF 업로드
→ PyMuPDF 텍스트 추출
→ 문서 Chunk 분할 및 DB 저장
→ OpenAI Embedding 생성
→ FAISS 인덱스 저장 및 유사 Chunk 검색
→ 검색 문맥을 사용한 요약 및 질의응답
```

## 주요 기능

- PDF 문서 업로드
- PDF 텍스트 및 페이지 이미지 추출
- 문서 텍스트 Chunk 분할
- OpenAI Embedding 생성
- FAISS 기반 유사 문서 Chunk 검색
- RAG 기반 문서 요약 및 질의응답
- Kakao 로그인과 JWT 기반 인증

## 기술 스택

### Frontend

- Flutter / Dart
- Dio 및 HTTP
- Syncfusion Flutter PDF Viewer
- Kakao Flutter SDK
- Flutter Secure Storage
- Flutter Markdown

### Backend

- Python / Django 5.2
- Django REST Framework
- Simple JWT
- MySQL
- OpenAI API
- FAISS / NumPy
- PyMuPDF

## 환경변수 설정

Backend 환경변수 예시는 `backend-rag/.env.example`에 있습니다. `.env`가 없는 새 환경에서는 이 파일을 참고해 `backend-rag/.env`를 별도로 준비하세요. 기존 `.env`가 있다면 덮어쓰지 마세요.

실제 API Key, Django Secret Key, DB 비밀번호는 저장소에 커밋하지 마세요. Django 설정은 `DJANGO_*`, `DB_*`, `CORS_ALLOWED_ORIGINS` 환경변수를 읽습니다.

## Backend 실행 방법

Backend 명령은 `backend-rag`에서 실행합니다.

```powershell
Set-Location backend-rag
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

현재 Backend는 MySQL을 사용하도록 구성되어 있으므로 실행 전에 로컬 DB 설정이 필요합니다. OpenAI 기능을 사용할 때는 유효한 `OPENAI_API_KEY`가 필요합니다.

## Flutter 실행 방법

먼저 Flutter 프로젝트로 이동해 의존성을 준비합니다.

이 프로젝트의 원래 기본 실행 환경은 Android입니다. Web의 Portfolio Preview와 Local Real RAG Demo는 포트폴리오 화면 확인을 위한 Debug 전용 모드입니다.

```powershell
Set-Location frontend-flutter
flutter pub get
```

### Web

```powershell
flutter run -d chrome `
  --dart-define=KAKAO_NATIVE_APP_KEY=<YOUR_KAKAO_NATIVE_APP_KEY> `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### Windows

```powershell
flutter run -d windows `
  --dart-define=KAKAO_NATIVE_APP_KEY=<YOUR_KAKAO_NATIVE_APP_KEY> `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### Android Emulator

```powershell
flutter run `
  --dart-define=KAKAO_NATIVE_APP_KEY=<YOUR_KAKAO_NATIVE_APP_KEY> `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

### 실제 Android 기기

실제 기기에서는 PC와 같은 네트워크에서 접근 가능한 주소를 명시적으로 전달해야 합니다. 앱에 개인 LAN IP 기본값은 포함되지 않습니다.

```powershell
flutter run `
  --dart-define=KAKAO_NATIVE_APP_KEY=<YOUR_KAKAO_NATIVE_APP_KEY> `
  --dart-define=API_BASE_URL=http://<PC_LAN_IP>:8000
```

`API_BASE_URL`을 전달하지 않으면 Web과 desktop은 `127.0.0.1`, Android Emulator는 `10.0.2.2`를 사용합니다. 실제 Android 기기는 `API_BASE_URL`을 반드시 전달해야 합니다.

## Kakao 설정

1. `frontend-flutter/android/local.properties.example`을 같은 폴더의 `local.properties`로 복사합니다.
2. 로컬 환경에 맞는 `sdk.dir`, `flutter.sdk`와 `kakao.nativeAppKey`를 입력합니다.
3. Flutter 실행 시 Android 설정과 동일한 Native App Key를 `KAKAO_NATIVE_APP_KEY`로 전달합니다.

일반 실행에서 `KAKAO_NATIVE_APP_KEY`를 전달하지 않으면 앱 초기화 단계에서 명확한 오류와 함께 실행이 중단됩니다. Android 빌드에는 별도로 `android/local.properties`의 `kakao.nativeAppKey`가 필요합니다.

Android Emulator에서 PowerShell로 실행하는 예시는 다음과 같습니다.

```powershell
flutter run `
  --dart-define=KAKAO_NATIVE_APP_KEY=<YOUR_KAKAO_NATIVE_APP_KEY> `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

- Android Emulator에서 PC의 Backend에 접속할 때는 `10.0.2.2`를 사용합니다.
- Flutter Web과 Windows에서는 `127.0.0.1`을 사용할 수 있습니다.
- 실제 Android 기기에서는 기기와 PC를 같은 네트워크에 연결하고 PC의 접근 가능한 로컬 IP를 사용합니다.
- Kakao Developers에서 Android 패키지명과 키 해시를 등록해야 합니다.
- `local.properties`와 실제 Kakao Native App Key는 Git에 포함하지 마세요.

## Portfolio Preview Mode

Flutter Web에서 실제 인증이나 Backend 데이터 없이 주요 포트폴리오 화면을 확인할 수 있는 Debug 전용 로컬 미리보기 모드입니다.

```powershell
flutter run -d chrome `
  --web-port=5173 `
  --dart-define=PORTFOLIO_PREVIEW=true `
  --dart-define=KAKAO_NATIVE_APP_KEY=dummy-preview-key `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

- `kDebugMode`, Flutter Web, `PORTFOLIO_PREVIEW=true` 조건을 모두 만족할 때만 활성화됩니다.
- `true` 외에 `1`, `yes`도 활성화 값으로 사용할 수 있습니다.
- Preview Mode에서는 Kakao SDK 초기화를 건너뛰므로 위의 dummy 값은 실제 인증에 사용되지 않습니다. 해당 인자는 생략해도 됩니다.
- 실제 Backend, Kakao, OpenAI API를 호출하지 않으며 JWT나 Preview 상태를 저장하지 않습니다.
- 업로드, 삭제, 이름 변경, 로그아웃과 같은 변경 기능은 안내 메시지만 표시합니다.
- 실제 인증을 대체하는 기능이 아니며 포트폴리오 화면 확인 목적으로만 사용합니다.
- Release 빌드에서는 Preview Mode와 진입 버튼이 비활성화됩니다.

## Local Real RAG Demo

Flutter Web에서 로컬 Django 일반 사용자와 실제 Simple JWT를 사용하기 위한 개발 전용 모드입니다. 이 모드는 Kakao 로그인을 대체하는 운영 기능이 아니며 Debug Web과 loopback 주소에서만 활성화됩니다.

1. `backend-rag/.env`에 다음 로컬 설정을 추가합니다. 실제 비밀번호는 `.env`에 저장하지 않습니다.

   ```env
   DJANGO_DEBUG=true
   LOCAL_DEMO_LOGIN=true
   LOCAL_DEMO_USERNAME=portfolio_demo
   DEMO_MEDIA_ROOT=demo-media
   DEMO_FAISS_ROOT=demo-faiss
   DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1
   CORS_ALLOWED_ORIGINS=http://localhost:5173,http://127.0.0.1:5173
   ```

2. Backend 가상환경에서 일반 데모 사용자를 대화형으로 생성합니다. 명령이 비밀번호와 확인 값을 직접 요청하며 입력값은 화면에 표시되지 않습니다.

   ```powershell
   Set-Location backend-rag
   .\venv\Scripts\python.exe manage.py create_local_demo_user
   ```

   이미 사용자가 존재하면 계정 권한을 확인한 후 다음 명령으로 비밀번호만 안전하게 변경할 수 있습니다.

   ```powershell
   .\venv\Scripts\python.exe manage.py changepassword portfolio_demo
   ```

3. 외부 네트워크에 노출되지 않도록 Django를 loopback 주소에만 바인딩합니다.

   ```powershell
   .\venv\Scripts\python.exe manage.py runserver 127.0.0.1:8000
   ```

4. 별도 터미널에서 Flutter Web을 실행합니다.

   ```powershell
   Set-Location frontend-flutter
   flutter run -d chrome `
     --web-port=5173 `
     --dart-define=REAL_RAG_DEMO=true `
     --dart-define=API_BASE_URL=http://127.0.0.1:8000
   ```

5. 로그인 화면의 `로컬 RAG 데모 로그인`에서 `portfolio_demo`와 직접 설정한 비밀번호를 입력합니다. 성공하면 실제 access/refresh JWT가 기존 세션 저장 흐름에 저장되고 인증된 문서 목록으로 이동합니다.

- `PORTFOLIO_PREVIEW`와 `REAL_RAG_DEMO`는 동시에 활성화할 수 없습니다.
- `LOCAL_DEMO_LOGIN`은 `DJANGO_DEBUG=true`일 때만 유효하며, 비활성 상태에서는 로그인 URL이 등록되지 않습니다.
- `DEMO_MEDIA_ROOT`와 `DEMO_FAISS_ROOT`를 위처럼 설정하면 기존 `media/`와 `faiss/` 대신 격리된 데모 경로를 사용합니다.
- 실제 API 호출에는 OpenAI 사용 비용과 로컬 데이터 생성이 수반됩니다.

## Known Issues

- Flutter Web의 PDF Viewer가 media URL을 직접 읽을 때 JWT Header를 함께 보내지 못해 환경에 따라 401 응답이 발생할 수 있습니다.
- Kakao 로그인은 Android 흐름을 기준으로 구현되어 있으며 정식 Kakao Web 로그인은 구현되어 있지 않습니다.
- `Document`에 사용자 소유권 필드가 없어 인증 사용자별 문서 격리가 적용되지 않습니다. Local Demo는 외부에 공개하지 마세요.
- 인제스트는 Chunk DB 저장과 OpenAI Embedding, FAISS 저장을 하나의 트랜잭션으로 처리하지 않습니다. Embedding 실패 시 Chunk만 남을 수 있습니다.

## 향후 개선사항

- 인증이 필요한 Web PDF 제공 방식 또는 제한된 media URL 설계
- Kakao Web 로그인과 플랫폼별 인증 흐름 정리
- Document 사용자 소유권과 API QuerySet 격리
- Chunk, Embedding, FAISS 저장의 트랜잭션·임시 파일 기반 원자성 개선
- 자동화 테스트와 운영 환경용 보안·배포 설정 분리

## 스크린샷

스크린샷은 개인정보, 실제 PDF 내용 및 Secret 노출 여부를 검토한 후 추가할 예정입니다.

## Git에 포함되지 않는 로컬 데이터

다음 항목은 실행 또는 사용자 업로드로 생성되는 데이터이므로 Git에 포함하지 않습니다.

- `backend-rag/.env`
- `backend-rag/media/`
- `backend-rag/faiss/`
- `backend-rag/demo-media/`
- `backend-rag/demo-faiss/`
- `backend-rag/db.sqlite3`
- Python 가상환경과 캐시
- Flutter 및 Gradle 빌드 산출물

이 파일들은 `.gitignore`로만 제외되며 자동으로 삭제되지 않습니다. 기존 포트폴리오 화면을 복구해야 한다면 별도로 안전하게 보관해야 합니다.

## 주의사항

- OpenAI API 요청에는 사용량에 따른 비용이 발생할 수 있습니다.
- 업로드한 PDF와 생성 이미지에는 개인정보 또는 저작권이 있는 내용이 포함될 수 있습니다.
- 이 저장소에는 실제 Secret을 포함하지 않아야 합니다.

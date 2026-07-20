import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

class AppConfig {
  static const String _portfolioPreviewValue = String.fromEnvironment(
    'PORTFOLIO_PREVIEW',
    defaultValue: 'false',
  );

  static const String _realRagDemoValue = String.fromEnvironment(
    'REAL_RAG_DEMO',
    defaultValue: 'false',
  );

  static bool _isEnabledValue(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  static void _ensureExclusiveDemoModes() {
    if (_isEnabledValue(_portfolioPreviewValue) &&
        _isEnabledValue(_realRagDemoValue)) {
      throw StateError(
        'PORTFOLIO_PREVIEW and REAL_RAG_DEMO cannot both be enabled.',
      );
    }
  }

  static bool get isPortfolioPreview {
    _ensureExclusiveDemoModes();
    return kDebugMode && kIsWeb && _isEnabledValue(_portfolioPreviewValue);
  }

  static bool get isRealRagDemo {
    _ensureExclusiveDemoModes();
    if (!kDebugMode || !kIsWeb || !_isEnabledValue(_realRagDemoValue)) {
      return false;
    }

    final configuredBaseUrl = _normalizeBaseUrl(_configuredBaseUrl);
    final uri = Uri.tryParse(configuredBaseUrl);
    if (configuredBaseUrl.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        (uri.host != 'localhost' && uri.host != '127.0.0.1')) {
      throw StateError(
        'REAL_RAG_DEMO requires API_BASE_URL to use localhost or 127.0.0.1.',
      );
    }
    return true;
  }

  static const String portfolioPreviewUnavailableMessage =
      '포트폴리오 미리보기 모드에서는 사용할 수 없는 기능입니다.';

  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String _normalizeBaseUrl(String value) {
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  static bool get _useAndroidEmulator =>
      const bool.fromEnvironment('USE_ANDROID_EMULATOR', defaultValue: true);

  /// 환경에 따라 baseUrl 자동 분기 (선택)
  static String get baseUrl {
    final configuredBaseUrl = _normalizeBaseUrl(_configuredBaseUrl);
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }

    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return 'http://127.0.0.1:8000';
    }

    if (Platform.isAndroid) {
      if (_useAndroidEmulator) {
        return 'http://10.0.2.2:8000'; // 에뮬레이터용
      } else {
        throw StateError(
          'Physical Android devices require API_BASE_URL to be provided '
          'with --dart-define.',
        );
      }
    }

    return 'http://127.0.0.1:8000';
  }

  static const String authKakaoPath = '/api/auth/kakao/'; // ← 추가
  static const String authLocalDemoPath = '/api/auth/local-demo/';

  // --- API paths (서버 URL 설계와 일치시켜 주세요; 끝에 슬래시 권장) ---
  static const String askGptPath = '/api/ask-gpt/';
  static const String summarizeForDocPath = '/api/summarize/'; // body: {doc_id}
  static const String docsPath = '/api/docs/';

  static const String uploadPath = '/api/files/upload/'; // multipart: file
  static const String ingestPath = '/api/ingest/'; // body: {doc_id}
  static const refreshPath = '/api/auth/refresh/';

  static const notesSummarizePath = '/summarize/notes/';
  static const notesSnapshotsPath = '/notes/snapshots/';

  static const bool useJwt = true;
}

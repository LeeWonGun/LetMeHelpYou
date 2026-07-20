// lib/api_client.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';

import 'config.dart';
import 'models.dart';
import 'core/session/session_manager.dart'; // SSOT

/// Web 디버그 전용 포트폴리오 미리보기에서는 로컬 Mock만 사용한다.
bool get kUseMock => AppConfig.isPortfolioPreview;

class PortfolioPreviewUnavailableException implements Exception {
  const PortfolioPreviewUnavailableException();

  @override
  String toString() => AppConfig.portfolioPreviewUnavailableMessage;
}

class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException([this.message = '세션이 만료되었습니다. 다시 로그인해 주세요.']);

  @override
  String toString() => message;
}

HttpException _httpStatusException(String message, int? statusCode) {
  final status = statusCode == null ? '' : ' (HTTP $statusCode)';
  return HttpException('$message$status');
}

class ApiClient {
  ApiClient({
    http.Client? client,
    Dio? dio,

    /// ⬆ CHANGED: 기본 타임아웃 15s → 60s
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: AppConfig.baseUrl,
               connectTimeout: const Duration(seconds: 15),

               /// ⬆ CHANGED: 무거운 응답 고려해 180s
               receiveTimeout: const Duration(seconds: 180),
             ),
           ) {
    // ✅ 모든 Dio 요청에 JWT 자동 부착 + 401 자동 refresh 재시도
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (opt, handler) async {
          if (AppConfig.isPortfolioPreview) {
            return handler.reject(
              DioException(
                requestOptions: opt,
                type: DioExceptionType.cancel,
                error: const PortfolioPreviewUnavailableException(),
              ),
            );
          }
          if (AppConfig.useJwt && opt.extra['skipAuth'] != true) {
            final t = await SessionManager.I.accessToken;
            if (t != null && t.isNotEmpty) {
              opt.headers['Authorization'] = 'Bearer $t';
            }
          }
          return handler.next(opt);
        },
        onError: (err, handler) async {
          // access 401 → refresh 시도
          if (err.response?.statusCode == 401 &&
              err.requestOptions.extra['skipAuth'] != true &&
              (err.requestOptions.extra['retried'] != true)) {
            final ok = await _refreshAccessToken();
            if (ok) {
              // 🔁 새 access로 한 번만 재시도
              final req = err.requestOptions;
              req.extra['retried'] = true;
              final t = await SessionManager.I.accessToken;
              if (t != null && t.isNotEmpty) {
                req.headers['Authorization'] = 'Bearer $t';
              } else {
                req.headers.remove('Authorization');
              }
              try {
                final clone = await _dio.fetch(req);
                return handler.resolve(clone);
              } catch (_) {
                return handler.next(err);
              }
            } else {
              // ❌ refresh도 실패 → 세션 만료 예외로 래핑해서 위로 올림
              return handler.reject(
                DioException(
                  requestOptions: err.requestOptions,
                  error: SessionExpiredException(), // <-- 이거!
                  type: DioExceptionType.badResponse,
                  response: err.response,
                ),
              );
            }
          }
          return handler.next(err);
        },
      ),
    );
  }

  final http.Client _client;
  final Dio _dio;
  final Duration timeout;

  // ----------------- 공통 헤더 -----------------
  Future<Map<String, String>> _authHeaders({Map<String, String>? base}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      ...?base,
    };
    if (!AppConfig.isPortfolioPreview && AppConfig.useJwt) {
      final t = await SessionManager.I.accessToken;
      if (t != null && t.isNotEmpty) {
        headers['Authorization'] = 'Bearer $t';
      }
    }
    return headers;
  }

  // ----------------- 401 처리 공통 -----------------
  Future<http.Response> _retryOn401(
    Future<http.Response> Function() send,
  ) async {
    if (AppConfig.isPortfolioPreview) {
      throw const PortfolioPreviewUnavailableException();
    }
    var resp = await send();
    if (resp.statusCode != 401) return resp;

    final ok = await _refreshAccessToken();
    if (!ok) {
      // ✅ refresh도 실패 → 세션 만료로 간주
      throw SessionExpiredException();
    }

    // 재시도
    resp = await send();
    return resp;
  }

  Future<bool> _refreshAccessToken() async {
    if (AppConfig.isPortfolioPreview) return false;
    final refresh = await SessionManager.I.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;

    final uri = Uri.parse('${AppConfig.baseUrl}${AppConfig.refreshPath}');

    try {
      final r = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(const Duration(seconds: 10));

      if (r.statusCode ~/ 100 != 2) {
        await SessionManager.I.logout();
        return false;
      }

      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

      // 🔹 새 access / refresh 둘 다 파싱
      final newAccess = (data['access'] ?? data['access_token'])?.toString();
      final newRefresh = (data['refresh'] ?? data['refresh_token'])?.toString();

      if (newAccess == null || newAccess.isEmpty) return false;

      await SessionManager.I.saveAccess(newAccess);
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await SessionManager.I.saveRefresh(newRefresh); // 🔹 회전된 refresh 저장
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ----------------- 인증 교환 (그대로 유지) -----------------
  /// 카카오 액세스 토큰 → 서버(JWT 교환). SSOT 저장은 하지 않고 토큰만 반환.
  Future<AuthTokens> loginWithKakao(String kakaoAccessToken) async {
    if (AppConfig.isPortfolioPreview) {
      throw const PortfolioPreviewUnavailableException();
    }
    final authDio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    final r = await authDio.post(
      AppConfig.authKakaoPath, // '/api/auth/kakao/'
      data: {'access_token': kakaoAccessToken},
    );

    if (r.statusCode != null && r.statusCode! ~/ 100 == 2) {
      final data = r.data is Map<String, dynamic>
          ? r.data as Map<String, dynamic>
          : (r.data is String
                ? jsonDecode(r.data as String) as Map<String, dynamic>
                : <String, dynamic>{});

      return AuthTokens.fromJson(data);
    }
    throw _httpStatusException('카카오 로그인에 실패했습니다.', r.statusCode);
  }

  /// 로컬 Web RAG 데모용 일반 사용자 로그인. 토큰 저장은 호출자가 담당한다.
  Future<AuthTokens> loginLocalDemo({
    required String username,
    required String password,
  }) async {
    if (AppConfig.isPortfolioPreview) {
      throw const PortfolioPreviewUnavailableException();
    }
    if (!AppConfig.isRealRagDemo) {
      throw StateError('Local Demo Login is only available in REAL_RAG_DEMO.');
    }

    final response = await _dio.post(
      AppConfig.authLocalDemoPath,
      data: {'username': username, 'password': password},
      options: Options(extra: const {'skipAuth': true}),
    );
    final data = response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : (response.data is String
              ? jsonDecode(response.data as String) as Map<String, dynamic>
              : <String, dynamic>{});
    final tokens = AuthTokens.fromJson(data);
    if (tokens.access.isEmpty || tokens.refresh.isEmpty) {
      throw const FormatException('JWT response is missing required tokens.');
    }
    return tokens;
  }

  // ----------------- API들 (기존 유지 + Timeout 메시지 명확화) -----------------
  Future<List<DocumentItem>> fetchDocs() async {
    if (kUseMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      return [
        DocumentItem(id: 101, title: '머신러닝 개론 - 신경망 기초.pdf'),
        DocumentItem(id: 102, title: '데이터베이스 시스템 - 인덱스와 트랜잭션.pdf'),
        DocumentItem(id: 103, title: '운영체제 - 프로세스와 스케줄링.pdf'),
      ];
    }

    final uri = Uri.parse('${AppConfig.baseUrl}${AppConfig.docsPath}');
    try {
      final resp = await _retryOn401(() async {
        return _client.get(uri, headers: await _authHeaders()).timeout(timeout);
      });

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final list = jsonDecode(utf8.decode(resp.bodyBytes));
        return (list as List).map((e) => DocumentItem.fromJson(e)).toList();
      }
      throw _httpStatusException(
        '문서 목록을 불러오지 못했습니다.',
        resp.statusCode,
      );
    } on TimeoutException {
      throw const HttpException(
        '요청 시간이 초과되었습니다(fetchDocs). 서버가 혼잡하거나 네트워크 지연이 있을 수 있습니다.',
      );
    }
  }

  // 문서 삭제 API
  Future<void> deleteDoc(int docId) async {
    if (kUseMock) {
      throw const PortfolioPreviewUnavailableException();
    }

    final uri = Uri.parse('${AppConfig.baseUrl}${AppConfig.docsPath}$docId/');

    try {
      final resp = await _retryOn401(() async {
        return _client
            .delete(uri, headers: await _authHeaders())
            .timeout(timeout);
      });

      if (resp.statusCode ~/ 100 != 2) {
        throw _httpStatusException('문서 삭제에 실패했습니다.', resp.statusCode);
      }
    } on TimeoutException {
      throw const HttpException(
        '요청 시간이 초과되었습니다(deleteDoc). 서버가 문서를 삭제 처리 중일 수 있습니다.',
      );
    }
  }

  Future<void> renameDoc(int docId, String newTitle) async {
    if (kUseMock) {
      throw const PortfolioPreviewUnavailableException();
    }

    // 예: /api/docs/3/ 에 PATCH
    final uri = Uri.parse('${AppConfig.baseUrl}/api/docs/$docId/');
    final body = jsonEncode({'title': newTitle});

    try {
      final resp = await _retryOn401(() async {
        return _client
            .patch(uri, headers: await _authHeaders(), body: body)
            .timeout(timeout);
      });

      if (resp.statusCode ~/ 100 != 2) {
        throw _httpStatusException(
          '문서 이름 변경에 실패했습니다.',
          resp.statusCode,
        );
      }
    } on TimeoutException {
      throw const HttpException('요청 시간이 초과되었습니다(renameDoc). 네트워크 상태를 확인해 주세요.');
    }
  }

  Future<List<String>> summarizeForDoc(int docId) async {
    if (kUseMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      return [
        '문서 텍스트를 의미 단위 Chunk로 분할하고 각 Chunk의 임베딩을 생성합니다.',
        '질문과 유사한 Chunk를 FAISS에서 검색해 답변 생성에 필요한 문맥으로 사용합니다.',
        '신경망 학습은 순전파, 손실 계산, 역전파, 가중치 갱신 순서로 진행됩니다.',
        '과적합을 줄이기 위해 검증 데이터, 정규화, Dropout과 조기 종료를 활용할 수 있습니다.',
        '핵심 키워드: Embedding, FAISS, RAG, 역전파, 최적화',
      ];
    }

    final uri = Uri.parse(
      '${AppConfig.baseUrl}${AppConfig.summarizeForDocPath}',
    );
    final body = jsonEncode({'doc_id': docId});

    try {
      final resp = await _retryOn401(() async {
        return _client
            .post(uri, headers: await _authHeaders(), body: body)
            .timeout(timeout);
      });

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
        if (decoded is Map && decoded['bullets'] is List) {
          return (decoded['bullets'] as List).map((e) => e.toString()).toList();
        }
        return decoded
            .toString()
            .split(RegExp(r'\r?\n'))
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }
      throw _httpStatusException('문서 요약에 실패했습니다.', resp.statusCode);
    } on TimeoutException {
      throw const HttpException(
        '요청 시간이 초과되었습니다(summarizeForDoc). 서버 처리 시간이 길어질 수 있습니다.',
      );
    }
  }

  Future<String> askGptForDoc(int docId, String question) async {
    if (kUseMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      return '질문: "$question"\n\n'
          '이 문서에서는 모델이 입력값을 순전파해 예측을 만들고, 손실 함수의 기울기를 역전파해 가중치를 갱신한다고 설명합니다. '
          'RAG 검색 결과 관련 내용이 포함된 강의 Chunk를 우선 참고했습니다.\n\n'
          '근거: Chunk 12 (p.8), Chunk 18 (p.11)';
    }

    final uri = Uri.parse('${AppConfig.baseUrl}${AppConfig.askGptPath}');
    final body = jsonEncode({'question': question, 'doc_id': docId});

    try {
      final resp = await _retryOn401(() async {
        return _client
            .post(uri, headers: await _authHeaders(), body: body)
            .timeout(timeout);
      });

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        return (data['answer'] ??
                data['response'] ??
                data['content'] ??
                data['message'] ??
                data)
            .toString();
      }
      throw _httpStatusException('질의응답 요청에 실패했습니다.', resp.statusCode);
    } on TimeoutException {
      throw const HttpException(
        '요청 시간이 초과되었습니다(askGptForDoc). 네트워크 상태를 확인해 주세요.',
      );
    }
  }

  Future<int> uploadPdf({
    required String fileName,
    String? filePath,
    Uint8List? bytes,
  }) async {
    if (kUseMock) {
      throw const PortfolioPreviewUnavailableException();
    }

    final MultipartFile pdfFile;
    if (kIsWeb) {
      if (bytes == null || bytes.isEmpty) {
        throw const HttpException('PDF 파일을 읽을 수 없습니다.');
      }
      pdfFile = MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType('application', 'pdf'),
      );
    } else {
      if (filePath == null || filePath.isEmpty) {
        throw const HttpException('PDF 파일을 읽을 수 없습니다.');
      }
      pdfFile = await MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: DioMediaType('application', 'pdf'),
      );
    }

    final form = FormData.fromMap({
      'file': pdfFile,
    });

    try {
      final resp = await _dio.post(AppConfig.uploadPath, data: form);

      if (resp.statusCode != null && resp.statusCode! ~/ 100 == 2) {
        final data = resp.data;
        final dynamic id = data is Map
            ? (data['doc_id'] ?? data['id'] ?? data['file_id'])
            : null;
        if (id is int) return id;
        if (id is String) return int.parse(id);
        throw const HttpException('업로드는 성공했지만 doc_id/id 필드가 응답에 없습니다.');
      }
      throw _httpStatusException('PDF 업로드에 실패했습니다.', resp.statusCode);
    } on DioException catch (e) {
      // ✅ 세션 만료
      if (e.error is SessionExpiredException) {
        throw e.error!;
      }
      throw const HttpException('PDF 업로드에 실패했습니다.');
    }
  }

  Future<void> ingestDoc(int docId) async {
    if (kUseMock) {
      throw const PortfolioPreviewUnavailableException();
    }

    final uri = Uri.parse('${AppConfig.baseUrl}${AppConfig.ingestPath}');
    final body = jsonEncode({'doc_id': docId});

    try {
      final resp = await _retryOn401(() async {
        return _client
            .post(uri, headers: await _authHeaders(), body: body)
            .timeout(timeout);
      });

      if (resp.statusCode ~/ 100 != 2) {
        throw _httpStatusException('PDF 분석에 실패했습니다.', resp.statusCode);
      }
    } on TimeoutException {
      throw const HttpException(
        '요청 시간이 초과되었습니다(ingestDoc). 서버가 문서를 처리 중일 수 있습니다.',
      );
    }
  }

  // ----------------- ⬇️ 학습노트 API (무거운 작업: Dio로 호출) -----------------
  Future<StudyNotes> summarizeStudyNotes(
    int docId, {
    String depth = "normal",
    int k = 5,
  }) async {
    if (kUseMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      return StudyNotes(
        markdown:
            '# 신경망 기초 학습노트\n\n'
            '## 핵심 흐름\n'
            '1. 입력 데이터를 모델에 전달해 예측값을 계산합니다.\n'
            '2. 손실 함수로 예측과 정답의 차이를 측정합니다.\n'
            '3. 역전파로 각 가중치의 기울기를 구합니다.\n'
            '4. 옵티마이저가 학습률에 따라 가중치를 갱신합니다.\n\n'
            '## 핵심 키워드\n'
            '- 순전파와 역전파\n'
            '- 손실 함수\n'
            '- 경사하강법\n'
            '- 과적합과 정규화\n',
        sources: [
          SourceHit(
            index: 12,
            page: 8,
            snippet: '역전파는 손실 함수의 기울기를 출력층에서 입력층 방향으로 전달합니다.',
          ),
          SourceHit(
            index: 18,
            page: 11,
            snippet: 'Dropout과 조기 종료는 과적합을 줄이기 위한 대표적인 방법입니다.',
          ),
        ],
        images: const [],
      );
    }

    try {
      final resp = await _dio.post(
        '/api/summarize/notes/',
        data: {"doc_id": docId, "depth": depth, "k": k},
        options: Options(
          receiveTimeout: const Duration(seconds: 180),
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (resp.statusCode != null && resp.statusCode! ~/ 100 == 2) {
        final data = resp.data is Map<String, dynamic>
            ? resp.data as Map<String, dynamic>
            : (resp.data is String
                  ? jsonDecode(resp.data as String) as Map<String, dynamic>
                  : <String, dynamic>{});
        return StudyNotes.fromJson(data);
      }
      throw _httpStatusException('학습노트 생성에 실패했습니다.', resp.statusCode);
    } on DioException catch (e) {
      // ✅ 세션 만료는 그대로 위로
      if (e.error is SessionExpiredException) {
        throw e.error!;
      }

      if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        throw const HttpException(
          '타임아웃: 학습노트 생성에 시간이 더 필요합니다. 잠시 후 다시 시도해 주세요.',
        );
      }
      throw _httpStatusException(
        '학습노트 생성에 실패했습니다.',
        e.response?.statusCode,
      );
    }
  }

  // ----------------- ⬇️ 스냅샷 생성 API (무거운 작업: Dio로 호출) -----------------
  /// 서버가 중요 페이지를 PNG로 렌더링해 저장하고, 저장된 이미지 메타를 돌려줌
  /// - 서버: POST /api/notes/snapshots/  { "doc_id": int, "top_k": 5, "zoom": 2.0 }
  /// - 응답: { ok, saved, images: [ { page,url,width,height,score }, ... ] }
  Future<List<PageImage>> generateSnapshots(
    int docId, {
    int topK = 5,
    double zoom = 2.0,
  }) async {
    if (kUseMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      return const [];
    }

    try {
      final resp = await _dio.post(
        '/api/notes/snapshots/',
        data: {"doc_id": docId, "top_k": topK, "zoom": zoom},
        options: Options(
          receiveTimeout: const Duration(seconds: 180),
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (resp.statusCode != null && resp.statusCode! ~/ 100 == 2) {
        final m = resp.data is Map<String, dynamic>
            ? resp.data as Map<String, dynamic>
            : (resp.data is String
                  ? jsonDecode(resp.data as String) as Map<String, dynamic>
                  : <String, dynamic>{});
        final imgs = (m['images'] as List? ?? [])
            .map((e) => PageImage.fromJson(e as Map<String, dynamic>))
            .toList();
        return imgs;
      }
      throw _httpStatusException('스냅샷 생성에 실패했습니다.', resp.statusCode);
    } on DioException catch (e) {
      // ✅ 세션 만료는 그대로 위로
      if (e.error is SessionExpiredException) {
        throw e.error!;
      }

      if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        throw const HttpException(
          '타임아웃: 스냅샷 생성에 시간이 더 필요합니다. 잠시 후 다시 시도해 주세요.',
        );
      }
      throw _httpStatusException(
        '스냅샷 생성에 실패했습니다.',
        e.response?.statusCode,
      );
    }
  }
}

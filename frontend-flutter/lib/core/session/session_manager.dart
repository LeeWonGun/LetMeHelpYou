import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT 세션 보관/갱신 헬퍼 (SSOT)
class SessionManager {
  SessionManager._();
  static final SessionManager I = SessionManager._();

  // 필요한 옵션이 있으면 여기서 설정 (기본은 안전한 기본값)
  final _store = const FlutterSecureStorage();

  // 키 상수
  static const _kAccess = 'access';
  static const _kRefresh = 'refresh';

  /// access/refresh 둘 다 존재하는지만 빠르게 확인
  Future<bool> hasValidSession() async {
    final a = await accessToken;
    final r = await refreshToken;
    return (a?.isNotEmpty == true) && (r?.isNotEmpty == true);
  }

  /// 두 토큰을 한 번에 저장
  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _store.write(key: _kAccess, value: access);
    await _store.write(key: _kRefresh, value: refresh);
  }

  /// 🔁 리프레시 성공 후 새 access만 덮어쓸 때 사용
  Future<void> saveAccess(String access) async {
    await _store.write(key: _kAccess, value: access);
  }

  /// (선택) 새 refresh만 바꿔야 할 때
  Future<void> saveRefresh(String refresh) async {
    await _store.write(key: _kRefresh, value: refresh);
  }

  /// 로그아웃: 세션 키만 정리
  Future<void> logout() async {
    await _store.delete(key: _kAccess);
    await _store.delete(key: _kRefresh);
  }

  /// Getter
  Future<String?> get accessToken async => _store.read(key: _kAccess);
  Future<String?> get refreshToken async => _store.read(key: _kRefresh);

  // ---------------------------
  // (옵션) 디버깅/UX 보조 유틸
  // ---------------------------

  /// access 토큰이 만료로 보이는지 (exp 필드 기준, 실패 시 null)
  Future<bool?> get isAccessExpired async => _isExpired(await accessToken);

  /// refresh 토큰이 만료로 보이는지 (exp 필드 기준, 실패 시 null)
  Future<bool?> get isRefreshExpired async => _isExpired(await refreshToken);

  Future<bool?> _isExpired(String? jwt) async {
    try {
      if (jwt == null || jwt.isEmpty) return null;
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      String norm(String s) => s.padRight(s.length + (4 - s.length % 4) % 4, '=')
          .replaceAll('-', '+').replaceAll('_', '/');
      final payload = jsonDecode(utf8.decode(base64Url.decode(norm(parts[1]))));
      final exp = payload['exp'];
      if (exp is! int) return null;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return now >= exp;
    } catch (_) {
      return null; // 파싱 실패 → 판단 불가
    }
  }
}

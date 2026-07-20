import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../api_client.dart';
import '../config.dart';
import '../ui/widgets.dart';
import '../core/session/session_manager.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (AppConfig.isPortfolioPreview) {
      showSnackBar(context, AppConfig.portfolioPreviewUnavailableMessage);
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      // 1) 카카오 계정 로그인
      final kakaoToken = await UserApi.instance.loginWithKakaoAccount();

      // 2) 우리 서버에 카카오 access_token 보내서 JWT 교환
      final tokens = await ApiClient().loginWithKakao(kakaoToken.accessToken);

      // 3) SSOT에 저장
      await SessionManager.I.saveTokens(
        access: tokens.access,
        refresh: tokens.refresh,
      );

      if (!mounted) return;
      // 4) 문서 목록 화면으로 이동
      Navigator.pushReplacementNamed(context, '/docs');
    } catch (e) {
      // ✅ 1단계: 네트워크 에러인지 공통 헬퍼로 먼저 체크
      final handled = await handleNetworkError(context, e);
      if (handled) {
        // 네트워크 문제인 경우: 다이얼로그만 띄우고 여기서 종료
        // (에러 배너는 굳이 안 띄움)
        return;
      }

      // ✅ 2단계: 네트워크 이외의 에러만 화면에 표시
      setState(() => _err = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _enterPortfolioPreview() {
    if (!AppConfig.isPortfolioPreview) return;
    Navigator.pushReplacementNamed(context, '/docs');
  }

  Future<void> _loginLocalDemo() async {
    if (!AppConfig.isRealRagDemo || _busy) return;

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _err = '사용자명과 비밀번호를 입력해 주세요.');
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      final tokens = await ApiClient().loginLocalDemo(
        username: username,
        password: password,
      );
      await SessionManager.I.saveTokens(
        access: tokens.access,
        refresh: tokens.refresh,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/docs');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _err = '로컬 데모 로그인에 실패했습니다. 계정 정보와 Backend 설정을 확인해 주세요.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '로그인',
      child: SectionCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.school, size: 56),
            const SizedBox(height: 12),
            Text(
              'Lecture AI',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (_err != null) ...[
              ErrorBanner(message: _err!),
              const SizedBox(height: 8),
            ],
            if (AppConfig.isRealRagDemo) ...[
              TextField(
                controller: _usernameController,
                enabled: !_busy,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '사용자명',
                  hintText: 'portfolio_demo',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                enabled: !_busy,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _loginLocalDemo(),
                decoration: const InputDecoration(labelText: '비밀번호'),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                onPressed: _busy ? null : _loginLocalDemo,
                icon: Icons.science_outlined,
                label: Text(_busy ? '로그인 중…' : '로컬 RAG 데모 로그인'),
              ),
              const SizedBox(height: 16),
            ],
            PrimaryButton(
              onPressed: _busy || AppConfig.isRealRagDemo ? null : _login,
              icon: Icons.login,
              label: Text(_busy ? '로그인 중…' : '카카오로 시작하기'),
            ),
            if (AppConfig.isPortfolioPreview) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _enterPortfolioPreview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('포트폴리오 미리보기'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

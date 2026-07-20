import 'package:flutter/material.dart';
import 'ui/app_theme.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'config.dart';

// Screens
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/document_list_screen.dart';
import 'screens/document_detail_screen.dart';
import 'screens/summarize_screen.dart';
import 'screens/ask_gpt_screen.dart';
import 'screens/upload_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isPortfolioPreview && !AppConfig.isRealRagDemo) {
    const kakaoNativeAppKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');
    if (kakaoNativeAppKey.trim().isEmpty) {
      throw StateError(
        'KAKAO_NATIVE_APP_KEY must be provided with --dart-define.',
      );
    }

    // 🔑 카카오 SDK 초기화
    KakaoSdk.init(
      nativeAppKey: kakaoNativeAppKey,
      // javaScriptAppKey: String.fromEnvironment('KAKAO_JAVASCRIPT_APP_KEY'),
      // loggingEnabled: true,
    );
  }

  runApp(const LectureAiApp());
}

class LectureAiApp extends StatelessWidget {
  const LectureAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lecture AI',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,

      // ✅ 스플래시를 초기 라우트로
      initialRoute: '/splash',

      // ✅ 라우트 테이블
      routes: {
        '/splash': (_) => const SplashScreen(), // 자동 로그인 분기
        '/login': (_) => const LoginScreen(),
        '/docs': (_) => const DocumentListScreen(), // 홈 격 화면
        '/doc': (_) => const DocumentDetailScreen(),
        '/summary': (_) => const SummarizeScreen(),
        '/ask': (_) => const AskGptScreen(),
        '/upload': (_) => const UploadScreen(),
      },
    );
  }
}

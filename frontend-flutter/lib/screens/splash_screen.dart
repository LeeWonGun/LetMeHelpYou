import 'package:flutter/material.dart';
import '../config.dart';
import '../core/session/session_manager.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    // 약간의 연출
    await Future.delayed(const Duration(milliseconds: 300));
    if (AppConfig.isPortfolioPreview) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final access = await SessionManager.I.accessToken;
    if (!mounted) return;
    if (access != null && access.isNotEmpty) {
      Navigator.pushReplacementNamed(context, '/docs');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
}

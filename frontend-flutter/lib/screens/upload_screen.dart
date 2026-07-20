import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart'; // 파일 피커 (PDF 선택)
import '../api_client.dart';
import '../config.dart';
import '../ui/widgets.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  bool _busy = false;
  String? _err;
  PlatformFile? _pickedFile;

  // ✅ 세션 만료 처리 중복 방지용 플래그 (선택이지만 있으면 안전)
  bool _sessionExpiredHandled = false;

  // ✅ 실제 파일 선택 로직
  Future<void> _pick() async {
    if (AppConfig.isPortfolioPreview) {
      showSnackBar(context, AppConfig.portfolioPreviewUnavailableMessage);
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'], // PDF만
        withData: kIsWeb,
      );
      if (!mounted) return;

      if (result == null || result.files.isEmpty) {
        // 사용자가 취소한 경우
        return;
      }

      final file = result.files.single;
      final extension = file.extension?.toLowerCase();
      if (extension != 'pdf' && !file.name.toLowerCase().endsWith('.pdf')) {
        showSnackBar(context, 'PDF 파일만 선택할 수 있습니다.');
        return;
      }
      if (kIsWeb && (file.bytes == null || file.bytes!.isEmpty)) {
        showSnackBar(context, 'PDF 파일을 읽을 수 없습니다.');
        return;
      }
      if (!kIsWeb && (file.path == null || file.path!.isEmpty)) {
        showSnackBar(context, 'PDF 파일을 읽을 수 없습니다.');
        return;
      }

      setState(() {
        _pickedFile = file;
        _err = null;
      });

      showSnackBar(context, '선택된 파일: ${file.name}');
    } catch (_) {
      if (!mounted) return;
      showSnackBar(context, 'PDF 파일을 읽을 수 없습니다.');
    }
  }

  Future<void> _upload() async {
    if (AppConfig.isPortfolioPreview) {
      showSnackBar(context, AppConfig.portfolioPreviewUnavailableMessage);
      return;
    }
    final pickedFile = _pickedFile;
    if (pickedFile == null) {
      showSnackBar(context, '먼저 PDF를 선택하세요.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });

    var uploadCompleted = false;
    try {
      final id = await ApiClient().uploadPdf(
        fileName: pickedFile.name,
        filePath: pickedFile.path,
        bytes: pickedFile.bytes,
      );
      uploadCompleted = true;
      await ApiClient().ingestDoc(id);

      if (!mounted) return;
      showSnackBar(context, '업로드 및 분석이 완료되었습니다.');
      Navigator.pop(context, true); // 목록 새로고침 신호
    } catch (e) {
      // ✅ 세션 만료 처리
      if (e is SessionExpiredException) {
        if (!_sessionExpiredHandled) {
          _sessionExpiredHandled = true;

          if (mounted) {
            // 로그인 화면으로 네비게이션
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (route) => false);
            // 안내 스낵바
            showSnackBar(context, e.message);
          }
        }
        // 더 이상 아래 일반 오류 처리는 하지 않고 반환
        return;
      }

      // ✅ 네트워크 에러 다이얼로그 (앱은 종료하지 않음)
      if (!mounted) return;
      await handleNetworkError(context, e, exitOnClose: false);

      // ✅ 일반 오류 메시지도 화면 상단 배너로 보여주기
      if (mounted) {
        setState(
          () => _err = uploadCompleted
              ? 'PDF 분석에 실패했습니다.'
              : 'PDF 업로드에 실패했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '강의 자료 올리기',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_err != null) ...[
            ErrorBanner(message: _err!),
            const SizedBox(height: 8),
          ],
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PDF 파일을 선택해 업로드합니다.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pick,
                        icon: const Icon(Icons.folder_open),
                        label: Text(_pickedFile == null ? '파일 선택' : '다시 선택'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _upload,
                        icon: const Icon(Icons.cloud_upload),
                        label: Text(_busy ? '업로드 중…' : '업로드'),
                      ),
                    ),
                  ],
                ),
                if (_pickedFile != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    _pickedFile!.name,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

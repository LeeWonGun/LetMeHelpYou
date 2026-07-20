import 'package:flutter/material.dart';
import '../api_client.dart';
import '../models.dart';
import '../ui/widgets.dart';
import '../ui/clipboard_and_save.dart';

class SummarizeScreen extends StatefulWidget {
  const SummarizeScreen({super.key});
  @override
  State<SummarizeScreen> createState() => _SummarizeScreenState();
}

class _SummarizeScreenState extends State<SummarizeScreen> {
  late Future<List<String>> _future;
  late DocumentItem doc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    doc = ModalRoute.of(context)!.settings.arguments as DocumentItem;
    _future = ApiClient().summarizeForDoc(doc.id);
  }

  void _reload() {
    setState(() => _future = ApiClient().summarizeForDoc(doc.id));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '요약 · ${doc.title}',
      child: FutureBuilder<List<String>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingView(message: '요약 생성 중…');
          }
          if (snap.hasError) {
            return ErrorView('요약을 가져오지 못했습니다.\n${snap.error}', onRetry: _reload);
          }

          final bullets = snap.data ?? [];
          if (bullets.isEmpty) {
            return EmptyView(
              title: '요약 결과가 없습니다.',
              subtitle: '문서를 다시 인덱싱한 뒤 시도해 보세요.',
              action: PrimaryButton(
                onPressed: _reload,
                icon: Icons.refresh,
                label: const Text('다시 시도'),
              ),
            );
          }

          return SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더 + 전체 복사 버튼
                Row(
                  children: [
                    Text('요약', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    IconButton(
                      tooltip: '요약 복사',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => copyToClipboard(
                        context,
                        bullets.join('\n'),
                        ok: '요약을 클립보드에 복사했어요.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 본문 목록
                for (final b in bullets)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: Text(b)),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

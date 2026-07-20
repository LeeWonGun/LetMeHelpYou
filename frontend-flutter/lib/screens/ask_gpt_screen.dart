import 'package:flutter/material.dart';
import '../api_client.dart';
import '../models.dart';
import '../ui/clipboard_and_save.dart';

class AskGptScreen extends StatefulWidget {
  const AskGptScreen({super.key});
  @override
  State<AskGptScreen> createState() => _AskGptScreenState();
}

class _AskGptScreenState extends State<AskGptScreen> {
  final _api = ApiClient();
  final _controller = TextEditingController();
  String? _answer;
  String? _error;
  bool _loading = false;

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() => _error = '질문을 입력하세요.');
      return;
    }

    final doc = ModalRoute.of(context)!.settings.arguments as DocumentItem;

    setState(() {
      _loading = true;
      _error = null;
      _answer = null;
    });
    try {
      final res = await _api.askGptForDoc(doc.id, q);
      setState(() => _answer = res);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final doc = ModalRoute.of(context)!.settings.arguments as DocumentItem;

    return Scaffold(
      appBar: AppBar(title: Text('질의응답 · ${doc.title}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: '질문을 입력하세요',
                hintText: '예) 3강 핵심 개념 요약해줘',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _send,
                icon: const Icon(Icons.send),
                label: const Text('질문 보내기'),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading) const LinearProgressIndicator(),

            // 에러 카드
            if (_error != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Card(
                    color: th.colorScheme.errorContainer.withOpacity(0.15),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _error!,
                        style: th.textTheme.bodyMedium!
                            .copyWith(color: th.colorScheme.error),
                      ),
                    ),
                  ),
                ),
              ),

            // 답변 카드 + 복사 버튼
            if (_answer != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('답변', style: th.textTheme.titleMedium),
                              const Spacer(),
                              IconButton(
                                tooltip: '답변 복사',
                                icon: const Icon(Icons.copy_rounded),
                                onPressed: () => copyToClipboard(
                                  context,
                                  _answer!,
                                  ok: '답변을 클립보드에 복사했어요.',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            _answer!,
                            style: th.textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

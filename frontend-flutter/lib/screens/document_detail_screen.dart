// lib/screens/document_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart'; // ✅ 클립보드
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../api_client.dart';
import '../config.dart';
import '../models.dart';
import '../ui/widgets.dart';
import '../ui/clipboard_and_save.dart'; // ✅ saver_gallery 유틸

class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({super.key});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen>
    with SingleTickerProviderStateMixin {
  late final DocumentItem doc;
  bool _inited = false;
  bool _isPdfLoading = true;
  String? _pdfLoadError;
  Key _pdfKey = UniqueKey();

  late final TabController _tab;

  // 요약 탭
  Future<List<String>>? _summaryFuture;

  // 학습노트 탭
  String _depth = 'normal'; // brief | normal | deep
  Future<StudyNotes>? _notesFuture;
  int _lastSnapshotCount = 0;

  // Q&A 탭
  final TextEditingController _q = TextEditingController();
  Future<String>? _answerFuture;

  // ✅ 세션 만료 처리 중복 방지 플래그
  bool _sessionExpiredHandled = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this); // 개요 / 요약 / 학습노트 / Q&A
  }

  @override
  void dispose() {
    _q.dispose();
    _tab.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is DocumentItem) {
      doc = args;
      _resetPdfState();
      _inited = true;

      // 초기 진입 시 요약만 자동 로딩
      _summaryFuture = ApiClient().summarizeForDoc(doc.id);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  void _reloadSummary() {
    setState(() {
      _summaryFuture = ApiClient().summarizeForDoc(doc.id);
    });
  }

  void _resetPdfState() {
    _isPdfLoading = true;
    _pdfLoadError = null;
    _pdfKey = UniqueKey(); // 재시도 시 SfPdfViewer 강제 재생성
  }

  void _retryPdf() {
    if (!mounted) return;
    setState(_resetPdfState);
  }

  // ✅ 공용: SessionExpiredException이면 로그인으로 보내고 true 반환
  bool _handleSessionExpired(Object? err) {
    if (_sessionExpiredHandled) return true; // 이미 처리했으면 무시
    if (err is! SessionExpiredException) return false;

    _sessionExpiredHandled = true;

    // 다음 프레임에서 네비게이션 (build 중 네비게이션 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 로그인 화면으로 이동
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      // 안내 스낵바
      showSnackBar(context, err.message);
    });

    return true;
  }

  // ⚙️ 스냅샷 생성 → 학습노트 생성 순차 호출
  Future<void> _loadSnapshotsThenNotes() async {
    setState(() {
      _notesFuture = null; // 로딩 화면을 보이기 위해 일단 비움
      _lastSnapshotCount = 0;
    });
    try {
      // (1) 중요 페이지 스냅샷 생성/갱신
      final imgs = await ApiClient().generateSnapshots(
        doc.id,
        topK: 5,
        zoom: 2.0,
      );
      _lastSnapshotCount = imgs.length;

      // (2) 학습노트 생성/갱신
      setState(() {
        _notesFuture = ApiClient().summarizeStudyNotes(
          doc.id,
          depth: _depth,
          k: 5,
        );
      });
    } catch (e) {
      // ✅ 세션 만료라면 여기서 바로 처리하고 종료
      if (_handleSessionExpired(e)) return;

      // ✅ 네트워크 에러라면 공통 헬퍼로 처리 (앱 강제 종료 X)
      final handled = await handleNetworkError(context, e, exitOnClose: false);
      if (handled) {
        // 다이얼로그만 띄우고, 화면은 "아직 생성하지 않았습니다" 상태로 유지
        setState(() {
          _notesFuture = null;
          _lastSnapshotCount = 0;
        });
        return;
      }

      // 그 외 에러는 화면에 ErrorView로 보여주기 위해 Future.error로 넘김
      setState(() {
        _notesFuture = Future.error(e);
      });
    }
  }

  void _ask() {
    final question = _q.text.trim();
    if (question.isEmpty) return;
    setState(() {
      _answerFuture = ApiClient().askGptForDoc(doc.id, question);
    });
  }

  /// 공용 전체 복사 헬퍼
  void _copyToClipboard(String label, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      showSnackBar(context, '$label 복사할 내용이 없습니다.');
      return;
    }

    Clipboard.setData(ClipboardData(text: trimmed));
    showSnackBar(context, '$label 전체를 클립보드에 복사했어요.');
  }

  Widget _buildPortfolioPdfPreview() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              color: Colors.white,
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text(
                          '강의 자료 페이지 미리보기',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 24),
                    Text(
                      '03. 신경망 학습의 핵심 흐름',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      '입력 → 순전파 → 손실 계산 → 역전파 → 가중치 갱신',
                      style: TextStyle(color: Colors.black87, fontSize: 17),
                    ),
                    SizedBox(height: 18),
                    Divider(),
                    SizedBox(height: 14),
                    Text(
                      '• 임베딩으로 문서 Chunk의 의미를 벡터화\n'
                      '• FAISS에서 질문과 유사한 Chunk 검색\n'
                      '• 검색된 근거를 활용해 RAG 답변 생성',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        height: 1.7,
                      ),
                    ),
                    SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Preview page 8 / 24',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_inited) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title, overflow: TextOverflow.ellipsis),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '개요'),
            Tab(text: '요약'),
            Tab(text: '학습노트'),
            Tab(text: 'Q&A'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ─────────────────────────────────────────────
          // 0) 개요 탭 + 원본 PDF 뷰어
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 상단 설명 카드 (이건 그대로 둬도 됨)
                SectionCard(
                  title: '문서 개요',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.title,
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '원본 강의 자료 PDF를 아래에서 그대로 볼 수 있어요.\n'
                        '상단 탭을 이용해 요약, 학습노트, Q&A 기능도 함께 활용해 보세요.\n'
                        '크기가 큰 원본 PDF 파일은 불러오는데 시간이 오래 걸릴 수 있습니다.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ⬇️ 여기부터는 SectionCard 없이 Expanded 로 PDF 꽉 채우기
                Expanded(
                  child: AppConfig.isPortfolioPreview
                      ? _buildPortfolioPdfPreview()
                      : Stack(
                          children: [
                            SfPdfViewer.network(
                              doc.fileUrl!,
                              key: _pdfKey,
                              canShowScrollHead: true,
                              canShowScrollStatus: true,
                              onDocumentLoaded: (details) {
                                if (!mounted) return;
                                setState(() {
                                  _isPdfLoading = false;
                                  _pdfLoadError = null; // ✅ 성공 시 에러 초기화
                                });
                              },
                              onDocumentLoadFailed: (details) {
                                if (!mounted) return;
                                setState(() {
                                  _isPdfLoading = false;
                                  _pdfLoadError = details.description;
                                });
                                final err = details.error;
                                handleNetworkError(
                                  context,
                                  err,
                                  exitOnClose: false,
                                );
                              },
                            ),

                            // ✅ 로딩 오버레이
                            if (_isPdfLoading)
                              Container(
                                color: Colors.black.withOpacity(0.25),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 12),
                                      Text(
                                        'PDF를 불러오는 중입니다.\n조금만 기다려 주세요.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // ✅ 실패 오버레이 (에러 + 재시도)
                            if (!_isPdfLoading && _pdfLoadError != null)
                              Container(
                                color: Colors.black.withOpacity(0.35),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 320,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.error_outline,
                                          size: 42,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'PDF를 불러오지 못했습니다.\n$_pdfLoadError',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        FilledButton.icon(
                                          onPressed: _retryPdf,
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('재시도'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),

          // ─────────────────────────────────────────────
          // 1) 요약 탭
          Padding(
            padding: const EdgeInsets.all(16),
            child: FutureBuilder<List<String>>(
              future: _summaryFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingView(message: '요약 생성 중…');
                }
                if (snap.hasError) {
                  final err = snap.error;

                  // ✅ 세션 만료 체크
                  if (_handleSessionExpired(err)) {
                    return const SizedBox.shrink();
                  }
                  // ✅ 네트워크 에러 다이얼로그 (앱 종료 X)
                  if (snap.error != null) {
                    handleNetworkError(context, err, exitOnClose: false);
                  }
                  return ErrorView(
                    '요약을 불러오지 못했습니다.\n$err',
                    onRetry: _reloadSummary,
                  );
                }
                final bullets = snap.data ?? const [];
                if (bullets.isEmpty) {
                  return EmptyView(
                    title: '요약이 없습니다',
                    subtitle: '다시 시도해 보세요.',
                    action: PrimaryButton(
                      onPressed: _reloadSummary,
                      icon: Icons.refresh,
                      label: const Text('다시 시도'),
                    ),
                  );
                }

                // ✅ 요약 전체 텍스트
                final summaryText = bullets.map((b) => '• $b').join('\n');

                return ListView(
                  children: [
                    SectionCard(
                      scrollable: true,
                      maxScrollHeight: 420,
                      headerActions: [
                        IconButton(
                          tooltip: '전체 복사',
                          onPressed: () => _copyToClipboard('요약', summaryText),
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final b in bullets) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('•  '),
                                Expanded(child: Text(b)),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // ─────────────────────────────────────────────
          // 2) 학습노트 탭
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      '깊이',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 40,
                      child: DropdownButton<String>(
                        value: _depth,
                        items: const [
                          DropdownMenuItem(value: 'brief', child: Text('간단히')),
                          DropdownMenuItem(value: 'normal', child: Text('보통')),
                          DropdownMenuItem(value: 'deep', child: Text('깊게')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _depth = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 40),
                            ),
                            onPressed: _loadSnapshotsThenNotes,
                            icon: const Icon(Icons.auto_fix_high),
                            label: const Text('생성 / 새로고침'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_lastSnapshotCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '추출된 이미지: $_lastSnapshotCount개',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                Expanded(
                  child: FutureBuilder<StudyNotes>(
                    future: _notesFuture,
                    builder: (context, snap) {
                      if (_notesFuture == null) {
                        return EmptyView(
                          title: '아직 생성하지 않았습니다',
                          subtitle: '위의 버튼을 눌러 학습노트를 만들어 보세요.',
                          action: PrimaryButton(
                            onPressed: _loadSnapshotsThenNotes,
                            icon: Icons.auto_fix_high,
                            label: const Text('지금 생성'),
                          ),
                        );
                      }
                      if (snap.connectionState != ConnectionState.done) {
                        return const LoadingView(message: '학습노트 생성 중…');
                      }
                      if (snap.hasError) {
                        final err = snap.error;

                        // ✅ 세션 만료 체크
                        if (_handleSessionExpired(err)) {
                          return const SizedBox.shrink();
                        }
                        // ✅ 네트워크 에러 다이얼로그
                        if (err != null) {
                          handleNetworkError(context, err, exitOnClose: false);
                        }
                        return ErrorView(
                          '생성 실패: $err',
                          onRetry: _loadSnapshotsThenNotes,
                        );
                      }
                      final notes = snap.data;
                      if (notes == null) {
                        return const EmptyView(
                          title: '생성 결과가 비었습니다',
                          subtitle: '다시 시도해 보세요.',
                        );
                      }

                      return ListView(
                        children: [
                          // 마크다운 학습노트 — 내부에서만 스크롤 + 전체 복사 버튼
                          SectionCard(
                            scrollable: false,
                            autoScrollForMarkdown: false,
                            headerActions: [
                              IconButton(
                                tooltip: '전체 복사',
                                onPressed: () =>
                                    _copyToClipboard('정리 노트', notes.markdown),
                                icon: const Icon(Icons.copy),
                              ),
                            ],
                            child: SizedBox(
                              height: 520,
                              child: Markdown(
                                data: notes.markdown,
                                selectable: true,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),
                          if (notes.images.isNotEmpty) ...[
                            Text(
                              '관련 페이지',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: notes.images.map((img) {
                                return InkWell(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => Dialog(
                                        child: Stack(
                                          children: [
                                            InteractiveViewer(
                                              maxScale: 5,
                                              child: Image.network(
                                                img.url,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                            Positioned(
                                              right: 8,
                                              top: 8,
                                              child: IconButton.filledTonal(
                                                tooltip: '갤러리에 저장',
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                  // ✅ saver_gallery 기반 공용 헬퍼
                                                  saveImageToGallery(
                                                    context,
                                                    img.url,
                                                    name: 'page_${img.page}',
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.download,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  onLongPress: () => saveImageToGallery(
                                    context,
                                    img.url,
                                    name: 'page_${img.page}',
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: SizedBox(
                                          width: 140,
                                          height: 90,
                                          child: Image.network(
                                            img.url,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'p.${img.page}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],

                          const SizedBox(height: 16),
                          if (notes.sources.isNotEmpty)
                            ExpansionTile(
                              title: const Text('근거 보기'),
                              children: notes.sources.map((s) {
                                final meta = [
                                  if (s.index != null) 'index=${s.index}',
                                  if (s.page != null) 'p.${s.page}',
                                ].join(' / ');
                                return ListTile(
                                  dense: true,
                                  title: Text(s.snippet),
                                  subtitle: meta.isEmpty ? null : Text(meta),
                                );
                              }).toList(),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ─────────────────────────────────────────────
          // 3) Q&A 탭
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _q,
                  decoration: const InputDecoration(
                    labelText: '질문을 입력하세요',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 4,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: _ask,
                      icon: const Icon(Icons.send),
                      label: const Text('질문하기'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<String>(
                    future: _answerFuture,
                    builder: (context, snap) {
                      if (_answerFuture == null) {
                        return const EmptyView(
                          title: '아직 질문하지 않았습니다',
                          subtitle: '위의 입력창에 질문을 적고 버튼을 눌러 보세요.',
                        );
                      }
                      if (snap.connectionState != ConnectionState.done) {
                        return const LoadingView(message: '답변 생성 중…');
                      }
                      if (snap.hasError) {
                        final err = snap.error;

                        // ✅ 세션 만료 체크
                        if (_handleSessionExpired(err)) {
                          return const SizedBox.shrink();
                        }
                        // ✅ 네트워크 에러 다이얼로그
                        if (err != null) {
                          handleNetworkError(context, err, exitOnClose: false);
                        }
                        return ErrorView('답변 생성 실패: $err', onRetry: _ask);
                      }
                      final ans = snap.data ?? '';
                      // 긴 답변 대비 내부 스크롤 + 전체 복사 버튼
                      return SectionCard(
                        headerActions: [
                          IconButton(
                            tooltip: '전체 복사',
                            onPressed: () => _copyToClipboard('답변', ans),
                            icon: const Icon(Icons.copy),
                          ),
                        ],
                        scrollable: true,
                        //maxScrollHeight: 420,
                        child: Text(ans),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

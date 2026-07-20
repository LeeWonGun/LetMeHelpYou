// lib/screens/document_list_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'; // kDebugMode, debugPrint
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../config.dart';
import '../models.dart';
import '../ui/widgets.dart';
import '../core/session/session_manager.dart'; // ✅ 세션 매니저

class DocumentListScreen extends StatefulWidget {
  const DocumentListScreen({super.key});
  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  static const Duration _docsTimeout = Duration(
    seconds: 8,
  ); // ✅ 로딩 너무 길면 빨리 타임아웃

  late Future<List<DocumentItem>> _future;

  // ✅ 문서 삭제용 상태
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  bool _deleting = false;

  // ✅ 현재 선택 모드가 "이름 바꾸기"인지 여부
  bool _renameMode = false;

  // ✅ 네트워크 에러 다이얼로그가 build 반복으로 여러 번 뜨는 것 방지
  bool _networkDialogShown = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) debugPrint('[DOCS] initState → fetchDocs');
    _future = _fetchDocsWithTimeout();
  }

  Future<List<DocumentItem>> _fetchDocsWithTimeout() {
    return ApiClient().fetchDocs().timeout(_docsTimeout);
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }

  void _reload() {
    _log('[DOCS] reload requested');
    setState(() {
      _networkDialogShown = false; // ✅ 다시 시도할 때는 다이얼로그 다시 허용
      _future = _fetchDocsWithTimeout();
    });
  }

  Future<void> _pullToRefresh() async {
    _log('[DOCS] pull-to-refresh');
    await Future.delayed(const Duration(milliseconds: 250));
    _reload();
    await _future.catchError((_) => <DocumentItem>[]);
  }

  Future<void> _goUpload() async {
    if (AppConfig.isPortfolioPreview) {
      _showPreviewUnavailable();
      return;
    }
    _log('[DOCS] navigate → /upload');
    final refresh = await Navigator.pushNamed(context, '/upload');
    _log('[DOCS] returned from /upload, refresh=$refresh');
    if (refresh == true && mounted) _reload();
  }

  Future<void> _logout(BuildContext context) async {
    if (AppConfig.isPortfolioPreview) {
      showSnackBar(context, AppConfig.portfolioPreviewUnavailableMessage);
      return;
    }
    _log('[DOCS] logout dialog open');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('정말 로그아웃할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );

    _log('[DOCS] logout dialog result = $ok');
    if (ok != true) return;

    await SessionManager.I.logout();
    _log('[DOCS] tokens cleared, navigating → /login');

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    showSnackBar(context, '로그아웃되었습니다.');
  }

  void _showPreviewUnavailable() {
    if (!mounted) return;
    showSnackBar(context, AppConfig.portfolioPreviewUnavailableMessage);
  }

  bool _isNetworkError(Object? err) {
    if (err == null) return false;
    return err is SocketException ||
        err is TimeoutException ||
        err is HttpException ||
        err.toString().contains('SocketException') ||
        err.toString().toLowerCase().contains('timed out');
  }

  // ✅ 선택 토글
  void _toggleSelect(int docId) {
    setState(() {
      if (_selectedIds.contains(docId)) {
        _selectedIds.remove(docId);
      } else {
        if (_renameMode) {
          _selectedIds
            ..clear()
            ..add(docId);
        } else {
          _selectedIds.add(docId);
        }
      }
    });
  }

  // ✅ 선택한 문서들 일괄 삭제
  Future<void> _deleteSelected() async {
    if (AppConfig.isPortfolioPreview) {
      _showPreviewUnavailable();
      return;
    }
    if (_selectedIds.isEmpty || _deleting) return;

    final ids = _selectedIds.toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('문서 삭제'),
        content: Text('선택한 문서 ${ids.length}개를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _deleting = true);
    final api = ApiClient();

    int successCount = 0;
    int failCount = 0;

    try {
      for (final id in ids) {
        try {
          await api.deleteDoc(id);
          successCount++;
        } on SessionExpiredException catch (e) {
          if (!mounted) return;

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await SessionManager.I.logout();
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (route) => false);
            showSnackBar(context, e.message);
          });
          return;
        } catch (e) {
          failCount++;
          if (mounted) {
            await handleNetworkError(context, e, exitOnClose: false);
          }
        }
      }

      if (!mounted) return;

      String msg;
      if (successCount == 0) {
        msg = '문서 삭제에 실패했습니다.';
      } else if (failCount == 0) {
        msg = '선택한 문서 ${successCount}개를 삭제했습니다.';
      } else {
        msg = '문서 ${successCount}개 삭제, ${failCount}개 삭제 실패했습니다.';
      }
      showSnackBar(context, msg);

      if (successCount > 0) {
        setState(() {
          _selectionMode = false;
          _selectedIds.clear();
          _networkDialogShown = false;
          _future = _fetchDocsWithTimeout();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  // ✅ 선택한 문서 이름 바꾸기
  Future<void> _renameSelected() async {
    if (AppConfig.isPortfolioPreview) {
      _showPreviewUnavailable();
      return;
    }
    if (_selectedIds.length != 1 || _deleting) {
      if (_selectedIds.isEmpty && mounted) {
        showSnackBar(context, '이름을 바꿀 문서를 선택해 주세요.');
      }
      return;
    }

    final docId = _selectedIds.first;
    final controller = TextEditingController();

    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('문서 이름 바꾸기'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '변경할 문서 이름을 작성하세요.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx, text.isEmpty ? null : text);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (newTitle == null || newTitle.isEmpty) return;

    setState(() => _deleting = true);
    final api = ApiClient();

    try {
      await api.renameDoc(docId, newTitle);

      if (!mounted) return;
      showSnackBar(context, '문서 이름을 변경했습니다.');

      setState(() {
        _selectionMode = false;
        _renameMode = false;
        _selectedIds.clear();
        _networkDialogShown = false;
        _future = _fetchDocsWithTimeout();
      });
    } on SessionExpiredException catch (e) {
      if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await SessionManager.I.logout();
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
        showSnackBar(context, e.message);
      });
    } catch (e) {
      if (mounted) {
        await handleNetworkError(context, e, exitOnClose: false);
        showSnackBar(context, '문서 이름 변경 실패');
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Widget _buildList(List<DocumentItem> items) {
    return RefreshIndicator(
      onRefresh: _pullToRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        itemBuilder: (_, i) {
          final d = items[i];
          final selected = _selectedIds.contains(d.id);

          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: _selectionMode
                  ? Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleSelect(d.id),
                    )
                  : const Icon(Icons.description_outlined),
              title: Text(
                d.title,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _selectionMode ? null : const Icon(Icons.chevron_right),
              onTap: () {
                if (_selectionMode) {
                  _toggleSelect(d.id);
                } else {
                  Navigator.pushNamed(context, '/doc', arguments: d);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _networkFallbackView() {
    // ✅ 빨간 오류 로그 대신, 깔끔한 안내 + 재시도
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SectionCard(
            title: '서버 연결 실패',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '문서 목록을 불러오지 못했습니다.\n'
                  '서버 연결을 확인하고 다시 시도해 주세요.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '강의 자료 목록',
      actions: [
        if (!_selectionMode) ...[
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () => _logout(context),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (AppConfig.isPortfolioPreview) {
                _showPreviewUnavailable();
                return;
              }
              if (value == 'delete') {
                setState(() {
                  _selectionMode = true;
                  _renameMode = false;
                  _selectedIds.clear();
                });
              } else if (value == 'rename') {
                setState(() {
                  _selectionMode = true;
                  _renameMode = true;
                  _selectedIds.clear();
                });
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'delete', child: Text('문서 삭제')),
              PopupMenuItem(value: 'rename', child: Text('문서 이름 바꾸기')),
            ],
          ),
        ] else ...[
          TextButton(
            onPressed: _deleting
                ? null
                : () {
                    setState(() {
                      _selectionMode = false;
                      _selectedIds.clear();
                    });
                  },
            child: const Text('취소'),
          ),
          if (!_renameMode)
            IconButton(
              icon: _deleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete),
              tooltip: '선택한 문서 삭제',
              onPressed: (_selectedIds.isEmpty || _deleting)
                  ? null
                  : _deleteSelected,
            )
          else
            TextButton(
              onPressed: (_selectedIds.length != 1 || _deleting)
                  ? null
                  : _renameSelected,
              child: _deleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('이름 변경'),
            ),
        ],
      ],
      floating: FloatingActionButton.extended(
        onPressed: _goUpload,
        icon: const Icon(Icons.upload_file),
        label: const Text('강의 자료 올리기'),
      ),
      child: FutureBuilder<List<DocumentItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            _log('[DOCS] state=${snap.connectionState} → loading');
            return const LoadingView(message: '불러오는 중…');
          }

          if (snap.hasError) {
            final err = snap.error;

            // ✅ 1) 네트워크 오류 → 다이얼로그 1회 + 깔끔한 재시도 화면
            if (_isNetworkError(err)) {
              if (!_networkDialogShown) {
                _networkDialogShown = true;
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!mounted) return;
                  await handleNetworkError(context, err!, exitOnClose: false);
                });
              }
              return _networkFallbackView();
            }

            // ✅ 2) 세션 만료
            if (err is SessionExpiredException) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!mounted) return;
                await SessionManager.I.logout();
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/login', (route) => false);
                showSnackBar(context, err.message);
              });
              return const SizedBox.shrink();
            }

            // ✅ 3) 그 외 에러
            return ErrorView('문서 목록을 불러오지 못했습니다.', onRetry: _reload);
          }

          final items = snap.data ?? [];
          _log('[DOCS] fetched count=${items.length}');

          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _pullToRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  EmptyView(
                    title: '등록된 자료가 없습니다.',
                    subtitle: '우측 하단 버튼으로 PDF를 업로드해 보세요.',
                    action: PrimaryButton(
                      onPressed: _goUpload,
                      icon: Icons.upload,
                      label: const Text('지금 업로드'),
                    ),
                  ),
                ],
              ),
            );
          }

          return _buildList(items);
        },
      ),
    );
  }
}

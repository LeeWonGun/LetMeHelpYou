// lib/ui/widgets.dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' show ExtensionSet, BlockSyntax, InlineSyntax;

/// 화면 기본 골격
/// - 앱바 제목/액션/플로팅 버튼 기본 제공
/// - 화면 아무 곳이나 탭하면 키보드 자동 닫힘
class AppScaffold extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget child;
  final Widget? floating;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;

  const AppScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.floating,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        floatingActionButton: floating,
        bottomNavigationBar: bottomNavigationBar,
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 가득 찬 기본 버튼
class PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget label;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = (isLoading) ? null : onPressed;

    final btnChild = Row(
      mainAxisAlignment: expanded ? MainAxisAlignment.center : MainAxisAlignment.start,
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (isLoading) ...[
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon),
          const SizedBox(width: 8),
        ],
        Flexible(child: label),
      ],
    );

    final button = FilledButton(onPressed: effectiveOnPressed, child: btnChild);
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// 내부 스크롤 유틸: bounded(높이 제한 있음)면 Expanded,
/// unbounded(리스트 등)면 maxHeight로 안전히 고정 후 스크롤
class _ScrollableArea extends StatelessWidget {
  final Widget child;
  final double maxHeight;
  final EdgeInsets padding;

  const _ScrollableArea({
    required this.child,
    required this.maxHeight,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;

        final scrollChild = Scrollbar(
          child: SingleChildScrollView(
            child: Padding(padding: padding, child: child),
          ),
        );

        if (bounded) {
          // Column 등 내부에서 남은 영역을 채우며 내부 스크롤
          return Expanded(child: scrollChild);
        } else {
          // ListView 등 높이 무제한 컨텍스트에서는 안전한 최대높이로 내부 스크롤
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: scrollChild,
          );
        }
      },
    );
  }
}

/// 섹션 카드(제목 + 본문)
/// - 긴 내용은 카드 내부에서만 스크롤(방법 2)
/// - child가 Markdown/MarkdownBody면 자동 내부 스크롤 적용
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;

  /// 내용이 길 때 카드 내부에서만 스크롤되도록 할지 여부
  final bool scrollable;

  /// child가 Markdown/MarkdownBody일 때 자동으로 내부 스크롤 적용
  final bool autoScrollForMarkdown;

  /// [scrollable] 또는 자동 스크롤 시, 스크롤 영역의 최대 높이
  final double maxScrollHeight;

  /// 카드 안 패딩(기본 16)
  final EdgeInsets padding;

  /// (선택) 섹션 상단 우측 액션(예: 더보기 버튼)
  final List<Widget>? headerActions;

  const SectionCard({
    super.key,
    this.title,
    required this.child,
    this.scrollable = false,
    this.autoScrollForMarkdown = true,
    this.maxScrollHeight = 260,
    this.padding = const EdgeInsets.all(16),
    this.headerActions,
  });

  bool _isMarkdownLike(Widget w) => w is Markdown || w is MarkdownBody;

  @override
  Widget build(BuildContext context) {
    final hasHeader =
        (title != null && title!.isNotEmpty) || (headerActions != null);

    final header = hasHeader
        ? Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (title != null && title!.isNotEmpty)
            Expanded(
              child: Text(
                title!,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          if (headerActions != null) ...headerActions!,
        ],
      ),
    )
        : const SizedBox.shrink();

    final wantsInternalScroll =
        scrollable || (autoScrollForMarkdown && _isMarkdownLike(child));

    return Card(
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 높이가 정해져 있는지(=Expanded 안에 있는지) 여부
            final hasBoundedHeight = constraints.hasBoundedHeight;

            // ───────── 스크롤 필요 없음 ─────────
            if (!wantsInternalScroll) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasHeader) header,
                  child,
                ],
              );
            }

            // ───────── 스크롤 + 부모가 높이를 정해준 경우
            // 예: Q&A 탭에서 Expanded(FutureBuilder -> SectionCard)
            if (hasBoundedHeight) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasHeader) header,
                  Expanded(
                    child: SingleChildScrollView(
                      child: child,
                    ),
                  ),
                ],
              );
            }

            // ───────── 스크롤 + 부모 높이가 무한(리스트 안 카드 등)
            // 예: 요약 탭에서 ListView(children: [SectionCard(...)])
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasHeader) header,
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: maxScrollHeight,
                  ),
                  child: SingleChildScrollView(
                    child: child,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Markdown을 안전하게 Expanded로 감싸는 헬퍼(방법 2 적용)
/// - Flex(Column/Row) 조상/부모 제약 여부에 관계없이 내부 스크롤 유지
class MarkdownExpanded extends StatelessWidget {
  final String data;

  /// Flex가 아닌 부모(리스트 등)일 때 사용할 최대 높이(내부 스크롤)
  final double fallbackMaxHeight;

  /// Markdown 옵션
  final MarkdownStyleSheet? styleSheet;
  final MarkdownTapLinkCallback? onTapLink;
  final EdgeInsets padding;

  /// 텍스트 선택 가능 여부 — flutter_markdown ^0.7.7+에서 `selectable: true`
  final bool selectable;

  // 문법 옵션
  final ExtensionSet? extensionSet;
  final List<BlockSyntax>? blockSyntaxes;
  final List<InlineSyntax>? inlineSyntaxes;

  const MarkdownExpanded({
    super.key,
    required this.data,
    this.fallbackMaxHeight = 300,
    this.styleSheet,
    this.onTapLink,
    this.padding = EdgeInsets.zero,
    this.selectable = false,
    this.extensionSet,
    this.blockSyntaxes,
    this.inlineSyntaxes,
  });

  Widget _buildMarkdown(BuildContext context) {
    final sheet = styleSheet ?? MarkdownStyleSheet.fromTheme(Theme.of(context));
    return Markdown(
      data: data,
      styleSheet: sheet,
      onTapLink: onTapLink,
      extensionSet: extensionSet,
      blockSyntaxes: blockSyntaxes,
      inlineSyntaxes: inlineSyntaxes,
      selectable: selectable,
      padding: padding,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final scrollChild = Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(child: _buildMarkdown(context)),
        );
        if (bounded) {
          return Expanded(child: scrollChild);
        } else {
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: fallbackMaxHeight),
            child: scrollChild,
          );
        }
      },
    );
  }
}

/// 로딩 뷰
class LoadingView extends StatelessWidget {
  final String? message;
  final bool inline;

  const LoadingView({super.key, this.message, this.inline = false});

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(message!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );

    return inline ? body : Center(child: body);
  }
}

/// 오류 뷰(재시도 버튼 포함) — 긴 메시지도 안전하게 표시되도록 스크롤 카드 사용
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView(this.message, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      title: '오류',
      scrollable: true,
      maxScrollHeight: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(message, style: TextStyle(color: cs.error)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            PrimaryButton(
              onPressed: onRetry,
              label: const Text('다시 시도'),
              icon: Icons.refresh,
            ),
          ],
        ],
      ),
    );
  }
}

/// 빈 상태 뷰
class EmptyView extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final bool centered;

  const EmptyView({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: centered ? TextAlign.center : TextAlign.start,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: centered ? TextAlign.center : TextAlign.start,
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 12),
          if (centered) Center(child: action!) else action!,
        ],
      ],
    );

    return SectionCard(
      child: centered ? Center(child: column) : column,
    );
  }
}

/// 페이지 상단에 표시하는 오류 배너(테마 색 사용 + 선택적 재시도)
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  const ErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: cs.onErrorContainer),
            ),
          ),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
              style: TextButton.styleFrom(
                foregroundColor: cs.onErrorContainer,
              ),
            ),
        ],
      ),
    );
  }
}

/// 공용 스낵바 헬퍼
void showSnackBar(
    BuildContext context,
    String message, {
      String? actionLabel,
      VoidCallback? onAction,
      Duration duration = const Duration(seconds: 3),
    }) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    ),
  );
}

/// 공통 네트워크 에러 처리 헬퍼
/// - SocketException / TimeoutException 계열을 잡아서
///   안내 다이얼로그를 보여주고, 필요하면 앱 종료까지 수행
Future<bool> handleNetworkError(
    BuildContext context,
    Object? error, {
      bool exitOnClose = false,
    }) async {
  final isNetworkError =
      error is SocketException ||
          error is TimeoutException ||
          error.toString().contains('SocketException');

  if (!isNetworkError) {
    // 내가 처리할 타입이 아니면 false 리턴 → 호출한 쪽에서 다른 처리
    return false;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('네트워크 오류'),
      content: const Text('인터넷 연결이 불안정합니다.\n인터넷 연결을 확인해 주세요.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(exitOnClose ? '앱 종료' : '확인'),
        ),
      ],
    ),
  );

  if (exitOnClose) {
    // 앱 종료
    SystemNavigator.pop();
  }

  return true; // 네트워크 에러를 여기서 처리했다는 의미
}

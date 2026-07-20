// models.dart

/// 문서 리스트 아이템
class DocumentItem {
  final int id;
  final String title;
  final String? fileUrl; // ✅ 추가

  DocumentItem({
    required this.id,
    required this.title,
    this.fileUrl,
  });

  factory DocumentItem.fromJson(Map<String, dynamic> j) => DocumentItem(
    id: (j['id'] as num).toInt(),                    // 기존처럼 안전 캐스팅
    title: (j['title'] ?? '제목 없음').toString(),
    fileUrl: j['file_url']?.toString(),              // ✅ 서버에서 내려오는 file_url
  );
}

/// SSOT용 토큰 모델 (서버 응답 키: 'access', 'refresh')
class AuthTokens {
  final String access;
  final String refresh;
  AuthTokens({required this.access, required this.refresh});

  factory AuthTokens.fromJson(Map<String, dynamic> j) => AuthTokens(
    access: (j['access'] ?? '').toString(),
    refresh: (j['refresh'] ?? '').toString(),
  );
}

/// 학습노트 응답: 마크다운 + 소스 스니펫 + 중요 이미지
class StudyNotes {
  final String markdown;
  final List<SourceHit> sources;
  final List<PageImage> images;

  StudyNotes({
    required this.markdown,
    required this.sources,
    required this.images,
  });

  factory StudyNotes.fromJson(Map<String, dynamic> j) => StudyNotes(
    markdown: (j['markdown'] ?? '').toString(),
    sources: (j['sources'] as List? ?? [])
        .map((e) => SourceHit.fromJson(e as Map<String, dynamic>))
        .toList(),
    images: (j['images'] as List? ?? [])
        .map((e) => PageImage.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 근거 스니펫(요약/노트 하단 “참고 근거” 영역)
class SourceHit {
  /// 서버 summarize_notes에서는 doc_id 없이 내려오고,
  /// ask_gpt에서는 doc_id/index/snippet 형태가 내려올 수 있어 둘 다 수용
  final int? docId;   // optional
  final int? index;   // chunk index
  final String snippet;
  final int? page;    // 있을 수도, 없을 수도

  SourceHit({
    this.docId,
    this.index,
    required this.snippet,
    this.page,
  });

  factory SourceHit.fromJson(Map<String, dynamic> j) => SourceHit(
    docId: (j['doc_id'] as num?)?.toInt(),
    index: (j['index'] as num?)?.toInt(),
    snippet: (j['snippet'] ?? '').toString(),
    page: (j['page'] as num?)?.toInt(),
  );
}

/// 중요 페이지 이미지(스냅샷)
class PageImage {
  final int page;       // 1-based 또는 0-based여도 그대로 표시용
  final String url;     // MEDIA_URL 절대경로
  final int width;      // 픽셀
  final int height;     // 픽셀
  final double score;   // 중요도 점수(정렬용)

  PageImage({
    required this.page,
    required this.url,
    required this.width,
    required this.height,
    required this.score,
  });

  factory PageImage.fromJson(Map<String, dynamic> j) => PageImage(
    page: (j['page'] as num?)?.toInt() ?? 0,
    url: (j['url'] ?? '').toString(),
    width: (j['width'] as num?)?.toInt() ?? 0,
    height: (j['height'] as num?)?.toInt() ?? 0,
    score: (j['score'] is num) ? (j['score'] as num).toDouble() : 0.0,
  );
}

# lmhu/models.py
from django.db import models


class QuestionAnswer(models.Model):
    question = models.TextField()
    answer = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Q: {self.question[:30]}..."


class Document(models.Model):
    title = models.CharField(max_length=255)
    file = models.FileField(upload_to="docs/")
    created_at = models.DateTimeField(auto_now_add=True)

    # ✅ (선택) "전체 페이지 이미지" 생성 상태 플래그
    # - 기존 기능에는 영향 없음
    # - 페이지 뷰어 UX에서 "생성 중 / 완료" 표시 또는 중복 생성 방지에 유용
    pages_ready = models.BooleanField(default=False)
    pages_generating = models.BooleanField(default=False)

    def __str__(self) -> str:
        return f"{self.id}: {self.title}"


class DocumentChunk(models.Model):
    # 🔒 필드명 유지: doc / idx
    doc = models.ForeignKey(
        Document,
        on_delete=models.CASCADE,
        related_name="chunks",
    )
    idx = models.IntegerField()   # 청크 순서(0-based 권장)
    text = models.TextField()

    class Meta:
        # 동일 문서 내에서 idx는 유니크
        unique_together = ("doc", "idx")
        # 기본 정렬: idx 오름차순
        ordering = ["idx"]
        # 조회 성능 향상용 복합 인덱스
        indexes = [models.Index(fields=["doc", "idx"])]

    def __str__(self) -> str:
        return f"Chunk(doc={self.doc_id}, idx={self.idx})"


# ✅ 전략 1: 페이지 스냅샷(중요 페이지 PNG) 저장용 모델 (기존 유지)
class DocumentImage(models.Model):
    doc = models.ForeignKey(
        Document,
        on_delete=models.CASCADE,
        related_name="images",
    )
    page = models.IntegerField()                 # 1-based 페이지 번호
    path = models.CharField(max_length=500)      # MEDIA_ROOT 기준 상대 경로 (예: "docs/12/images/p-0003.png")
    width = models.IntegerField()
    height = models.IntegerField()
    score = models.FloatField(default=0)         # 중요도 점수(이미지 개수/키워드 등 규칙 기반)
    caption = models.TextField(blank=True)       # (옵션) 나중에 캡션 추출 시 사용

    class Meta:
        indexes = [models.Index(fields=["doc", "page"])]
        ordering = ["-score", "page"]

    def __str__(self) -> str:
        return f"DocImage(doc={self.doc_id}, page={self.page}, score={self.score:.2f})"


# ✅ 추가: "전체 페이지" PDF → 이미지(페이지) 저장용 모델
# - 기존 DocumentImage(중요 페이지 스냅샷)와 목적이 달라서 분리하는 게 안전
class DocumentPageImage(models.Model):
    doc = models.ForeignKey(
        Document,
        on_delete=models.CASCADE,
        related_name="page_images",  # ✅ 중요: 기존 "images"와 이름 겹치지 않게
    )

    # 1-based page number
    page = models.PositiveIntegerField()

    # 실제 이미지 파일 (MEDIA_ROOT 아래 저장)
    # 예: MEDIA_ROOT/doc_pages/doc12/p0001.png
    image = models.ImageField(upload_to="doc_pages/")

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("doc", "page")
        ordering = ["page"]
        indexes = [models.Index(fields=["doc", "page"])]

    def __str__(self) -> str:
        return f"DocPageImage(doc={self.doc_id}, page={self.page})"
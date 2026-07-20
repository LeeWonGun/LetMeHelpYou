# lmhu/utils_pages.py
import fitz  # PyMuPDF
from django.core.files.base import ContentFile
from django.db import transaction

from .models import Document, DocumentPageImage


def build_page_images_for_document(
    doc: Document,
    *,
    zoom: float = 1.5,
    max_pages: int | None = None,
    force: bool = False,
) -> int:
    """
    PDF -> 전체 페이지 PNG 생성 후 DocumentPageImage에 저장.
    - zoom: 렌더링 해상도(1.0~2.0 권장). 높을수록 선명하지만 느림/메모리↑
    - max_pages: 너무 큰 PDF 방지용(예: 30). None이면 전체
    - force: True면 기존 페이지 이미지 삭제 후 재생성
    반환: 생성된(또는 존재하는) 총 페이지 이미지 개수
    """

    pdf_path = doc.file.path

    # 중복 생성 방지 플래그(UX용)
    # 생성 실패해도 반드시 원복되도록 try/finally 패턴을 API단에서 쓰는 걸 권장
    if force:
        # DB 레코드 삭제 + 파일 삭제는 Django가 ImageField 파일을 자동 삭제하지 않을 수 있어
        # 여기서는 레코드 삭제만 하고, 파일 정리는 추후 필요 시 커스텀으로 정리 가능
        DocumentPageImage.objects.filter(doc=doc).delete()
        doc.pages_ready = False
        doc.save(update_fields=["pages_ready"])

    # 이미 있고 force가 아니라면 그대로 반환(빠른 경로)
    if (not force) and DocumentPageImage.objects.filter(doc=doc).exists():
        return DocumentPageImage.objects.filter(doc=doc).count()

    # PDF 렌더
    pdf = fitz.open(pdf_path)
    total_pages = pdf.page_count

    limit = total_pages
    if max_pages is not None:
        limit = min(limit, int(max_pages))

    mat = fitz.Matrix(zoom, zoom)
    created = 0

    # 한번에 너무 많이 save()하면 느릴 수 있지만,
    # 페이지별로 저장해야 파일이 생성되므로 루프 저장
    for idx in range(limit):
        page_num = idx + 1  # 1-based
        page = pdf.load_page(idx)
        pix = page.get_pixmap(matrix=mat, alpha=False)

        png_bytes = pix.tobytes("png")
        filename = f"doc{doc.id}_p{page_num:04d}.png"

        # upsert
        obj, _ = DocumentPageImage.objects.get_or_create(doc=doc, page=page_num)
        # ImageField 저장
        obj.image.save(filename, ContentFile(png_bytes), save=True)
        created += 1

    pdf.close()

    doc.pages_ready = True
    doc.save(update_fields=["pages_ready"])

    return created
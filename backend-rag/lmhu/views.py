# lmhu/views.py
import logging
import os, json, re, requests

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile  # ✅ 추가 (ImageField에 bytes 저장)

from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.parsers import JSONParser, MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework import status

from rest_framework_simplejwt.tokens import RefreshToken


logger = logging.getLogger(__name__)

# ✅ DocumentPageImage 추가 import
from .models import (
    Document,
    DocumentChunk,
    DocumentImage,
    DocumentPageImage,   # ✅ 추가
)

# ────────────────────────────────────────────────────────────────────────────
# RAG / 스냅샷 유틸 (utils.py)
try:
    from .utils import (
        build_faiss_index_for_document,   # PDF→chunks→embedding→FAISS 저장
        search_similar_chunks,            # 질의 유사도 검색
        extract_key_pages_as_pngs,        # 중요 페이지 PNG 렌더링
    )
except Exception:
    build_faiss_index_for_document = None
    search_similar_chunks = None
    extract_key_pages_as_pngs = None

# (선택) 기존 QA 모델/시리얼라이저가 있을 때만 사용
try:
    from .models import QuestionAnswer
    from .serializers import QuestionAnswerSerializer
except Exception:
    QuestionAnswer = None
    QuestionAnswerSerializer = None

# ────────────────────────────────────────────────────────────────────────────
# OpenAI 클라이언트 (환경변수 기반)
try:
    from openai import OpenAI
    _openai_client = OpenAI(api_key=getattr(settings, "OPENAI_API_KEY", "") or os.getenv("OPENAI_API_KEY", ""))
    _OPENAI_MODEL = getattr(settings, "OPENAI_MODEL", os.getenv("OPENAI_MODEL", "gpt-4o-mini"))
except Exception:
    _openai_client = None
    _OPENAI_MODEL = "gpt-4o-mini"


def _openai_chat(messages: list[dict], temperature: float = 0.2, max_tokens: int | None = None) -> str:
    """OpenAI 호출(가능하면) 또는 실패 시 빈 문자열 반환"""
    if not _openai_client or not (getattr(settings, "OPENAI_API_KEY", "") or os.getenv("OPENAI_API_KEY")):
        return ""
    resp = _openai_client.chat.completions.create(
        model=_OPENAI_MODEL,
        messages=messages,
        temperature=temperature,
        **({"max_tokens": max_tokens} if max_tokens else {}),
    )
    return (resp.choices[0].message.content or "").strip()

# ────────────────────────────────────────────────────────────────────────────
# 텍스트 유틸
def _extract_text_from_pdf(pdf_path: str) -> str:
    import fitz  # PyMuPDF
    doc = fitz.open(pdf_path)
    parts = []
    for page in doc:
        parts.append(page.get_text("text"))
    doc.close()
    return "\n".join(parts)

def _chunk_text(text: str, max_len: int = 800) -> list[str]:
    text = re.sub(r"\s+", " ", text).strip()
    chunks, cur = [], []
    for token in text.split(" "):
        cur.append(token)
        if sum(len(t) + 1 for t in cur) > max_len:
            chunks.append(" ".join(cur))
            cur = []
    if cur:
        chunks.append(" ".join(cur))
    return chunks

def _naive_bullets_from_text(text: str, n: int = 5) -> list[str]:
    sents = re.split(r"(?<=[.!?])\s+", text)
    sents = [s.strip() for s in sents if s.strip()]
    return [s[:200] for s in sents[:n]] or ["내용이 충분하지 않습니다."]

# ────────────────────────────────────────────────────────────────────────────
# 학습노트용 도우미
def _join_chunks_for_notes(doc_id: int, max_chars: int = 12000) -> str:
    """앞에서부터 순서대로 이어붙여 상한까지만 사용(간단/안정)."""
    parts, total = [], 0
    for t in DocumentChunk.objects.filter(doc_id=doc_id).order_by("idx").values_list("text", flat=True):
        if not t:
            continue
        t = re.sub(r"\s+", " ", t).strip()
        if not t:
            continue
        if total + len(t) > max_chars:
            remain = max_chars - total
            if remain > 0:
                parts.append(t[:remain])
            break
        parts.append(t)
        total += len(t)
    return "\n".join(parts)

def _notes_system_prompt(depth: str = "normal") -> str:
    base = (
        "너는 대학 전공 수업을 돕는 조교야. 아래 문서를 바탕으로 시험 대비용 학습노트를 만들어."
        " 한국어로 작성하고, Markdown 형식으로 출력해."
        " 섹션/소제목/불릿/표를 적극 활용하고, 핵심 개념 → 정의 → 공식/예제 → 주의점 순으로 정리해."
    )
    if depth == "brief":
        return base + " 분량은 짧게 핵심만 요약해."
    if depth == "deep":
        return base + " 분량을 충분히 쓰고, 각 개념마다 예시, 흔한 오개념, 기출 포인트/암기 팁도 포함해."
    return base

def _build_notes_sources(doc_id: int, k: int = 5):
    """간단한 근거 보기: 앞쪽 k개 청크 스니펫."""
    qs = DocumentChunk.objects.filter(doc_id=doc_id).order_by("idx")[:k]
    out = []
    for c in qs:
        snippet = (c.text or "").strip().replace("\n", " ")
        snippet = re.sub(r"\s+", " ", snippet)[:160]
        out.append({"index": c.idx, "page": None, "snippet": snippet})
    return out

def _image_abs_url(request, rel_path: str) -> str:
    """MEDIA_URL + rel_path 로 절대 URL 생성 (DocumentImage.path용)"""
    if rel_path.startswith("http://") or rel_path.startswith("https://"):
        return rel_path
    media_url = settings.MEDIA_URL.rstrip("/") + "/"
    return request.build_absolute_uri(media_url + rel_path.lstrip("/"))

def _filefield_abs_url(request, filefield) -> str:
    """ImageField/FileField 같은 FileField 타입의 절대 URL 생성"""
    if not filefield:
        return ""
    try:
        return request.build_absolute_uri(filefield.url)
    except Exception:
        return ""

# ────────────────────────────────────────────────────────────────────────────
# 카카오 로그인(JWT 교환) — 공개 엔드포인트
User = get_user_model()

@api_view(["POST"])
@permission_classes([AllowAny])
def kakao_auth(request):
    access_token = (request.data.get("access_token") or "").strip()
    if not access_token:
        return Response({"detail": "access_token required"}, status=status.HTTP_400_BAD_REQUEST)

    # 1) 카카오 사용자 정보 조회
    try:
        r = requests.get(
            "https://kapi.kakao.com/v2/user/me",
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=5,
        )
        if r.status_code != 200:
            logger.warning(
                "Kakao user lookup failed with status %s",
                r.status_code,
            )
            return Response(
                {"detail": "invalid kakao token"},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        data = r.json()
        kakao_id = data.get("id")
        if not kakao_id:
            return Response({"detail": "kakao id missing"}, status=status.HTTP_400_BAD_REQUEST)

        kakao_account = data.get("kakao_account", {}) or {}
        profile = (kakao_account.get("profile") or {})
        nickname = profile.get("nickname") or ""
        email = kakao_account.get("email") or ""
    except Exception as e:
        logger.warning("Kakao authentication failed: %s", type(e).__name__)
        return Response(
            {"detail": "kakao authentication failed"},
            status=status.HTTP_502_BAD_GATEWAY,
        )

    # 2) 유저 찾기/생성
    username = f"kakao_{kakao_id}"
    user, created = User.objects.get_or_create(username=username, defaults={"email": email})
    if created:
        user.first_name = nickname[:30] if nickname else ""
        user.set_unusable_password()
        user.save(update_fields=["first_name"])

    # 3) JWT 발급
    refresh = RefreshToken.for_user(user)
    access = str(refresh.access_token)

    return Response({
        "access": access,
        "refresh": str(refresh),
        "user": {
            "id": user.id,
            "username": user.username,
            "nickname": user.first_name,
            "email": user.email,
        }
    })

# ────────────────────────────────────────────────────────────────────────────
# 문서 목록
@api_view(["GET"])
def docs_list(request):
    """
    GET /api/docs/ →
    [
      {"id": 1, "title": "xxx.pdf", "file_url": "http://.../media/docs/xxx.pdf"},
      ...
    ]
    """
    docs = Document.objects.order_by("-id")
    data = []
    for doc in docs:
        file_url = request.build_absolute_uri(doc.file.url) if doc.file else ""
        data.append({
            "id": doc.id,
            "title": doc.title,
            "file_url": file_url,
            "pages_ready": bool(getattr(doc, "pages_ready", False)),
        })
    return Response(data)

# ✅ 문서 삭제/이름변경 API (기존 그대로)
@api_view(["DELETE", "PATCH"])
def doc_detail(request, doc_id: int):
    """
    DELETE /api/docs/<doc_id>/
    PATCH  /api/docs/<doc_id>/   body: { "title": "새 이름" }
    """
    try:
        doc = Document.objects.get(id=doc_id)
    except Document.DoesNotExist:
        return Response({"detail": "document not found"}, status=status.HTTP_404_NOT_FOUND)

    if request.method == "DELETE":
        file_path = doc.file.path if (doc.file and hasattr(doc.file, "path")) else None

        DocumentChunk.objects.filter(doc=doc).delete()
        DocumentImage.objects.filter(doc=doc).delete()
        DocumentPageImage.objects.filter(doc=doc).delete()  # ✅ 페이지 이미지도 같이 삭제

        doc.delete()

        if file_path:
            try:
                if os.path.exists(file_path):
                    os.remove(file_path)
            except OSError as e:
                logger.warning(
                    "Document file removal failed: %s",
                    type(e).__name__,
                )

        return Response(status=status.HTTP_204_NO_CONTENT)

    if request.method == "PATCH":
        title = (request.data.get("title") or "").strip()
        if not title:
            return Response({"detail": "title required"}, status=status.HTTP_400_BAD_REQUEST)

        doc.title = title
        doc.save(update_fields=["title"])

        return Response({"id": doc.id, "title": doc.title}, status=status.HTTP_200_OK)

# 파일 업로드
@api_view(["POST"])
@parser_classes([MultiPartParser, FormParser])
def upload_file(request):
    """POST /api/files/upload/ (multipart 'file') → {"doc_id":..,"title":..}"""
    f = request.FILES.get("file")
    if not f:
        return Response({"detail": "file required"}, status=status.HTTP_400_BAD_REQUEST)
    doc = Document.objects.create(title=f.name, file=f)
    return Response({"doc_id": doc.id, "title": doc.title})

# 텍스트 인젝스트(FAISS 없이)
@api_view(["POST"])
@parser_classes([JSONParser])
def ingest_file(request):
    """POST /api/files/ingest/ {"doc_id":int} → {"ok":True,"chunks":N}"""
    doc_id = request.data.get("doc_id")
    if not doc_id:
        return Response({"detail": "doc_id required"}, status=status.HTTP_400_BAD_REQUEST)
    try:
        doc = Document.objects.get(id=doc_id)
    except Document.DoesNotExist:
        return Response({"detail": "document not found"}, status=status.HTTP_404_NOT_FOUND)

    pdf_path = doc.file.path
    full_text = _extract_text_from_pdf(pdf_path)
    chunks = _chunk_text(full_text, max_len=800)

    DocumentChunk.objects.filter(doc=doc).delete()
    for i, t in enumerate(chunks):
        DocumentChunk.objects.create(doc=doc, idx=i, text=t)

    return Response({"ok": True, "chunks": len(chunks)})

# 전체 인게스트(임베딩/FAISS까지)
@api_view(["POST"])
@parser_classes([JSONParser])
def ingest_api(request):
    """
    POST /api/ingest/ {"doc_id": int}
    업로드 후 호출 시 문서 인덱싱(FAISS)까지 수행
    """
    if build_faiss_index_for_document is None:
        return Response({"detail": "RAG utils not available"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    doc_id = request.data.get("doc_id")
    if not doc_id:
        return Response({"detail": "doc_id required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        doc = Document.objects.get(id=doc_id)
    except Document.DoesNotExist:
        return Response({"detail": "document not found"}, status=status.HTTP_404_NOT_FOUND)

    n = build_faiss_index_for_document(doc)
    return Response({"ok": True, "chunks": n})

# 중요 페이지 스냅샷 생성(API)
@api_view(["POST"])
@parser_classes([JSONParser])
def generate_snapshots(request):
    if extract_key_pages_as_pngs is None:
        return Response({"detail": "snapshot utility not available"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    doc_id = request.data.get("doc_id")
    top_k = int(request.data.get("top_k") or 5)
    zoom = float(request.data.get("zoom") or 2.0)

    if not doc_id:
        return Response({"detail": "doc_id required"}, status=status.HTTP_400_BAD_REQUEST)
    try:
        doc = Document.objects.get(id=doc_id)
    except Document.DoesNotExist:
        return Response({"detail": "document not found"}, status=status.HTTP_404_NOT_FOUND)

    saved = extract_key_pages_as_pngs(doc, top_k=top_k, zoom=zoom)

    imgs_qs = DocumentImage.objects.filter(doc=doc).order_by("-score", "page")
    images = [{
        "page": im.page,
        "url": _image_abs_url(request, im.path),
        "width": im.width,
        "height": im.height,
        "score": im.score,
    } for im in imgs_qs]

    return Response({"ok": True, "saved": saved, "images": images})

# 요약(bullets)
@api_view(["POST"])
@parser_classes([JSONParser])
def summarize_doc(request):
    doc_id = request.data.get("doc_id")
    if not doc_id:
        return Response({"detail": "doc_id required"}, status=status.HTTP_400_BAD_REQUEST)
    try:
        doc = Document.objects.get(id=doc_id)
    except Document.DoesNotExist:
        return Response({"detail": "document not found"}, status=status.HTTP_404_NOT_FOUND)

    text = " ".join(doc.chunks.values_list("text", flat=True)[:20])
    bullets = []

    content = _openai_chat([
        {"role": "system", "content": "너는 대학 전공 학습을 돕는 조교야. 한국어로 핵심을 간결한 불릿 5개로 정리해줘."},
        {"role": "user", "content": text},
    ], temperature=0.2)
    if content:
        bullets = [ln.strip("•- ").strip() for ln in content.splitlines() if ln.strip()]

    if not bullets:
        bullets = _naive_bullets_from_text(text, n=5)

    return Response({"bullets": bullets})

# 학습노트(마크다운 + 근거 + 이미지)
@api_view(["POST"])
@parser_classes([JSONParser])
def summarize_notes(request):
    doc_id = request.data.get("doc_id")
    depth = (request.data.get("depth") or "normal").lower()
    k = int(request.data.get("k") or 5)

    if not doc_id:
        return Response({"detail": "doc_id required"}, status=status.HTTP_400_BAD_REQUEST)
    try:
        doc = Document.objects.get(id=doc_id)
    except Document.DoesNotExist:
        return Response({"detail": "document not found"}, status=status.HTTP_404_NOT_FOUND)

    context = _join_chunks_for_notes(doc.id, max_chars=12000)
    if not context:
        return Response({"detail": "no content"}, status=status.HTTP_400_BAD_REQUEST)

    sys_prompt = _notes_system_prompt(depth)
    user_prompt = "다음은 문서의 추출 텍스트야. 이를 바탕으로 시험 대비용 학습노트를 만들어줘.\n\n=== 문서 내용 ===\n" + context
    try:
        md = _openai_chat(
            [{"role": "system", "content": sys_prompt}, {"role": "user", "content": user_prompt}],
            temperature=0.2,
            max_tokens=None,
        )
    except Exception as e:
        logger.warning("Study notes generation failed: %s", type(e).__name__)
        return Response(
            {"detail": "study notes generation failed"},
            status=status.HTTP_502_BAD_GATEWAY,
        )

    if not md:
        md = "내용이 충분하지 않아 요약이 생성되지 않았습니다."

    sources = _build_notes_sources(doc.id, k=k)

    imgs_qs = DocumentImage.objects.filter(doc=doc).order_by("-score", "page")
    images = [{
        "page": im.page,
        "url": _image_abs_url(request, im.path),
        "width": im.width,
        "height": im.height,
        "score": im.score,
    } for im in imgs_qs]

    return Response({"markdown": md, "images": images, "sources": sources})

# Q&A (RAG on/off 지원)
@api_view(["POST"])
@parser_classes([JSONParser])
def ask_gpt(request):
    q = (request.data.get("question") or "").strip()
    doc_id = request.data.get("doc_id")
    if not q:
        return Response({"detail": "question required"}, status=status.HTTP_400_BAD_REQUEST)

    context = ""
    if doc_id:
        qs = DocumentChunk.objects.filter(doc_id=doc_id).order_by("idx").values_list("text", flat=True)[:20]
        context = " ".join(qs)

    hits = []
    prompt = f"문맥: {context}\n\n질문: {q}"

    if getattr(settings, "USE_RAG", False) and search_similar_chunks is not None and doc_id:
        try:
            topk = getattr(settings, "TOP_K", 5)
            hits = search_similar_chunks(int(doc_id), q, topk)
            rag_ctx = "\n\n".join(f"- {h['text']}" for h in hits)
            prompt = (
                "다음 '근거'를 바탕으로 질문에 간결하고 정확하게 답하세요. "
                "근거에 없는 내용은 추측하지 마세요.\n\n"
                f"[근거]\n{rag_ctx}\n\n[질문]\n{q}"
            )
        except Exception as e:
            logger.warning("RAG search failed: %s", type(e).__name__)

    content = _openai_chat(
        [{"role": "system", "content": "너는 대학 전공 학습을 돕는 조교야. 한국어로 간결하게 답변해줘."},
         {"role": "user", "content": prompt}],
        temperature=0.2,
    )

    answer = content if content else f"(샘플 응답) 문서:{doc_id} / 질문:'{q}'"
    sources = [{"doc_id": h["doc_id"], "index": h["idx"], "snippet": h["text"]} for h in hits]
    return Response({"answer": answer, "sources": sources})

# ────────────────────────────────────────────────────────────────────────────
# ✅✅✅ 추가 1) PDF → 전체 페이지 이미지 생성 API
@api_view(["POST"])
@parser_classes([JSONParser, FormParser, MultiPartParser])
def generate_page_images(request):
    """
    POST /api/pages/generate/
    body: { "doc_id": int, "zoom": 2.0, "force": false }
    resp: {
      "ok": true,
      "doc_id": 12,
      "pages": 35,
      "images": [ { "page": 1, "url": "..." }, ... ]
    }
    """
    doc_id = request.data.get("doc_id")

    if not doc_id:
        return Response({"detail": "doc_id required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        doc_id = int(doc_id)  # ✅ 타입 안정화
    except ValueError:
        return Response({"detail": "invalid doc_id"}, status=status.HTTP_400_BAD_REQUEST)

    zoom = float(request.data.get("zoom", 2.0))
    force = request.data.get("force", False)

    if not doc_id:
        return Response({"detail": "doc_id required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        doc = Document.objects.get(id=int(doc_id))
    except Document.DoesNotExist:
        return Response({"detail": "document not found"}, status=status.HTTP_404_NOT_FOUND)

    if not doc.file:
        return Response({"detail": "document file missing"}, status=status.HTTP_400_BAD_REQUEST)

    # 이미 준비되어 있고 force가 아니면 바로 반환
    if getattr(doc, "pages_ready", False) and not force:
        qs = DocumentPageImage.objects.filter(doc=doc).order_by("page")
        images = [{"page": p.page, "url": _filefield_abs_url(request, p.image)} for p in qs]
        return Response({"ok": True, "doc_id": doc.id, "pages": len(images), "images": images})

    # 생성 플래그 업데이트
    if hasattr(doc, "pages_generating"):
        doc.pages_generating = True
        doc.pages_ready = False
        doc.save(update_fields=["pages_generating", "pages_ready"])

    # 기존 페이지 이미지 삭제(강제 재생성/중복 방지)
    DocumentPageImage.objects.filter(doc=doc).delete()

    try:
        import fitz  # PyMuPDF

        pdf_path = doc.file.path
        pdf = fitz.open(pdf_path)

        images_out = []
        mat = fitz.Matrix(zoom, zoom)

        for i in range(pdf.page_count):
            page = pdf.load_page(i)
            pix = page.get_pixmap(matrix=mat, alpha=False)
            png_bytes = pix.tobytes("png")

            # ImageField 저장: 하위 폴더 포함한 파일명으로 저장 가능
            filename = f"doc_{doc.id}/p{i+1:04d}.png"

            obj = DocumentPageImage(doc=doc, page=i + 1)
            obj.image.save(filename, ContentFile(png_bytes), save=True)

            images_out.append({"page": obj.page, "url": _filefield_abs_url(request, obj.image)})

        pdf.close()

        # 완료 플래그
        if hasattr(doc, "pages_generating"):
            doc.pages_generating = False
            doc.pages_ready = True
            doc.save(update_fields=["pages_generating", "pages_ready"])

        return Response({"ok": True, "doc_id": doc.id, "pages": len(images_out), "images": images_out})

    except Exception as e:
        logger.warning("Page image generation failed: %s", type(e).__name__)
        if hasattr(doc, "pages_generating"):
            doc.pages_generating = False
            doc.pages_ready = False
            doc.save(update_fields=["pages_generating", "pages_ready"])
        return Response(
            {"detail": "page image generation failed"},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

# ✅✅✅ 추가 2) 전체 페이지 이미지 목록 조회 API
@api_view(["GET"])
def list_page_images(request, doc_id: int):
    """
    GET /api/pages/<doc_id>/
    resp: {
      "doc_id": 12,
      "pages_ready": true,
      "pages_generating": false,
      "pages": 35,
      "images": [ { "page": 1, "url": "..." }, ... ]
    }
    """
    try:
        doc = Document.objects.get(id=int(doc_id))
    except Document.DoesNotExist:
        return Response({"detail": "document not found"}, status=status.HTTP_404_NOT_FOUND)

    qs = DocumentPageImage.objects.filter(doc=doc).order_by("page")
    images = [{"page": p.page, "url": _filefield_abs_url(request, p.image)} for p in qs]

    return Response({
        "doc_id": doc.id,
        "pages_ready": bool(getattr(doc, "pages_ready", False)),
        "pages_generating": bool(getattr(doc, "pages_generating", False)),
        "pages": len(images),
        "images": images,
    })

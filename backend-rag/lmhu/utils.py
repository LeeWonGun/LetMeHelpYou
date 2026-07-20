# lmhu/utils.py
import os
import re
from typing import List, Dict, Tuple

import fitz  # PyMuPDF
import numpy as np
import faiss
from openai import OpenAI
from django.conf import settings

from .models import Document, DocumentChunk, DocumentImage

# =========================================================
# 텍스트 추출 / 청크 / 요약 보조
# =========================================================
def extract_text_from_pdf(pdf_path: str) -> str:
    doc = fitz.open(pdf_path)
    parts = []
    for page in doc:
        parts.append(page.get_text("text"))
    doc.close()
    return "\n".join(parts)


def chunk_text(text: str, max_len: int = 800) -> List[str]:
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


def naive_bullets_from_text(text: str, n: int = 5) -> List[str]:
    sents = re.split(r"(?<=\.|!|\?)\s+", text)
    sents = [s.strip() for s in sents if s.strip()]
    return sents[:n] if sents[:n] else ["내용이 충분하지 않습니다."]


# =========================================================
# RAG: 경로/임베딩/FAISS
# =========================================================
client = OpenAI()  # OPENAI_API_KEY는 .env에서 자동 로드


def _faiss_paths(doc_id: int) -> Tuple[str, str]:
    faiss_dir = settings.FAISS_ROOT
    faiss_dir.mkdir(parents=True, exist_ok=True)
    base = faiss_dir / f"doc_{doc_id}"
    return str(base.with_suffix(".index")), str(base.with_suffix(".meta.npy"))


def embed_batch(texts: List[str]) -> List[List[float]]:
    if not texts:
        return []
    res = client.embeddings.create(
        model=settings.EMBED_MODEL,  # 예: "text-embedding-3-small"
        input=texts,
    )
    return [d.embedding for d in res.data]


def build_faiss_index_for_document(doc: Document) -> int:
    """
    PDF -> text -> chunks -> DB(DocumentChunk) 저장 -> 임베딩 -> FAISS index 저장
    반환값: 생성된 청크 수
    """
    raw = extract_text_from_pdf(doc.file.path)
    chunks = chunk_text(raw, max_len=getattr(settings, "CHUNK_SIZE", 800))

    # 기존 청크 삭제 후 재생성
    DocumentChunk.objects.filter(doc=doc).delete()
    metas = []
    for i, t in enumerate(chunks):
        DocumentChunk.objects.create(doc=doc, idx=i, text=t)
        metas.append(t)  # 간단: 텍스트 자체를 메타로 저장(필요 시 dict로 확장)

    if not chunks:
        # 빈 문서일 수 있음 → 기존 인덱스/메타 제거
        ipath, mpath = _faiss_paths(doc.id)
        if os.path.exists(ipath):
            os.remove(ipath)
        if os.path.exists(mpath):
            os.remove(mpath)
        return 0

    vecs = embed_batch(chunks)
    arr = np.array(vecs, dtype="float32")

    index = faiss.IndexFlatL2(arr.shape[1])
    index.add(arr)

    ipath, mpath = _faiss_paths(doc.id)
    faiss.write_index(index, ipath)
    np.save(mpath, np.array(metas, dtype=object))  # 문자열 배열로 저장
    return len(chunks)


def search_similar_chunks(doc_id: int, query: str, topk: int) -> List[Dict]:
    """
    질의 임베딩 -> FAISS 검색 -> [ {doc_id, idx, rank, score, text}, ... ]
    """
    ipath, mpath = _faiss_paths(doc_id)
    if not (os.path.exists(ipath) and os.path.exists(mpath)):
        return []

    index = faiss.read_index(ipath)
    metas = np.load(mpath, allow_pickle=True).tolist()  # 텍스트 리스트

    qv = np.array(embed_batch([query])[0], dtype="float32")[None, :]
    D, I = index.search(qv, min(topk, len(metas)))
    hits = []
    for rank, idx in enumerate(I[0]):
        if idx < 0 or idx >= len(metas):
            continue
        hits.append({
            "doc_id": doc_id,
            "idx": int(idx),
            "rank": int(rank),
            "score": float(D[0][rank]),
            "text": metas[idx][:400],
        })
    return hits


# =========================================================
# 페이지 스냅샷(“중요 페이지”) PNG 렌더링 & DB 기록
# =========================================================

# 중요도 키워드(간단 가중치용)
_KEYWORDS = re.compile(r"(figure|diagram|chart|table|그림|표|도표|다이어그램)", re.I)


def _ensure_dir(abs_path: str):
    os.makedirs(os.path.dirname(abs_path), exist_ok=True)


def _page_score(page) -> float:
    """
    간단 점수: 이미지 개수(×2) + 키워드 매칭(×3)
    - 이미지가 많거나, 텍스트에 '그림/표/diagram' 등이 보이면 점수 상승
    """
    img_count = len(page.get_images(full=True) or [])
    text = page.get_text("text") or ""
    kw = 1 if _KEYWORDS.search(text) else 0
    return img_count * 2 + kw * 3


def extract_key_pages_as_pngs(
    django_doc: Document,
    top_k: int = 5,
    zoom: float = 2.0
) -> int:
    """
    문서에서 점수가 높은 '중요 페이지'를 골라 PNG로 저장하고 DocumentImage로 기록.
    - 저장 경로: MEDIA_ROOT/docs/<doc_id>/images/p-0001.png
    - page: 1-based 페이지 번호
    반환: 저장/갱신된 이미지 개수
    """
    pdf_path = django_doc.file.path
    doc = fitz.open(pdf_path)

    # 1) 페이지별 점수 계산
    scored = []
    for i in range(len(doc)):
        page = doc.load_page(i)
        s = _page_score(page)
        if s > 0:
            scored.append((s, i))  # (score, page_idx)

    # 2) 상위 K 페이지만 채택 (모두 0점이면 앞에서부터 대체 선택)
    picked: List[int]
    if scored:
        scored.sort(reverse=True)
        picked = [idx for _, idx in scored[:top_k]]
    else:
        picked = list(range(min(top_k, len(doc))))

    # 3) 기존 이미지 레코드 제거(매번 재생성 정책)
    DocumentImage.objects.filter(doc=django_doc).delete()

    # 4) 렌더 & 저장 & DB 기록
    saved = 0
    for i in picked:
        page = doc.load_page(i)
        mat = fitz.Matrix(zoom, zoom)
        pix = page.get_pixmap(matrix=mat, alpha=False)

        rel_dir = f"docs/{django_doc.id}/images/"
        rel_path = f"{rel_dir}p-{i+1:04d}.png"  # 1-based 번호 표기
        abs_path = os.path.join(settings.MEDIA_ROOT, rel_path)
        _ensure_dir(abs_path)
        pix.save(abs_path)

        # 현재 페이지 점수(스코어링이 없던 케이스도 동일 계산)
        score = _page_score(page)

        DocumentImage.objects.create(
            doc=django_doc,
            page=i + 1,
            path=rel_path,
            width=pix.width,
            height=pix.height,
            score=score,
        )
        saved += 1

    doc.close()
    return saved

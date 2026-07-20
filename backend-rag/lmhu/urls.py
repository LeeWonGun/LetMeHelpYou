# lmhu/urls.py
from django.conf import settings
from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView
from . import views

urlpatterns = [
    # 인증
    path("auth/kakao/", views.kakao_auth, name="kakao_auth"),
    path("auth/refresh/", TokenRefreshView.as_view(), name="token_refresh"),

    # 문서/파일
    path("docs/", views.docs_list, name="docs_list"),
    path("docs/<int:doc_id>/", views.doc_detail, name="docs-delete"),  # 문서 삭제/이름변경
    path("files/upload/", views.upload_file, name="upload_file"),
    path("files/ingest/", views.ingest_file, name="ingest_file"),   # (기존) FAISS 없이 청크만
    path("ingest/", views.ingest_api, name="ingest_api"),           # ✅ (신규) RAG 인덱싱(FAISS)

    # 요약 / 학습노트 / Q&A
    path("summarize/", views.summarize_doc, name="summarize_doc"),
    path("summarize/notes/", views.summarize_notes, name="summarize_notes"),
    path("ask-gpt/", views.ask_gpt, name="ask_gpt"),
    
    # 스냅샷(중요 페이지 PNG) 생성/갱신
    path("notes/snapshots/", views.generate_snapshots, name="generate_snapshots"),
    
    path("pages/generate/", views.generate_page_images, name="pages-generate"),
    path("pages/<int:doc_id>/", views.list_page_images, name="pages-list"),
]

if settings.DEBUG and settings.LOCAL_DEMO_LOGIN:
    from .demo_auth import local_demo_auth

    urlpatterns.insert(
        0,
        path("auth/local-demo/", local_demo_auth, name="local_demo_auth"),
    )

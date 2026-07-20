from django.core.management.base import BaseCommand
from lmhu.models import Document
from lmhu.utils import build_faiss_index_for_document

class Command(BaseCommand):
    help = "Build FAISS index for a document (PDF -> chunks -> embeddings -> index)."

    def add_arguments(self, parser):
        parser.add_argument('--doc_id', type=int, required=True)

    def handle(self, *args, **opts):
        doc_id = opts['doc_id']
        doc = Document.objects.get(id=doc_id)
        n = build_faiss_index_for_document(doc)
        if n == 0:
            self.stdout.write(self.style.WARNING(f"[doc {doc_id}] No text extracted."))
        else:
            self.stdout.write(self.style.SUCCESS(f"[doc {doc_id}] Ingested chunks: {n}"))

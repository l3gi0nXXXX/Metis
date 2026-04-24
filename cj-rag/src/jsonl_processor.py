"""
JSONL document processor for Graph RAG system.
Handles DocumentModel schema with parent_ids relationships.
"""
import json
import uuid
from typing import List, Optional, Dict
from pathlib import Path
from pydantic import BaseModel

from .models import Chunk, ChunkMetadata
from .extractor import CangjieCodeElementExtractor


class DocumentModel(BaseModel):
    """Pydantic model for JSONL document schema."""
    id: str
    text: str
    parent_ids: List[str]
    source: str
    short: str
    example_code: Optional[str] = None
    example_coding_problem: Optional[str] = None
    url: str


class JSONLProcessor:
    """Process JSONL files containing DocumentModel data."""

    def __init__(self):
        self.extractor = CangjieCodeElementExtractor()

    def load_jsonl(self, file_path: str) -> List[DocumentModel]:
        """Load and validate JSONL file."""
        print(f"\n📄 LOADING JSONL FILE: {file_path}")
        print("-" * 50)
        documents = []

        with open(file_path, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                try:
                    json_obj = json.loads(line.strip())
                    # Validate with Pydantic model
                    doc = DocumentModel(**json_obj)
                    documents.append(doc)
                except json.JSONDecodeError as e:
                    print(f"⚠️  JSON decode error at line {line_num}: {e}")
                    continue
                except Exception as e:
                    print(f"⚠️  Validation error at line {line_num}: {e}")
                    # Try fallback for missing fields
                    if 'long' not in json_obj and 'text' in json_obj:
                        json_obj.setdefault('example_code', None)
                        json_obj.setdefault('example_coding_problem', None)
                        try:
                            doc = DocumentModel(**json_obj)
                            documents.append(doc)
                        except Exception as e2:
                            print(f"❌ Failed even with fallback at line {line_num}: {e2}")
                            continue

        print(f"\n✅ JSONL LOADING COMPLETE: {len(documents)} valid documents loaded")
        print("-" * 50)
        return documents

    def convert_to_chunks(self, documents: List[DocumentModel]) -> List[Chunk]:
        """Convert DocumentModel objects to Chunk objects."""
        print(f"\n🔄 CONVERTING {len(documents)} DOCUMENTS TO CHUNKS")
        print("-" * 50)
        chunks = []

        for i, doc in enumerate(documents, 1):
            if i % 50 == 0 or i == len(documents):
                print(f"  📊 Progress: {i}/{len(documents)} documents converted")

            # Combine text and example_code as full content
            content_parts = [doc.text]
            if doc.example_coding_problem:
                content_parts.append("\n## Example Problem\n" + doc.example_coding_problem)
            if doc.example_code:
                content_parts.append("\n## Example Code\n```cangjie\n" + doc.example_code + "\n```")

            full_content = "\n".join(content_parts)

            # Extract code elements from both text and example_code
            temp_chunk = Chunk(
                id=doc.id,
                content=full_content,
                file_path=doc.source,
                start_line=0,
                end_line=0,
                chunk_type=self._determine_chunk_type(doc),
                metadata=ChunkMetadata(
                    code_elements=[],  # Will be populated below
                    language="cangjie",
                    section_title=doc.short # Use short as section title
                )
            )

            # Extract code elements
            code_elements = self.extractor.get_code_element_names(temp_chunk)
            temp_chunk.metadata.code_elements = code_elements

            # Log code elements found
            if code_elements and (i <= 5 or i % 20 == 0):  # Show for first 5 and every 20th
                elements_preview = code_elements[:3]
                more_indicator = f" + {len(code_elements) - 3} more" if len(code_elements) > 3 else ""
                print(f"      📝 Doc {doc.id}: {len(code_elements)} elements found: {elements_preview}{more_indicator}")

            chunks.append(temp_chunk)

        # Calculate total code elements extracted
        total_elements = sum(len(chunk.metadata.code_elements) for chunk in chunks)
        chunks_with_elements = sum(1 for chunk in chunks if chunk.metadata.code_elements)

        print(f"\n✅ CHUNK CONVERSION COMPLETE:")
        print(f"    📦 Total chunks created: {len(chunks)}")
        print(f"    🔧 Code elements extracted: {total_elements}")
        print(f"    📝 Chunks with elements: {chunks_with_elements}")
        print("-" * 50)
        return chunks

    def _determine_chunk_type(self, doc: DocumentModel) -> str:
        """Determine chunk type based on content."""
        has_example_code = bool(doc.example_code)

        # Check if main text contains code patterns - updated patterns
        code_patterns = [
            r'func\s+\w+\s*\(',
            r'class\s+\w+(?:\s+extends\s+\w+)?(?:\s*\{|\s*$|\s+)',
            r'struct\s+\w+(?:\s*\{|\s*$|\s+)',
            r'interface\s+\w+(?:\s*\{|\s*$|\s+)',
            r'enum\s+\w+(?:\s*\{|\s*$|\s+)'
        ]

        import re
        has_code_in_text = any(re.search(pattern, doc.text) for pattern in code_patterns)

        if has_example_code and has_code_in_text:
            return "MIXED"
        elif has_example_code or has_code_in_text:
            return "CODE"
        else:
            return "TEXT"


class JSONLGraphBuilder:
    """Build graph relationships using parent_ids from JSONL documents."""

    def __init__(self):
        pass

    def build_parent_relationships(self, chunks: List[Chunk], documents: List[DocumentModel]) -> Dict[str, List[str]]:
        """Build parent-child relationships from JSONL parent_ids."""
        print(f"\n🔗 BUILDING PARENT-CHILD RELATIONSHIPS")
        print("-" * 50)

        # Create mapping from doc_id to chunk_id
        doc_to_chunk = {doc.id: chunk.id for doc, chunk in zip(documents, chunks)}

        # Build parent-child relationships
        parent_relationships = {}
        total_relationships = 0

        for doc in documents:
            if doc.parent_ids:
                chunk_id = doc_to_chunk.get(doc.id)
                if chunk_id:
                    parent_chunks = []
                    for parent_id in doc.parent_ids:
                        parent_chunk_id = doc_to_chunk.get(parent_id)
                        if parent_chunk_id:
                            parent_chunks.append(parent_chunk_id)
                            total_relationships += 1

                    if parent_chunks:
                        parent_relationships[chunk_id] = parent_chunks

        print(f"\n✅ RELATIONSHIP MAPPING COMPLETE:")
        print(f"    🔗 Total relationships: {total_relationships}")
        print(f"    👥 Chunks with parents: {len(parent_relationships)}")
        print("-" * 50)
        return parent_relationships



class HybridProcessor:
    """Process both markdown files and JSONL files together."""

    def __init__(self):
        from .chunker import DirectoryProcessor, MarkdownChunker
        self.markdown_processor = DirectoryProcessor()
        self.jsonl_processor = JSONLProcessor()
        self.jsonl_graph_builder = JSONLGraphBuilder()

    def process_hybrid_sources(self,
                             markdown_dir: Optional[str] = None,
                             jsonl_file: Optional[str] = None) -> tuple[List[Chunk], Optional[Dict[str, List[str]]]]:
        """Process both markdown and JSONL sources."""
        print(f"\n🚀 PROCESSING HYBRID DATA SOURCES")
        print("=" * 60)
        all_chunks = []
        parent_relationships = None

        # Process markdown files if provided
        if markdown_dir and Path(markdown_dir).exists():
            print(f"\n📚 PROCESSING MARKDOWN DIRECTORY: {markdown_dir}")
            print("-" * 50)
            md_chunks = self.markdown_processor.process_directory(markdown_dir)
            all_chunks.extend(md_chunks)
            print(f"\n  ✅ MARKDOWN COMPLETE: {len(md_chunks)} chunks added")

        # Process JSONL file if provided
        if jsonl_file and Path(jsonl_file).exists():
            documents = self.jsonl_processor.load_jsonl(jsonl_file)
            jsonl_chunks = self.jsonl_processor.convert_to_chunks(documents)
            all_chunks.extend(jsonl_chunks)

            # Build parent relationships
            parent_relationships = self.jsonl_graph_builder.build_parent_relationships(
                jsonl_chunks, documents
            )
            print(f"\n  ✅ JSONL COMPLETE: {len(jsonl_chunks)} chunks added")

        print(f"\n🎯 HYBRID PROCESSING COMPLETE")
        print(f"    📦 Total chunks from all sources: {len(all_chunks)}")
        print("=" * 60)
        return all_chunks, parent_relationships
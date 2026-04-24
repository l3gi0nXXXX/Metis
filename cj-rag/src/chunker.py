"""
Document chunking module for splitting markdown files into processable chunks.
"""
import re
import uuid
from typing import List, Tuple, Optional
from pathlib import Path
from .models import Chunk, ChunkMetadata
from .extractor import CangjieCodeElementExtractor


class MarkdownChunker:
    """Chunker for markdown documents."""
    
    def __init__(self, 
                 max_chunk_size: int = 1000,
                 min_chunk_size: int = 100,
                 overlap_size: int = 50):
        self.max_chunk_size = max_chunk_size
        self.min_chunk_size = min_chunk_size
        self.overlap_size = overlap_size
        self.extractor = CangjieCodeElementExtractor()
        
        # Regex patterns for markdown structure
        self.header_pattern = re.compile(r'^(#{1,6})\s+(.+)$', re.MULTILINE)
        self.code_block_pattern = re.compile(r'```(\w+)?\n(.*?)```', re.DOTALL)
    
    def chunk_file(self, file_path: str) -> List[Chunk]:
        """Chunk a single markdown file."""
        print(f"  📄 Processing file: {file_path}")
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except UnicodeDecodeError:
            print(f"  ⚠️  Encoding issue with {file_path}, using fallback encoding")
            # Try with different encoding
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
        
        chunks = self.chunk_content(content, file_path)
        print(f"    ✅ Generated {len(chunks)} chunks from {file_path}")
        return chunks
    
    def chunk_content(self, content: str, file_path: str) -> List[Chunk]:
        """Chunk markdown content into processable pieces."""
        chunks = []
        
        # First, try to split by headers
        header_chunks = self._split_by_headers(content, file_path)
        
        # Then, split large chunks by size if needed
        for chunk in header_chunks:
            if len(chunk.content) > self.max_chunk_size:
                size_chunks = self._split_by_size(chunk)
                chunks.extend(size_chunks)
            else:
                chunks.append(chunk)
        
        # Filter out very small chunks
        chunks = [c for c in chunks if len(c.content.strip()) >= self.min_chunk_size]
        
        # Add code element metadata to chunks
        print(f"    🔍 Extracting code elements from {len(chunks)} chunks...")
        for i, chunk in enumerate(chunks):
            chunk.metadata.code_elements = self.extractor.get_code_element_names(chunk)
            if chunk.metadata.code_elements:
                print(f"      📝 Chunk {i+1}: Found {len(chunk.metadata.code_elements)} code elements: {chunk.metadata.code_elements[:3]}{'...' if len(chunk.metadata.code_elements) > 3 else ''}")
        
        return chunks
    
    def _split_by_headers(self, content: str, file_path: str) -> List[Chunk]:
        """Split content by markdown headers."""
        chunks = []
        lines = content.split('\n')
        
        current_section = []
        current_header = None
        start_line = 1
        
        for i, line in enumerate(lines):
            header_match = self.header_pattern.match(line)
            
            if header_match and current_section:
                # Save previous section
                section_content = '\n'.join(current_section)
                if section_content.strip():
                    chunk = self._create_chunk(
                        content=section_content,
                        file_path=file_path,
                        start_line=start_line,
                        end_line=i,
                        section_title=current_header
                    )
                    chunks.append(chunk)
                
                # Start new section
                current_section = [line]
                current_header = header_match.group(2).strip()
                start_line = i + 1
            else:
                current_section.append(line)
        
        # Add the last section
        if current_section:
            section_content = '\n'.join(current_section)
            if section_content.strip():
                chunk = self._create_chunk(
                    content=section_content,
                    file_path=file_path,
                    start_line=start_line,
                    end_line=len(lines),
                    section_title=current_header
                )
                chunks.append(chunk)
        
        # If no headers found, treat entire content as one chunk
        if not chunks:
            chunk = self._create_chunk(
                content=content,
                file_path=file_path,
                start_line=1,
                end_line=len(lines),
                section_title=None
            )
            chunks.append(chunk)
        
        return chunks
    
    def _split_by_size(self, chunk: Chunk) -> List[Chunk]:
        """Split a large chunk into smaller chunks by size."""
        chunks = []
        content = chunk.content
        words = content.split()
        
        if len(words) <= self.max_chunk_size // 10:  # Rough word count estimate
            return [chunk]
        
        current_chunk = []
        current_size = 0
        start_word = 0
        
        for i, word in enumerate(words):
            current_chunk.append(word)
            current_size += len(word) + 1  # +1 for space
            
            if current_size >= self.max_chunk_size:
                # Create chunk with overlap
                chunk_content = ' '.join(current_chunk)
                new_chunk = self._create_chunk(
                    content=chunk_content,
                    file_path=chunk.file_path,
                    start_line=chunk.start_line,
                    end_line=chunk.end_line,
                    section_title=chunk.metadata.section_title
                )
                chunks.append(new_chunk)
                
                # Start next chunk with overlap
                overlap_words = max(0, min(self.overlap_size // 10, len(current_chunk) // 4))
                current_chunk = current_chunk[-overlap_words:]
                current_size = sum(len(w) + 1 for w in current_chunk)
                start_word = i - overlap_words
        
        # Add remaining content
        if current_chunk:
            chunk_content = ' '.join(current_chunk)
            if len(chunk_content.strip()) >= self.min_chunk_size:
                new_chunk = self._create_chunk(
                    content=chunk_content,
                    file_path=chunk.file_path,
                    start_line=chunk.start_line,
                    end_line=chunk.end_line,
                    section_title=chunk.metadata.section_title
                )
                chunks.append(new_chunk)
        
        return chunks if chunks else [chunk]
    
    def _create_chunk(self, 
                     content: str, 
                     file_path: str, 
                     start_line: int, 
                     end_line: int, 
                     section_title: Optional[str]) -> Chunk:
        """Create a chunk with appropriate metadata."""
        chunk_id = str(uuid.uuid4())
        chunk_type = self._determine_chunk_type(content)
        
        metadata = ChunkMetadata(
            code_elements=[],  # Will be populated later
            language="cangjie",
            section_title=section_title
        )
        
        return Chunk(
            id=chunk_id,
            content=content.strip(),
            file_path=file_path,
            start_line=start_line,
            end_line=end_line,
            chunk_type=chunk_type,
            metadata=metadata
        )
    
    def _determine_chunk_type(self, content: str) -> str:
        """Determine if a chunk is TEXT, CODE, or MIXED."""
        code_blocks = self.code_block_pattern.findall(content)
        
        if not code_blocks:
            # Check if there are code-like patterns in the text
            code_patterns = [
                r'func\s+\w+\s*\(',
                r'class\s+\w+',
                r'struct\s+\w+',
                r'interface\s+\w+',
                r'enum\s+\w+'
            ]
            
            has_code_patterns = any(re.search(pattern, content) for pattern in code_patterns)
            return "MIXED" if has_code_patterns else "TEXT"
        
        # Calculate ratio of code to text
        code_length = sum(len(block[1]) for block in code_blocks)
        total_length = len(content)
        code_ratio = code_length / total_length if total_length > 0 else 0
        
        if code_ratio > 0.7:
            return "CODE"
        elif code_ratio > 0.3:
            return "MIXED"
        else:
            return "TEXT"


class DirectoryProcessor:
    """Process multiple markdown files in a directory."""
    
    def __init__(self, chunker: Optional[MarkdownChunker] = None):
        self.chunker = chunker or MarkdownChunker()
    
    def process_directory(self, directory_path: str, 
                         pattern: str = "*.md") -> List[Chunk]:
        """Process all markdown files in a directory."""
        directory = Path(directory_path)
        chunks = []
        
        # Find all markdown files first
        files = list(directory.rglob(pattern))
        print(f"📁 Found {len(files)} markdown files in {directory_path}")
        
        for i, file_path in enumerate(files, 1):
            if file_path.is_file():
                print(f"📄 [{i}/{len(files)}] Processing: {file_path.name}")
                try:
                    file_chunks = self.chunker.chunk_file(str(file_path))
                    chunks.extend(file_chunks)
                except Exception as e:
                    print(f"❌ Error processing {file_path}: {e}")
                    continue
        
        print(f"✅ Completed processing {len(files)} files, generated {len(chunks)} total chunks")
        return chunks
    
    def process_files(self, file_paths: List[str]) -> List[Chunk]:
        """Process a list of markdown files."""
        chunks = []
        
        for file_path in file_paths:
            try:
                file_chunks = self.chunker.chunk_file(file_path)
                chunks.extend(file_chunks)
            except Exception as e:
                print(f"Error processing {file_path}: {e}")
                continue
        
        return chunks
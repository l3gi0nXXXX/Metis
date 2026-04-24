"""
Milvus vector storage for semantic search functionality.
"""
import json
from typing import List, Optional, Dict, Any, Callable, Union
import numpy as np

from .models import Chunk, ChunkResult, ChunkMetadata


class MilvusVectorStore:
    """Vector storage using Milvus for semantic search."""

    def __init__(self,
                 db_path: str = "milvus_cangjie_docs.db",
                 collection_name: str = "cangjie_docs",
                 embedding_model_path: str = "./model/Conan-embedding-v1"):
        """Initialize Milvus connection and embedding model."""
        self.db_path = db_path
        self.collection_name = collection_name
        self.embedding_model_path = embedding_model_path

        # Initialize embedding model with fallback mechanism (like original code)
        self.embedding_model = None
        self.use_langchain = True
        self._setup_embedding_model()

        # Milvus client will be initialized when needed
        self.client = None
        self._setup_client()

    def _setup_embedding_model(self) -> None:
        """Initialize embedding model with langchain-huggingface fallback to transformers."""
        try:
            from langchain_huggingface import HuggingFaceEmbeddings
            # print("Using HuggingFaceEmbeddings from langchain-huggingface")
            self.embedding_model = HuggingFaceEmbeddings(
                model_name=self.embedding_model_path,
                model_kwargs={'device': 'cpu'},
                encode_kwargs={'normalize_embeddings': True}
            )
            self.use_langchain = True
        except ImportError:
            self.use_langchain = False
            try:
                from transformers import AutoModel, AutoTokenizer
                # print("Using transformers directly")
                tokenizer = AutoTokenizer.from_pretrained(self.embedding_model_path)
                model = AutoModel.from_pretrained(self.embedding_model_path)

                def embed_text(text: str) -> List[float]:
                    inputs = tokenizer(text, return_tensors="pt", truncation=True, max_length=512)
                    outputs = model(**inputs)
                    return outputs.last_hidden_state.mean(dim=1).squeeze().detach().numpy().tolist()

                self.embedding_model = embed_text

            except ImportError:
                # print("Warning: Neither langchain-huggingface nor transformers available.")
                # print("Falling back to sentence-transformers")
                try:
                    from sentence_transformers import SentenceTransformer
                    self.embedding_model = SentenceTransformer("all-MiniLM-L6-v2")
                    self.use_langchain = True  # sentence-transformers uses .encode() method
                except ImportError:
                    raise ImportError("No embedding library available. Install langchain-huggingface, transformers, or sentence-transformers.")

    def _encode_text(self, text: str) -> List[float]:
        """Encode text using the appropriate embedding model."""
        if self.use_langchain:
            if hasattr(self.embedding_model, 'embed_query'):
                return self.embedding_model.embed_query(text)
            else:  # sentence-transformers
                return self.embedding_model.encode([text])[0].tolist()
        else:
            return self.embedding_model(text)

    def _setup_client(self) -> None:
        """Set up Milvus client using MilvusClient (simpler approach)."""
        try:
            from pymilvus import MilvusClient

            # Initialize client with database file path
            self.client = MilvusClient(uri=self.db_path)
            # print(f"Connected to Milvus database at: {self.db_path}")

        except ImportError:
            print("Warning: pymilvus not installed. Vector storage will use fallback mode.")
            self.client = None
        except Exception as e:
            print(f"Warning: Failed to connect to Milvus: {e}")
            self.client = None

    def _create_collection_if_needed(self) -> None:
        """Create collection if it doesn't exist."""
        if self.client is None:
            return

        if not self.client.has_collection(collection_name=self.collection_name):
            # Get embedding dimension from a test vector
            test_vector = self._encode_text("test")

            self.client.create_collection(
                collection_name=self.collection_name,
                dimension=len(test_vector),
                metric_type="COSINE"
            )
            print(f"Created collection: {self.collection_name}")
        else:
            print(f"Collection {self.collection_name} already exists")

    def store_chunks(self, chunks: List[Chunk]) -> None:
        """Store chunks in the vector database."""
        if not chunks:
            return

        if self.client is None:
            self._store_chunks_fallback(chunks)
            return

        # Create collection if needed
        print(f"🗄️  Setting up Milvus collection: {self.collection_name}")
        self._create_collection_if_needed()

        # Generate embeddings for all chunks
        print(f"🧠 Generating embeddings for {len(chunks)} chunks...")
        embeddings = []
        for i, chunk in enumerate(chunks, 1):
            if i % 10 == 0 or i == len(chunks):
                print(f"  📊 Progress: {i}/{len(chunks)} embeddings generated")

            # Use section_title (short summary) for embedding if available, otherwise use content
            text_for_embedding = (chunk.metadata.section_title
                                 if chunk.metadata.section_title and len(chunk.metadata.section_title) > 30
                                 else chunk.content)

            embedding = self._encode_text(text_for_embedding)
            embeddings.append(embedding)

        # Prepare data for insertion (using simpler MilvusClient format)
        data = []
        for i, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
            data.append({
                "id": i,  # Use numeric ID for MilvusClient
                "vector": embedding,
                "chunk_id": chunk.id,  # Store original chunk ID as metadata
                "content": chunk.content,
                "file_path": chunk.file_path,
                "start_line": chunk.start_line,
                "end_line": chunk.end_line,
                "chunk_type": chunk.chunk_type,
                "code_elements": json.dumps(chunk.metadata.code_elements),
                "section_title": chunk.metadata.section_title or ""
            })

        # Insert data using MilvusClient
        print(f"💾 Inserting {len(data)} records into Milvus...")
        self.client.insert(
            collection_name=self.collection_name,
            data=data
        )

        print(f"✅ Successfully stored {len(chunks)} chunks in Milvus collection: {self.collection_name}")

    def semantic_search(self, query: str, top_k: int = 10) -> List[ChunkResult]:
        """Perform semantic search for similar chunks."""
        if self.client is None:
            return self._semantic_search_fallback(query, top_k)

        # Generate query embedding
        query_embedding = self._encode_text(query)

        # Perform search using MilvusClient
        results = self.client.search(
            collection_name=self.collection_name,
            data=[query_embedding],
            limit=top_k,
            output_fields=["chunk_id", "content", "file_path", "start_line", "end_line",
                          "chunk_type", "code_elements", "section_title"]
        )

        # Convert results to ChunkResult objects
        chunk_results = []
        for result in results[0]:  # results[0] contains the list of matches
            entity = result["entity"]

            # Parse code elements from JSON
            try:
                code_elements = json.loads(entity.get("code_elements", "[]"))
            except json.JSONDecodeError:
                code_elements = []

            metadata = ChunkMetadata(
                code_elements=code_elements,
                language="cangjie",
                section_title=entity.get("section_title") or None
            )

            # Convert distance to similarity score (for COSINE metric, higher is better)
            # For COSINE distance in Milvus, smaller distance = more similar
            similarity_score = 1.0 - result["distance"]

            chunk_result = ChunkResult(
                id=entity.get("chunk_id", str(result["id"])),
                content=entity.get("content", ""),
                score=similarity_score,
                metadata=metadata
            )
            chunk_results.append(chunk_result)

        return chunk_results

    def get_chunk_by_id(self, chunk_id: str) -> Optional[ChunkResult]:
        """Retrieve a specific chunk by ID."""
        if self.client is None:
            return self._get_chunk_by_id_fallback(chunk_id)

        # Note: MilvusClient doesn't support direct query by custom field
        # This is a limitation of the simpler client approach
        # In practice, you might need to maintain a mapping or use the full pymilvus approach
        # For now, we'll return None and rely on fallback
        return self._get_chunk_by_id_fallback(chunk_id)

    def get_all_chunk_ids(self) -> List[str]:
        """Get all chunk IDs in the collection."""
        if self.client is None:
            return list(self.fallback_storage.keys()) if hasattr(self, 'fallback_storage') else []

        # MilvusClient doesn't support querying all records easily
        # Return fallback storage keys if available
        return list(self.fallback_storage.keys()) if hasattr(self, 'fallback_storage') else []

    def delete_collection(self) -> None:
        """Delete the entire collection."""
        if self.client is not None:
            try:
                if self.client.has_collection(collection_name=self.collection_name):
                    self.client.drop_collection(collection_name=self.collection_name)
                    print(f"Deleted collection: {self.collection_name}")
            except Exception as e:
                print(f"Error deleting collection: {e}")

    # Fallback methods for when Milvus is not available
    def _store_chunks_fallback(self, chunks: List[Chunk]) -> None:
        """Fallback storage in memory when Milvus is not available."""
        if not hasattr(self, 'fallback_storage'):
            self.fallback_storage = {}
            self.fallback_embeddings = {}

        # Generate embeddings
        for chunk in chunks:
            embedding = self._encode_text(chunk.content)
            self.fallback_storage[chunk.id] = chunk
            self.fallback_embeddings[chunk.id] = np.array(embedding)

        print(f"Stored {len(chunks)} chunks in fallback storage")

    def _semantic_search_fallback(self, query: str, top_k: int = 10) -> List[ChunkResult]:
        """Fallback semantic search using in-memory storage."""
        if not hasattr(self, 'fallback_storage') or not self.fallback_storage:
            return []

        # Generate query embedding
        query_embedding = np.array(self._encode_text(query))

        # Calculate similarities
        similarities = []
        for chunk_id, chunk_embedding in self.fallback_embeddings.items():
            similarity = np.dot(query_embedding, chunk_embedding) / (
                np.linalg.norm(query_embedding) * np.linalg.norm(chunk_embedding)
            )
            similarities.append((chunk_id, similarity))

        # Sort by similarity and take top_k
        similarities.sort(key=lambda x: x[1], reverse=True)
        top_similarities = similarities[:top_k]

        # Convert to ChunkResult objects
        results = []
        for chunk_id, similarity in top_similarities:
            chunk = self.fallback_storage[chunk_id]
            results.append(ChunkResult(
                id=chunk_id,
                content=chunk.content,
                score=similarity,
                metadata=chunk.metadata
            ))

        return results

    def _get_chunk_by_id_fallback(self, chunk_id: str) -> Optional[ChunkResult]:
        """Fallback method to get chunk by ID."""
        if not hasattr(self, 'fallback_storage') or chunk_id not in self.fallback_storage:
            return None

        chunk = self.fallback_storage[chunk_id]
        return ChunkResult(
            id=chunk_id,
            content=chunk.content,
            score=1.0,
            metadata=chunk.metadata
        )
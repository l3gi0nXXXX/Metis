# Graph RAG for Cangjie Documentation

## Installation

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Start Milvus (if using full vector storage):
```bash
# Using Docker Compose
curl -sfL https://raw.githubusercontent.com/milvus-io/milvus/master/scripts/standalone_embed.sh -o standalone_embed.sh
bash standalone_embed.sh start
```

Or use the fallback in-memory storage (no Milvus required).

## Quick Start

### 1. Build Index from Documentation

**From Markdown files:**
```bash
python main.py build --docs /path/to/cangjie/docs --collection my_docs
```

**From JSONL file:**
```bash
python main.py build --jsonl /path/to/data.jsonl --collection my_docs
```

**From both sources:**
```bash
python main.py build --docs /path/to/docs --jsonl /path/to/data.jsonl --collection my_docs
```

### 2. Query Documentation

```bash
python main.py query "How to define a function with parameters?" --collection my_docs
```

### 3. Interactive Mode

```bash
python main.py interactive --collection my_docs
```

## Programmatic Usage

```python
from src import GraphRAGRetriever, RetrievalConfig

# Build system from directory
retriever = GraphRAGRetriever.from_directory(
    docs_path="./cangjie_docs/",
    vector_config={'collection_name': 'cangjie_docs'}
)

# Configure retrieval
config = RetrievalConfig(
    initial_k=5,           # Initial semantic search results
    max_graph_distance=2,  # Maximum hops in graph traversal
    max_total_chunks=15    # Maximum final results
)

# Query documentation
results = retriever.retrieve(
    "How to define a function with named parameters?",
    config=config
)

for result in results:
    print(f"Score: {result.score:.3f}")
    print(f"Content: {result.content[:200]}...")
    print(f"Code Elements: {result.metadata.code_elements}")
    print("---")
```

## Cangjie Code Elements Supported

The system can extract and link the following Cangjie language elements:

### Function Definitions
```cangjie
func calculateSum(a: Int64, b: Int64): Int64 {
    return a + b
}
```

### Type Definitions
```cangjie
class DataProcessor {
    // class body
}

struct Point {
    x: Float64
    y: Float64
}

interface Drawable {
    func draw(): Unit
}

enum Color {
    Red, Green, Blue
}
```

### Function Calls
```cangjie
// Method calls
processor.validate(data)

// Function calls
calculateSum(10, 20)
```

## JSONL Data Source Support

The system supports JSONL files with the following schema:

### DocumentModel Schema
```python
class DocumentModel(BaseModel):
    id: str                                    # Unique document ID
    text: str                                  # Main document content
    parent_ids: List[str]                      # Parent document IDs for relationships
    source: str                                # Source file/location
    short: str                                 # Summary for embedding and retrieval
    example_code: Optional[str] = None         # Cangjie code examples
    example_coding_problem: Optional[str] = None  # Coding problems/exercises
    url: str                                   # Documentation URL
```

### JSONL File Format
Each line in the JSONL file should be a valid JSON object:

```jsonl
{"id": "doc1", "text": "Functions are basic building blocks...", "parent_ids": [], "source": "functions.md", "short": "Introduction to functions", "example_code": "func add(a: Int64, b: Int64): Int64 { return a + b }", "url": "https://docs.cangjie.com/functions"}
{"id": "doc2", "text": "Named parameters allow...", "parent_ids": ["doc1"], "source": "functions.md", "short": "Named parameters in functions", "example_code": "func greet(name: String, age!: Int64 = 0) { println(\"Hello ${name}\") }", "url": "https://docs.cangjie.com/functions/named"}
```

### Usage Examples:

```bash
# JSONL only
python main.py build --jsonl ./data/cangjiedoc.jsonl

# JSONL + Markdown
python main.py build --jsonl ./data/cangjiedoc.jsonl --docs ./markdown_docs/

# Run JSONL example
python example_jsonl.py
```

## Configuration

### RetrievalConfig Options

- `initial_k` (int): Number of initial semantic search results (default: 5)
- `max_graph_distance` (int): Maximum hops in graph traversal (default: 2)
- `relevance_threshold` (float): Minimum score for graph expansion (default: 0.3)
- `max_total_chunks` (int): Maximum final results (default: 20)
- `rerank_by_graph` (bool): Re-rank using graph centrality (default: True)

### Vector Store Configuration

- `host`: Milvus server host (default: "localhost")
- `port`: Milvus server port (default: 19530)
- `collection_name`: Collection name (default: "cangjie_docs")
- `embedding_model`: Sentence transformer model (default: "all-MiniLM-L6-v2")

## CLI Commands

### Build Index
```bash
python main.py build [options]
  --docs <path>          # Markdown documentation directory
  --jsonl <path>         # JSONL file with DocumentModel schema
  --collection <name>    # Milvus collection name
  --embed-model <path>   # Embedding model path
  --chunk-size <size>    # Maximum chunk size
```

### Query
```bash
python main.py query <query> [options]
  --collection <name>    # Milvus collection name
  --initial-k <k>       # Initial search results
  --max-distance <d>    # Graph traversal distance
  --max-results <n>     # Maximum final results
  --output <file>       # Output JSON file
```

### Interactive Mode
```bash
python main.py interactive [options]
  --collection <name>   # Milvus collection name

# Interactive commands:
# /config initial_k 10     # Change configuration
# /stats                   # Show system statistics
# /quit                    # Exit
```

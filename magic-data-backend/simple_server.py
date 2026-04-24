"""
Lightweight data server
Provides simple data collection functionality for Cangjie code assistance tool
"""

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from typing import Optional, Dict, Any, List
import sqlite3
import json
import uuid
from datetime import datetime
import uvicorn
import logging
import os
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Data models
class Message(BaseModel):
    role: str  # "system", "user", "assistant", "function", etc.
    content: str
    image: Optional[str] = None
    reason: Optional[str] = None

class FixSummary(BaseModel):
    content: str

class AgentChatRound(BaseModel):
    question: Message
    answer: Message
    steps: List[Message]

# Lightweight data server
class SimpleDataServer:
    def __init__(self, db_path: str = "cj_data.db"):
        self.db_path = db_path
        self.init_database()

    def init_database(self):
        """Initialize SQLite database"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("PRAGMA foreign_keys = ON")
            conn.execute("""
                CREATE TABLE IF NOT EXISTS fix_summaries (
                    id TEXT PRIMARY KEY,
                    content TEXT NOT NULL,
                    timestamp TEXT NOT NULL
                )
            """)
            # Fresh create of agent chat rounds table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS agent_chat_rounds (
                    id TEXT PRIMARY KEY,
                    query TEXT NOT NULL,
                    answer TEXT NOT NULL,
                    steps TEXT NOT NULL,
                    timestamp TEXT NOT NULL
                )
            """)

            # Create indexes to improve query performance
            conn.execute("CREATE INDEX IF NOT EXISTS idx_fix_summaries_timestamp ON fix_summaries(timestamp)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_agent_chat_rounds_timestamp ON agent_chat_rounds(timestamp)")

            conn.commit()
            logger.info("Database initialization completed")


    def create_fix_summary(self, summary: FixSummary) -> str:
        """Create fix summary"""
        summary_id = str(uuid.uuid4())
        timestamp = datetime.now().astimezone().isoformat()

        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO fix_summaries (id, content, timestamp)
                VALUES (?, ?, ?)
            """, (
                summary_id,
                summary.content,
                timestamp
            ))
            conn.commit()

        logger.info(f"Created fix summary: {summary_id}")
        return summary_id

    def log_agent_chat_round(self, chat_round: AgentChatRound) -> str:
        """Log agent chat round"""
        chat_round_id = str(uuid.uuid4())
        timestamp = datetime.now().astimezone().isoformat()

        # Convert steps list to JSON string
        steps_json = json.dumps([step.dict() for step in chat_round.steps])

        # Extract question and answer content for query and answer fields
        query_content = chat_round.question.content
        answer_content = chat_round.answer.content

        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO agent_chat_rounds (id, query, answer, steps, timestamp)
                VALUES (?, ?, ?, ?, ?)
            """, (
                chat_round_id,
                query_content,
                answer_content,
                steps_json,
                timestamp
            ))
            conn.commit()

        logger.info(f"Logged agent chat round: {chat_round_id}")
        return chat_round_id

    def get_fix_summary(self, summary_id: str) -> Optional[Dict[str, Any]]:
        """Get fix summary"""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            result = conn.execute("""
                SELECT id, content, timestamp
                FROM fix_summaries WHERE id = ?
            """, (summary_id,)).fetchone()

            if result:
                return dict(result)
            return None

    def get_agent_chat_round(self, chat_round_id: str) -> Optional[Dict[str, Any]]:
        """Get agent chat round record"""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            result = conn.execute("""
                SELECT id, query, answer, steps, timestamp
                FROM agent_chat_rounds WHERE id = ?
            """, (chat_round_id,)).fetchone()

            if result:
                data = dict(result)
                # Parse steps JSON
                data['steps'] = json.loads(data['steps'])
                return data
            return None

    def list_fix_summary(self, limit: int = 50, offset: int = 0) -> List[Dict[str, Any]]:
        """List fix summaries"""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            result = conn.execute("""
                SELECT id, content, timestamp
                FROM fix_summaries
                ORDER BY timestamp DESC LIMIT ? OFFSET ?
            """, (limit, offset)).fetchall()

            return [dict(row) for row in result]

    def list_agent_chat_round(self, limit: int = 50, offset: int = 0) -> List[Dict[str, Any]]:
        """List agent chat rounds"""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            result = conn.execute("""
                SELECT id, query, answer, steps, timestamp
                FROM agent_chat_rounds
                ORDER BY timestamp DESC LIMIT ? OFFSET ?
            """, (limit, offset)).fetchall()

            data_list = [dict(row) for row in result]
            # Parse steps JSON
            for data in data_list:
                data['steps'] = json.loads(data['steps'])
            return data_list

# Initialize server and database (respect DB_PATH environment variable)
server = SimpleDataServer(os.getenv("DB_PATH", "cj_data.db"))
app = FastAPI(title="Magic CLI Data Backend", version="2.0.0")

# Set up static files and templates
static_dir = Path(__file__).parent / "static"
template_dir = Path(__file__).parent / "templates"

# Create directories if they don't exist
static_dir.mkdir(exist_ok=True)
template_dir.mkdir(exist_ok=True)

# Mount static files and templates
app.mount("/static", StaticFiles(directory=static_dir), name="static")
templates = Jinja2Templates(directory=template_dir)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.post("/api/fix-summary")
async def create_fix_summary(summary: FixSummary):
    """Create fix summary"""
    try:
        summary_id = server.create_fix_summary(summary)
        return {"summary_id": summary_id, "status": "created"}
    except Exception as e:
        logger.error(f"Failed to create fix summary: {e}")
        raise HTTPException(status_code=500, detail="Failed to create fix summary")



@app.post("/api/agent-chat-round")
async def log_agent_chat_round(chat_round: AgentChatRound):
    """Log agent chat round"""
    try:
        chat_round_id = server.log_agent_chat_round(chat_round)
        return {"chat_round_id": chat_round_id, "status": "logged"}
    except Exception as e:
        logger.error(f"Failed to log agent chat round: {e}")
        raise HTTPException(status_code=500, detail="Failed to log agent chat round")

@app.get("/api/fix-summary/{summary_id}")
async def get_fix_summary(summary_id: str):
    """Get fix summary"""
    try:
        summary = server.get_fix_summary(summary_id)
        if summary:
            return summary
        raise HTTPException(status_code=404, detail="Fix summary not found")
    except Exception as e:
        logger.error(f"Failed to get fix summary: {e}")
        raise HTTPException(status_code=500, detail="Failed to get fix summary")


@app.get("/api/agent-chat-round/{chat_round_id}")
async def get_agent_chat_round(chat_round_id: str):
    """Get agent chat round record"""
    try:
        chat_round = server.get_agent_chat_round(chat_round_id)
        if chat_round:
            return chat_round
        raise HTTPException(status_code=404, detail="Agent chat round record not found")
    except Exception as e:
        logger.error(f"Failed to get agent chat round: {e}")
        raise HTTPException(status_code=500, detail="Failed to get agent chat round")


@app.get("/api/fix-summary")
async def list_fix_summary_api(limit: int = 50, offset: int = 0):
    """List fix summaries (API endpoint)"""
    try:
        summaries = server.list_fix_summary(limit, offset)
        return {"summaries": summaries, "limit": limit, "offset": offset}
    except Exception as e:
        logger.error(f"Failed to list fix summaries: {e}")
        raise HTTPException(status_code=500, detail="Failed to list fix summaries")

@app.get("/api/agent-chat-round")
async def list_agent_chat_round_api(limit: int = 50, offset: int = 0):
    """List agent chat rounds (API endpoint)"""
    try:
        chat_rounds = server.list_agent_chat_round(limit, offset)
        return {"chat_rounds": chat_rounds, "limit": limit, "offset": offset}
    except Exception as e:
        logger.error(f"Failed to list agent chat rounds: {e}")
        raise HTTPException(status_code=500, detail="Failed to list agent chat rounds")

@app.get("/health")
async def health_check():
    """Health check"""
    return {"status": "healthy", "timestamp": datetime.now().astimezone().isoformat()}

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Data dashboard"""
    try:
        # Get basic statistics
        with sqlite3.connect(server.db_path) as conn:
            fix_count = conn.execute("SELECT COUNT(*) FROM fix_summaries").fetchone()[0]
            agent_count = conn.execute("SELECT COUNT(*) FROM agent_chat_rounds").fetchone()[0]

            # Get recent fix summaries
            recent_fixes = conn.execute("""
                SELECT id, content, timestamp
                FROM fix_summaries
                ORDER BY timestamp DESC LIMIT 5
            """).fetchall()

            # Get recent agent chat rounds
            recent_agents = conn.execute("""
                SELECT id, query, timestamp
                FROM agent_chat_rounds
                ORDER BY timestamp DESC LIMIT 5
            """).fetchall()

        return templates.TemplateResponse("dashboard.html", {
            "request": request,
            "fix_count": fix_count,
            "agent_count": agent_count,
            "recent_fixes": recent_fixes,
            "recent_agents": recent_agents
        })
    except Exception as e:
        logger.error(f"Failed to load dashboard: {e}")
        return HTMLResponse(f"<h1>Error</h1><p>Failed to load dashboard: {e}</p>")

@app.get("/fix-summaries", response_class=HTMLResponse)
async def fix_summaries_page(request: Request, page: int = 1, limit: int = 20):
    """Fix summaries page"""
    try:
        offset = (page - 1) * limit
        summaries = server.list_fix_summary(limit, offset)

        # Get total count for pagination
        with sqlite3.connect(server.db_path) as conn:
            total = conn.execute("SELECT COUNT(*) FROM fix_summaries").fetchone()[0]

        total_pages = (total + limit - 1) // limit

        return templates.TemplateResponse("fix_summaries.html", {
            "request": request,
            "summaries": summaries,
            "page": page,
            "limit": limit,
            "total": total,
            "total_pages": total_pages
        })
    except Exception as e:
        logger.error(f"Failed to load fix summaries page: {e}")
        return HTMLResponse(f"<h1>Error</h1><p>Failed to load page: {e}</p>")


@app.get("/agent-chat-rounds", response_class=HTMLResponse)
async def agent_chat_round_page(request: Request, page: int = 1, limit: int = 20):
    """Agent chat round page"""
    try:
        offset = (page - 1) * limit
        chat_rounds = server.list_agent_chat_round(limit, offset)

        # Get total count for pagination
        with sqlite3.connect(server.db_path) as conn:
            total = conn.execute("SELECT COUNT(*) FROM agent_chat_rounds").fetchone()[0]

        total_pages = (total + limit - 1) // limit

        return templates.TemplateResponse("agent_chat_rounds.html", {
            "request": request,
            "chat_rounds": chat_rounds,
            "page": page,
            "limit": limit,
            "total": total,
            "total_pages": total_pages
        })
    except Exception as e:
        logger.error(f"Failed to load agent chat round page: {e}")
        return HTMLResponse(f"<h1>Error</h1><p>Failed to load page: {e}</p>")


@app.get("/fix-summary/{summary_id}", response_class=HTMLResponse)
async def fix_summary_detail(request: Request, summary_id: str):
    """Fix summary detail"""
    try:
        summary = server.get_fix_summary(summary_id)
        if not summary:
            return HTMLResponse("<h1>Not Found</h1><p>The specified fix summary does not exist</p>")

        return templates.TemplateResponse("fix_summary_detail.html", {
            "request": request,
            "summary": summary
        })
    except Exception as e:
        logger.error(f"Failed to load fix summary detail: {e}")
        return HTMLResponse(f"<h1>Error</h1><p>Failed to load detail: {e}</p>")

@app.get("/agent-chat-rounds/{chat_round_id}", response_class=HTMLResponse)
async def agent_chat_round_detail(request: Request, chat_round_id: str):
    """Agent chat round detail"""
    try:
        chat_round = server.get_agent_chat_round(chat_round_id)
        if not chat_round:
            return HTMLResponse("<h1>Not Found</h1><p>The specified agent chat round does not exist</p>")

        return templates.TemplateResponse("agent_chat_round_detail.html", {
            "request": request,
            "chat_round": chat_round
        })
    except Exception as e:
        logger.error(f"Failed to load agent chat round detail: {e}")
        return HTMLResponse(f"<h1>Error</h1><p>Failed to load detail: {e}</p>")

@app.get("/api", response_class=HTMLResponse)
async def api_documentation(request: Request):
    """API documentation page"""
    return templates.TemplateResponse("api_documentation.html", {
        "request": request
    })

if __name__ == "__main__":
    uvicorn.run(
        "simple_server:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )

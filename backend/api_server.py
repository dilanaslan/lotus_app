import csv
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List
from main import generate_response

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

BASE_DIR = Path(__file__).resolve().parent
PROFILES_CSV = BASE_DIR / "profiles.csv"
JOURNAL_CSV = BASE_DIR / "journal.csv"
FEELINGS_CSV = BASE_DIR / "feelings.csv"

EMOTION_EMOJIS = {
    "Happy": "😊",
    "Loved": "😍",
    "Confident": "😎",
    "Excited": "🥳",
    "Calm": "😇",
    "Grateful": "🤗",
    "Hopeful": "🌈",
    "Motivated": "💪",
    "Peaceful": "🧘",
    "Inspired": "✨",
    "Sad": "😔",
    "Angry": "😡",
    "Anxious": "😰",
    "Tired": "😴",
    "Confused": "😕",
    "Disappointed": "😞",
    "Stressed": "😣",
    "Numb": "😶",
    "Overwhelmed": "😓",
    "Lonely": "💔",
}

app = FastAPI(title="Lotus Backend API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class HobbyItem(BaseModel):
    title: str
    rating: int = 0


class SaveProfileRequest(BaseModel):
    email: str
    name: str = ""
    birthday: str = ""
    gender: str = ""
    location: str = ""
    hobbies: List[HobbyItem] = Field(default_factory=list)
    savedAt: str | None = None


class SaveJournalRequest(BaseModel):
    email: str
    text: str
    date: str | None = None


class FeelingItem(BaseModel):
    emoji: str = ""
    label: str
    type: str
    level: int
    note: str = ""


class SaveFeelingsRequest(BaseModel):
    email: str
    date: str | None = None
    emotions: List[FeelingItem]
    goodPercent: int
    badPercent: int


class ChatRequest(BaseModel):
    email: str
    text: str


def ensure_csv(file_path: Path, header: List[str]) -> None:
    if not file_path.exists():
        with file_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(header)


def append_csv(file_path: Path, header: List[str], row: List[Any]) -> None:
    ensure_csv(file_path, header)
    with file_path.open("a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(row)


def now_iso() -> str:
    return datetime.utcnow().isoformat()


def get_user_memory(email: str) -> Dict[str, Any]:
    profile = None
    journals: List[Dict[str, Any]] = []
    feelings: List[Dict[str, Any]] = []

    if PROFILES_CSV.exists():
        with PROFILES_CSV.open("r", newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            rows = [row for row in reader if row.get("email") == email]
            if rows:
                profile = rows[-1]

    if JOURNAL_CSV.exists():
        with JOURNAL_CSV.open("r", newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            journals = [row for row in reader if row.get("email") == email][-10:]

    if FEELINGS_CSV.exists():
        with FEELINGS_CSV.open("r", newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            feelings = [row for row in reader if row.get("email") == email][-20:]

    return {
        "email": email,
        "profile": profile,
        "journals": journals,
        "feelings": feelings,
    }


def get_user_journals(email: str) -> List[Dict[str, Any]]:
    if not JOURNAL_CSV.exists():
        return []

    with JOURNAL_CSV.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        return [row for row in reader if row.get("email") == email]


def get_user_feelings(email: str) -> List[Dict[str, Any]]:
    if not FEELINGS_CSV.exists():
        return []

    grouped: Dict[str, Dict[str, Any]] = {}

    with FEELINGS_CSV.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("email") != email:
                continue

            session_date = row.get("sessionDate") or row.get("date") or now_iso()
            entry = grouped.setdefault(
                session_date,
                {
                    "email": email,
                    "date": session_date,
                    "emotions": [],
                    "goodPercent": int(row.get("goodPercent") or 0),
                    "badPercent": int(row.get("badPercent") or 0),
                },
            )

            try:
                level = int(row.get("level") or 0)
            except ValueError:
                level = 0

            entry["emotions"].append(
                {
                    "emoji": row.get("emoji") or EMOTION_EMOJIS.get(row.get("emotion", ""), ""),
                    "label": row.get("emotion", ""),
                    "type": row.get("type", ""),
                    "level": level,
                    "note": row.get("note", ""),
                }
            )

    return list(grouped.values())


def build_memory_summary(memory: Dict[str, Any]) -> str:
    profile = memory.get("profile")
    journals = memory.get("journals", [])
    feelings = memory.get("feelings", [])

    parts = []

    if profile:
        parts.append(
            "User profile: "
            f"name={profile.get('name', '')}, "
            f"location={profile.get('location', '')}, "
            f"gender={profile.get('gender', '')}, "
            f"birthday={profile.get('birthday', '')}"
        )

    if journals:
        recent_journals = [
            f"- {j.get('date', '')}: {j.get('text', '')}"
            for j in journals[-3:]
        ]
        parts.append("Recent journal entries:\n" + "\n".join(recent_journals))

    if feelings:
        recent_feelings = [
            f"- {f.get('sessionDate', '')}: "
            f"{f.get('emotion', '')} ({f.get('type', '')}) level {f.get('level', '')}, "
            f"note={f.get('note', '')}, "
            f"good={f.get('goodPercent', '')}%, bad={f.get('badPercent', '')}%"
            for f in feelings[-5:]
        ]
        parts.append("Recent feelings:\n" + "\n".join(recent_feelings))

    return "\n\n".join(parts).strip()


def simple_chat_response(user_text: str, memory: Dict[str, Any]) -> str:
    profile = memory.get("profile")
    name = ""
    if profile and profile.get("name"):
        name = profile["name"]

    feelings = memory.get("feelings", [])
    journals = memory.get("journals", [])

    intro = f"{name}, " if name else ""

    if feelings:
        last_feeling = feelings[-1]
        emotion = last_feeling.get("emotion", "")
        note = last_feeling.get("note", "")
        if emotion:
            return (
                f"{intro}seni daha iyi anlayabilmek için son his kaydına da baktim. "
                f"Son zamanlarda '{emotion}' duygusu one cikmis gorunuyor. "
                f"{'Notunda ' + note + ' demissin. ' if note else ''}"
                f"Bu konuda biraz daha anlatmak ister misin?"
            )

    if journals:
        last_journal = journals[-1].get("text", "")
        if last_journal:
            return (
                f"{intro}son journal kaydinda paylastiklarin benim icin onemli. "
                f"Son yazinda su dikkatimi cekti: '{last_journal}'. "
                f"Bunun su an sende nasil bir etkisi var?"
            )

    return (
        f"{intro}buradayim ve seni dinliyorum. "
        f"Mesajinda '{user_text}' dedin. "
        f"Bunu biraz daha acmak ister misin?"
    )


@app.get("/")
def root():
    return {"status": "ok", "message": "Lotus backend is running"}


@app.post("/save-profile")
def save_profile(payload: SaveProfileRequest):
    saved_at = payload.savedAt or now_iso()
    hobbies_text = "|".join(
        f"{hobby.title}:{hobby.rating}" for hobby in payload.hobbies
    )

    append_csv(
        PROFILES_CSV,
        ["email", "name", "birthday", "gender", "location", "hobbies", "savedAt"],
        [
            payload.email,
            payload.name,
            payload.birthday,
            payload.gender,
            payload.location,
            hobbies_text,
            saved_at,
        ],
    )

    return {
        "success": True,
        "message": "Profile saved",
        "file": str(PROFILES_CSV),
    }


@app.post("/save-journal")
def save_journal(payload: SaveJournalRequest):
    entry_date = payload.date or now_iso()

    append_csv(
        JOURNAL_CSV,
        ["email", "date", "text"],
        [payload.email, entry_date, payload.text],
    )

    return {
        "success": True,
        "message": "Journal saved",
        "file": str(JOURNAL_CSV),
    }


@app.post("/save-feelings")
def save_feelings(payload: SaveFeelingsRequest):
    entry_date = payload.date or now_iso()

    ensure_csv(
        FEELINGS_CSV,
        ["email", "sessionDate", "emotion", "type", "level", "note", "goodPercent", "badPercent"],
    )

    with FEELINGS_CSV.open("a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        for emotion in payload.emotions:
            writer.writerow([
                payload.email,
                entry_date,
                emotion.label,
                emotion.type,
                emotion.level,
                emotion.note,
                payload.goodPercent,
                payload.badPercent,
            ])

    return {
        "success": True,
        "message": "Feelings saved",
        "file": str(FEELINGS_CSV),
        "rowsWritten": len(payload.emotions),
    }


@app.get("/journals")
def journals(email: str):
    return {
        "success": True,
        "journals": get_user_journals(email),
    }


@app.get("/feelings")
def feelings(email: str):
    return {
        "success": True,
        "feelings": get_user_feelings(email),
    }


@app.get("/user-memory")
def user_memory(email: str):
    return get_user_memory(email)


@app.post("/chat")
def chat(payload: ChatRequest):
    memory = get_user_memory(payload.email)
    memory_summary = build_memory_summary(memory)

    response = generate_response(
        prompt=payload.text,
        current_user_email=payload.email
    )

    #response = simple_chat_response(payload.text, memory)

    return {
        "response": response,
        "memory_summary": memory_summary,
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("api_server:app", host="0.0.0.0", port=8000, reload=True)

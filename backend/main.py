import os
import re
import csv
from pathlib import Path

import torch
import torch.nn as nn
from torch.nn import functional as F
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

# =========================================================
# 1. SETTINGS
# =========================================================
BASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BASE_DIR.parent


def load_local_env() -> None:
    for env_path in (PROJECT_DIR / ".env", BASE_DIR / ".env"):
        if not env_path.exists():
            continue

        for raw_line in env_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue

            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")

            if key and key not in os.environ:
                os.environ[key] = value


load_local_env()

device = "cuda" if torch.cuda.is_available() else "cpu"
DEBUG_MODE = True

block_size = 128
n_embd = 256
n_head = 8
n_layer = 6
dropout = 0.2

# Relative paths
data_path = BASE_DIR / "mentalhealth_cleaned_final.csv"
notes_path = BASE_DIR / "journal.csv"   # api_server bunu yazacak
checkpoint_path = BASE_DIR / "mental_health_bot_v3.pth"

SPECIAL_TOKENS = ["<PAD>", "<UNK>", "<USER>", "<BOT>", "<SEP>", "<EOS>"]

# API
USE_API_FALLBACK = True
GEMINI_MODEL = "gemini-2.5-flash"
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY", "")

# Retrieval thresholds
RETRIEVAL_API_THRESHOLD = 0.35
NOTES_MIN_SCORE = 0.03

chat_history_by_user = {}
memory_by_user = {}

# =========================================================
# 2. HELPER FUNCTIONS
# =========================================================
def clean_text(s: str) -> str:
    s = str(s).strip().lower()
    s = s.replace("’", "'").replace("“", '"').replace("”", '"')
    s = re.sub(r"\s+", " ", s)
    return s


def normalize_for_detection(text: str) -> str:
    text = str(text).lower().strip()
    text = text.replace("’", "'").replace("“", '"').replace("”", '"')
    text = re.sub(r"\s+", " ", text)
    return text


def tokenize(text: str):
    return re.findall(r"<[^>]+>|[\w']+|[.,!?;:]", text.lower())


def normalize_output(text: str) -> str:
    if not text:
        return ""

    text = re.sub(r"<[^>]+>", " ", text)
    text = text.replace(" .", ".").replace(" ,", ",")
    text = text.replace(" !", "!").replace(" ?", "?")
    text = text.replace(" ;", ";").replace(" :", ":")
    text = re.sub(r"\s+", " ", text).strip()

    if text:
        text = text[0].upper() + text[1:]

    return text


def safe_capitalize_after_name(text: str) -> str:
    if not text:
        return text
    if len(text) == 1:
        return text.lower()
    return text[0].lower() + text[1:]


def deduplicate_topics(topics):
    return list(dict.fromkeys(topics))


def detect_name(prompt: str):
    patterns = [
        r"(?:my name is|i am|call me)\s+([a-zA-Z]+)",
    ]

    prompt_l = normalize_for_detection(prompt)
    for pattern in patterns:
        m = re.search(pattern, prompt_l)
        if m:
            return m.group(1).capitalize()
    return None


def get_user_state(user_email: str):
    user_email = clean_text(user_email or "anonymous@example.com")

    if user_email not in memory_by_user:
        memory_by_user[user_email] = {
            "name": None,
            "topics": [],
            "last_emotion": None,
        }

    if user_email not in chat_history_by_user:
        chat_history_by_user[user_email] = []

    return memory_by_user[user_email], chat_history_by_user[user_email]


def update_memory(prompt: str, memory: dict):
    prompt_l = normalize_for_detection(prompt)

    found_name = detect_name(prompt)
    if found_name:
        memory["name"] = found_name

    topic_keywords = [
        "stress", "stressful", "anxiety", "depression", "sleep", "burnout",
        "university", "sad", "lonely", "panic", "waking", "motivation",
        "study", "exam", "exams", "therapy", "cbt", "overwhelmed", "tired",
        "deadline", "deadlines", "pressure", "focus", "fatigue", "hopeless",
        "chaotic", "racing", "presentation", "presentations", "friend", "friends"
    ]

    for kw in topic_keywords:
        if kw in prompt_l:
            memory["topics"].append(kw)

    emotion_keywords = [
        "sad", "lonely", "stressful", "overwhelmed", "burnout",
        "anxious", "depressed", "tired", "hopeless", "worried",
        "stressed", "afraid", "panic", "chaotic"
    ]

    for ek in emotion_keywords:
        if ek in prompt_l:
            memory["last_emotion"] = ek
            break

    memory["topics"] = deduplicate_topics(memory["topics"])[-10:]


def is_crisis_prompt(prompt: str) -> bool:
    p = normalize_for_detection(prompt)

    crisis_patterns = [
        "i don't want to live",
        "i do not want to live",
        "i dont want to live",
        "i want to die",
        "kill myself",
        "end my life",
        "suicide",
        "self harm",
        "self-harm",
        "hurt myself",
        "i want to disappear forever",
        "i don't want to be alive",
        "i dont want to be alive",
        "i want to end everything",
    ]

    return any(cp in p for cp in crisis_patterns)


def build_safety_response() -> str:
    return (
        "I'm really sorry that you're going through this. "
        "You deserve immediate support right now. "
        "Please contact a trusted person near you or emergency support in your area now. "
        "If you might act on these feelings, call emergency services immediately or go to the nearest emergency department. "
        "You do not have to handle this alone."
    )


def is_bad_response(text: str, prompt: str = "") -> bool:
    if not text:
        return True

    t = normalize_for_detection(text)
    p = normalize_for_detection(prompt)

    bad_patterns = [
        "<eos>", "<bot>", "<user>", "<sep>",
        "licensed professional can help",
        "seek urgent help and a",
        "i am here for weeks",
        "support a bit?",
        "yes, even if you feel",
        "a licensed professional support",
        "many people pleasing",
        "sleep problems can involve feelings like",
        "anger can involve feelings like",
        "negative self esteem",
        "daytime sleepiness",
        "that is your anxiety talking not the reality",
        "can involve feelings like",
    ]

    if any(bp in t for bp in bad_patterns):
        return True

    words = t.split()
    if len(words) < 6:
        return True

    unique_ratio = len(set(words)) / max(len(words), 1)
    if unique_ratio < 0.50:
        return True

    bad_endings = ["and a", "and", "or", "but", "with", "for", "to", "of", "in", "on", "a"]
    if any(t.endswith(be) for be in bad_endings):
        return True

    weird_chunks = [
        "i am here for weeks",
        "disrupt daily life",
        "professional support a bit",
        "seek urgent help and a",
    ]
    if any(w in t for w in weird_chunks):
        return True

    if ("advice" in p or "help" in p) and len(words) < 8:
        return True

    return False


def is_repetitive_response(candidate: str, chat_history: list) -> bool:
    if not candidate or len(chat_history) < 2:
        return False

    recent_bot_texts = []
    for turn in chat_history[-6:]:
        if turn.startswith("<BOT> "):
            recent_bot_texts.append(turn.replace("<BOT> ", "").strip())

    cand = clean_text(candidate)
    return cand in recent_bot_texts


def note_soft_signal(notes):
    if not notes:
        return ""

    text = " ".join([n for n, _, _ in notes[:3]])

    if any(k in text for k in ["exam", "exams", "study", "finals"]):
        return "This seems connected to some study-related pressure you've been dealing with. "
    if any(k in text for k in ["sleep", "wake", "tired"]):
        return "It sounds like this may also be affecting your rest and energy. "
    if any(k in text for k in ["panic", "anxious", "anxiety", "presentation"]):
        return "This seems related to a pattern of anxiety you've been struggling with. "
    if any(k in text for k in ["lonely", "friend", "friends", "argument"]):
        return "It sounds tied to some emotionally difficult situations you've been carrying. "
    if any(k in text for k in ["deadline", "overwhelmed", "motivation"]):
        return "This seems connected to an ongoing pattern of pressure and mental overload. "

    return "This seems connected to something you've been struggling with for a while. "

# =========================================================
# 3. LOAD QA DATA
# =========================================================
def load_qa_pairs(file_path):
    qa_pairs = []

    if not Path(file_path).exists():
        raise FileNotFoundError(f"CSV bulunamadı: {file_path}")

    with open(file_path, "r", encoding="utf-8", errors="ignore", newline="") as f:
        reader = csv.reader(f)
        next(reader, None)

        for row in reader:
            if len(row) < 3:
                continue

            q = clean_text(row[1])
            a = clean_text(row[2])

            if q and a:
                qa_pairs.append((q, a))

    if not qa_pairs:
        raise ValueError("CSV içinden soru-cevap verisi okunamadı.")

    return qa_pairs

# =========================================================
# 4. LOAD JOURNAL NOTES BY USER
# =========================================================
def load_notes_by_user(file_path):
    """
    Header'lı veya header'sız iki formatı da destekler:
    email,timestamp,note
    """
    notes_by_user = {}
    path = Path(file_path)

    if not path.exists():
        print(f"[WARN] journal.csv bulunamadı: {file_path}")
        return notes_by_user

    with open(path, "r", encoding="utf-8-sig", errors="ignore", newline="") as f:
        reader = csv.reader(f)

        for row in reader:
            if not row or len(row) < 3:
                continue

            email = clean_text(row[0])
            timestamp = str(row[1]).strip()
            note = clean_text(row[2])

            # boş/header satırlarını atla
            if not email and not timestamp and not note:
                continue
            if email in ["email", "mail", "user_email"] and "time" in clean_text(timestamp):
                continue
            if email == "email" and note == "text":
                continue

            if not email or not note:
                continue

            if email not in notes_by_user:
                notes_by_user[email] = []

            notes_by_user[email].append({
                "timestamp": timestamp,
                "note": note
            })

    return notes_by_user


qa_pairs = load_qa_pairs(data_path)
notes_by_user = load_notes_by_user(notes_path)

formatted_samples = [
    f"<USER> {q} <SEP> <BOT> {a} <EOS>"
    for q, a in qa_pairs
]

all_text = " ".join(formatted_samples)
tokens = tokenize(all_text)
unique_tokens = sorted(set(tokens))

vocab = SPECIAL_TOKENS + [t for t in unique_tokens if t not in SPECIAL_TOKENS]
vocab_size = len(vocab)

stoi = {w: i for i, w in enumerate(vocab)}
itos = {i: w for i, w in enumerate(vocab)}

PAD_ID = stoi["<PAD>"]
UNK_ID = stoi["<UNK>"]
EOS_ID = stoi["<EOS>"]


def encode(text: str):
    return [stoi.get(tok, UNK_ID) for tok in tokenize(text)]

# =========================================================
# 5. RETRIEVAL
# =========================================================
questions = [q for q, _ in qa_pairs]
answers = [a for _, a in qa_pairs]

vectorizer = TfidfVectorizer(
    ngram_range=(1, 3),
    lowercase=True,
    max_features=10000
)
X = vectorizer.fit_transform(questions)


def refresh_notes():
    global notes_by_user
    notes_by_user = load_notes_by_user(notes_path)


def build_user_notes_index(user_email: str):
    refresh_notes()
    user_email = clean_text(user_email)

    if user_email not in notes_by_user:
        return [], None, None

    user_rows = notes_by_user[user_email]
    user_notes = [item["note"] for item in user_rows]

    if not user_notes:
        return [], None, None

    user_vectorizer = TfidfVectorizer(
        ngram_range=(1, 3),
        lowercase=True,
        max_features=10000
    )
    user_notes_X = user_vectorizer.fit_transform(user_notes)

    return user_rows, user_vectorizer, user_notes_X


def retrieve_relevant_examples(user_input: str, top_k: int = 5):
    query = clean_text(user_input)
    q_vec = vectorizer.transform([query])
    sims = cosine_similarity(q_vec, X)[0]
    top_ids = sims.argsort()[-top_k:][::-1]

    examples = []
    for idx in top_ids:
        score = float(sims[idx])
        if score >= 0.10:
            q, a = qa_pairs[idx]
            examples.append((q, a, score))

    return examples


def retrieve_relevant_notes(user_input: str, user_email: str, top_k: int = 3, min_score: float = NOTES_MIN_SCORE):
    if not user_email:
        return []

    user_rows, user_vectorizer, user_notes_X = build_user_notes_index(user_email)

    if not user_rows or user_vectorizer is None or user_notes_X is None:
        if DEBUG_MODE:
            print(f"[DEBUG] No notes found for user: {user_email}")
        return []

    query = clean_text(user_input)
    q_vec = user_vectorizer.transform([query])
    sims = cosine_similarity(q_vec, user_notes_X)[0]
    top_ids = sims.argsort()[-top_k:][::-1]

    found_notes = []

    if DEBUG_MODE:
        print(f"[DEBUG] notes query = {query}")
        print(f"[DEBUG] current_user_email = {user_email}")
        print("[DEBUG] top user-note candidates:")

    for idx in top_ids:
        score = float(sims[idx])
        row = user_rows[idx]
        note_text = row["note"]
        note_time = row["timestamp"]

        if DEBUG_MODE:
            print(f"    score={score:.4f} | time={note_time} | note={note_text}")

        if score >= min_score:
            found_notes.append((note_text, score, note_time))

    return found_notes


def should_use_api_from_retrieval(examples, min_score=RETRIEVAL_API_THRESHOLD):
    if not examples:
        return True

    best_score = examples[0][2]
    return best_score < min_score


def build_fallback_response(prompt: str, examples, notes=None):
    prompt_l = normalize_for_detection(prompt)

    emotion_prefix = ""
    if any(w in prompt_l for w in ["stress", "stressed", "overwhelmed", "deadline", "pressure"]):
        emotion_prefix = "It sounds like you are under a lot of pressure right now. "
    elif any(w in prompt_l for w in ["sad", "lonely", "hopeless", "tired"]):
        emotion_prefix = "That sounds really heavy to carry on your own. "
    elif any(w in prompt_l for w in ["anxious", "panic", "worried", "chaotic", "racing"]):
        emotion_prefix = "It sounds like your mind has been under a lot of tension. "

    notes_prefix = note_soft_signal(notes)

    if "relaxation exercise" in prompt_l or ("relax" in prompt_l and "exercise" in prompt_l):
        return normalize_output(
            notes_prefix +
            "Let's try a short breathing exercise. "
            "Breathe in gently for 4 seconds, hold for 4 seconds, and breathe out slowly for 6 seconds. "
            "Repeat this 5 times and relax your shoulders while you do it."
        )

    if examples:
        best_q, best_a, best_score = examples[0]
        response = best_a.strip()

        return normalize_output(notes_prefix + emotion_prefix + response)

    generic = (
        "It sounds like you're having a hard time right now. "
        "Let's slow it down for a moment. "
        "Take one deep breath and tell me what feels hardest right now."
    )
    return normalize_output(notes_prefix + emotion_prefix + generic)

# =========================================================
# 6. MODEL
# =========================================================
class Head(nn.Module):
    def __init__(self, head_size):
        super().__init__()
        self.key = nn.Linear(n_embd, head_size, bias=False)
        self.query = nn.Linear(n_embd, head_size, bias=False)
        self.value = nn.Linear(n_embd, head_size, bias=False)
        self.register_buffer("tril", torch.tril(torch.ones(block_size, block_size)))
        self.dropout = nn.Dropout(dropout)

    def forward(self, x):
        B, T, C = x.shape

        k = self.key(x)
        q = self.query(x)
        v = self.value(x)

        head_dim = k.size(-1)
        wei = q @ k.transpose(-2, -1) * (head_dim ** -0.5)
        wei = wei.masked_fill(self.tril[:T, :T] == 0, float("-inf"))
        wei = F.softmax(wei, dim=-1)
        wei = self.dropout(wei)

        out = wei @ v
        return out


class MultiHeadAttention(nn.Module):
    def __init__(self, num_heads, head_size):
        super().__init__()
        self.heads = nn.ModuleList([Head(head_size) for _ in range(num_heads)])
        self.proj = nn.Linear(n_embd, n_embd)
        self.dropout = nn.Dropout(dropout)

    def forward(self, x):
        out = torch.cat([h(x) for h in self.heads], dim=-1)
        out = self.proj(out)
        out = self.dropout(out)
        return out


class FeedForward(nn.Module):
    def __init__(self, n_embd):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(n_embd, 4 * n_embd),
            nn.ReLU(),
            nn.Linear(4 * n_embd, n_embd),
            nn.Dropout(dropout),
        )

    def forward(self, x):
        return self.net(x)


class Block(nn.Module):
    def __init__(self, n_embd, n_head):
        super().__init__()
        head_size = n_embd // n_head
        self.sa = MultiHeadAttention(n_head, head_size)
        self.ffwd = FeedForward(n_embd)
        self.ln1 = nn.LayerNorm(n_embd)
        self.ln2 = nn.LayerNorm(n_embd)

    def forward(self, x):
        x = x + self.sa(self.ln1(x))
        x = x + self.ffwd(self.ln2(x))
        return x


class ChatBot(nn.Module):
    def __init__(self, vocab_size):
        super().__init__()
        self.token_embedding = nn.Embedding(vocab_size, n_embd)
        self.position_embedding = nn.Embedding(block_size, n_embd)
        self.blocks = nn.Sequential(*[Block(n_embd, n_head) for _ in range(n_layer)])
        self.ln_f = nn.LayerNorm(n_embd)
        self.lm_head = nn.Linear(n_embd, vocab_size)

    def forward(self, idx, targets=None):
        B, T = idx.shape

        tok_emb = self.token_embedding(idx)
        pos = torch.arange(T, device=idx.device)
        pos_emb = self.position_embedding(pos)

        x = tok_emb + pos_emb
        x = self.blocks(x)
        x = self.ln_f(x)
        logits = self.lm_head(x)

        return logits, None


model = ChatBot(vocab_size).to(device)

if Path(checkpoint_path).exists():
    try:
        checkpoint = torch.load(checkpoint_path, map_location=device)
        if checkpoint.get("vocab") == vocab and "model_state_dict" in checkpoint:
            model.load_state_dict(checkpoint["model_state_dict"])
            if DEBUG_MODE:
                print(f"[DEBUG] Model loaded: {checkpoint_path}")
        else:
            if DEBUG_MODE:
                print("[DEBUG] Checkpoint vocab mismatch. Retrieval answer will still work.")
    except Exception as e:
        if DEBUG_MODE:
            print(f"[DEBUG] Checkpoint load error: {e}")
else:
    if DEBUG_MODE:
        print("[DEBUG] Checkpoint not found. Retrieval answer will still work.")

model.eval()

# =========================================================
# 7. CONTEXT
# =========================================================
def build_context(user_input: str, examples, notes, memory, chat_history):
    parts = []
    memory_parts = []

    if memory["name"]:
        memory_parts.append(f"name {memory['name'].lower()}")

    if memory["last_emotion"]:
        memory_parts.append(f"emotion {memory['last_emotion']}")

    if memory["topics"]:
        uniq_topics = deduplicate_topics(memory["topics"][-5:])
        memory_parts.append("topics " + " ".join(uniq_topics))

    if memory_parts:
        memory_text = " ; ".join(memory_parts)
        parts.append(f"<USER> memory {memory_text} <SEP> <BOT> understood <EOS>")

    if notes:
        for note_text, score, note_time in notes[:3]:
            parts.append(f"<USER> background note {note_text} <SEP> <BOT> acknowledged <EOS>")

    for q, a, sim in examples[:3]:
        parts.append(f"<USER> {q} <SEP> <BOT> {a} <EOS>")

    recent_turns = chat_history[-6:]
    for turn in recent_turns:
        parts.append(turn)

    parts.append(f"<USER> {clean_text(user_input)} <SEP> <BOT>")
    return " ".join(parts)

# =========================================================
# 8. SAMPLING
# =========================================================
def choose_generation_controls(prompt: str):
    p = normalize_for_detection(prompt)

    if any(x in p for x in ["hopeless", "panic", "anxious", "worried", "stressed", "chaotic", "racing"]):
        return 0.60, 18
    if any(x in p for x in ["advice", "what should i do", "help"]):
        return 0.65, 20
    if "why" in p:
        return 0.62, 18
    return 0.68, 20


def sample_next_token(logits, temperature=0.65, top_k=20):
    logits = logits / max(temperature, 1e-6)
    values, indices = torch.topk(logits, k=min(top_k, logits.size(-1)))
    probs_topk = F.softmax(values, dim=-1)
    sampled_idx = torch.multinomial(probs_topk, num_samples=1)
    next_token = indices.gather(-1, sampled_idx)
    return next_token

# =========================================================
# 9. LOCAL MODEL RESPONSE
# =========================================================
def generate_model_response(prompt: str, examples, notes, memory, chat_history, max_new_tokens: int = 60):
    if examples and examples[0][2] >= RETRIEVAL_API_THRESHOLD and not notes:
        return normalize_output(examples[0][1])

    context_text = build_context(prompt, examples, notes, memory, chat_history)
    input_ids = encode(context_text)

    if len(input_ids) >= block_size:
        input_ids = input_ids[-(block_size - 1):]

    idx = torch.tensor([input_ids], dtype=torch.long, device=device)
    generated = []

    blocked_tokens = ["<PAD>", "<UNK>", "<USER>", "<BOT>", "<SEP>"]
    blocked_ids = [stoi[t] for t in blocked_tokens if t in stoi]

    wrong_names = ["lina", "ali", "sarah", "maya", "john", "david"]
    wrong_name_ids = [stoi[w] for w in wrong_names if w in stoi]

    temperature, top_k = choose_generation_controls(prompt)

    for step in range(max_new_tokens):
        idx_cond = idx[:, -block_size:]

        with torch.no_grad():
            logits, _ = model(idx_cond)

        logits = logits[:, -1, :]

        for bad_id in blocked_ids:
            logits[0, bad_id] -= 100.0

        for wid in wrong_name_ids:
            logits[0, wid] -= 25.0

        for token_id in set(generated[-12:]):
            logits[0, token_id] -= 1.5

        next_token = sample_next_token(logits, temperature=temperature, top_k=top_k)
        token_id = next_token.item()

        if token_id == EOS_ID:
            break

        token = itos[token_id]

        if token.startswith("<") and token.endswith(">"):
            break

        generated.append(token_id)
        idx = torch.cat((idx, next_token), dim=1)

        if step >= 18 and token in [".", "!", "?"]:
            break

    response = " ".join([itos[t] for t in generated])
    response = normalize_output(response)

    if notes and response:
        soft_prefix = note_soft_signal(notes)
        if soft_prefix and not response.lower().startswith(("this seems", "it sounds")):
            response = normalize_output(soft_prefix + response)

    return response

# =========================================================
# 10. API
# =========================================================
def build_api_messages(prompt: str, examples, notes, memory):
    context_notes = []

    if memory["name"]:
        context_notes.append(f"User name: {memory['name']}")

    if memory["last_emotion"]:
        context_notes.append(f"Last detected emotion: {memory['last_emotion']}")

    if memory["topics"]:
        context_notes.append(f"Topics: {', '.join(deduplicate_topics(memory['topics'][-5:]))}")

    if notes:
        note_lines = []
        for note_text, score, note_time in notes[:3]:
            note_lines.append(f"Background user note ({note_time}): {note_text}")
        context_notes.append("\n".join(note_lines))

    if examples:
        ex_lines = []
        for q, a, score in examples[:3]:
            ex_lines.append(f"Example user: {q}\nExample assistant: {a}")
        context_notes.append("\n".join(ex_lines))

    context_block = "\n".join(context_notes).strip()

    system_prompt = (
        "You are a supportive mental health chatbot assistant. "
        "Be warm, calm, empathetic, and practical. "
        "Use the provided background notes only as hidden context when relevant. "
        "Do not explicitly say things like 'I remember from your notes' or 'your notes say'. "
        "Do not quote the notes directly unless the user asks. "
        "Do not invent facts not grounded in the notes or the current user message. "
        "Do not diagnose. Do not claim to be a therapist. "
        "Give short, natural, conversational responses in English. "
        "If the user's message suggests immediate danger or self-harm, encourage urgent real-world support immediately. "
        "Avoid repeating the same sentence. "
        "Avoid incomplete responses. "
        "Keep the answer clear and finished."
    )

    user_prompt = f"Context:\n{context_block}\n\nUser message:\n{prompt}\n\nRespond naturally."
    return system_prompt, user_prompt


def generate_api_response(prompt: str, examples, notes, memory):
    if not USE_API_FALLBACK or not GEMINI_API_KEY:
        return None

    try:
        from google import genai

        client = genai.Client(api_key=GEMINI_API_KEY)
        system_prompt, user_prompt = build_api_messages(prompt, examples, notes, memory)

        response = client.models.generate_content(
            model=GEMINI_MODEL,
            config={"system_instruction": system_prompt},
            contents=user_prompt
        )

        if response and response.text:
            return normalize_output(response.text.strip())

        return None

    except Exception as e:
        if DEBUG_MODE:
            print(f"[DEBUG] [API fallback error] {e}")
        return None

# =========================================================
# 11. MAIN RESPONSE FUNCTION
# =========================================================
def generate_response(prompt: str, current_user_email: str):
    current_user_email = clean_text(current_user_email or "anonymous@example.com")
    memory, chat_history = get_user_state(current_user_email)

    update_memory(prompt, memory)
    p_clean = normalize_for_detection(prompt)

    greetings = ["hi", "hello", "hey", "hello there", "good morning"]
    is_greeting = any(p_clean == g for g in greetings)
    is_intro = any(x in p_clean for x in ["my name is", "i am", "call me"]) and len(p_clean.split()) < 6

    if is_greeting or is_intro:
        name_part = f" {memory['name']}" if memory["name"] else ""
        final_response = f"Hi{name_part}! How can I help you today?"

        chat_history.append(f"<USER> {clean_text(prompt)}")
        chat_history.append(f"<BOT> {clean_text(final_response)}")
        return final_response

    if is_crisis_prompt(prompt):
        final_response = build_safety_response()
        chat_history.append(f"<USER> {clean_text(prompt)}")
        chat_history.append(f"<BOT> {clean_text(final_response)}")
        return final_response

    examples = retrieve_relevant_examples(prompt, top_k=5)
    notes = retrieve_relevant_notes(prompt, current_user_email, top_k=3)

    use_api_because_not_found = should_use_api_from_retrieval(
        examples,
        min_score=RETRIEVAL_API_THRESHOLD
    )

    if DEBUG_MODE:
        print(f"[DEBUG] current_user_email = {current_user_email}")
        print(f"[DEBUG] examples_found = {len(examples)}")
        print(f"[DEBUG] notes_found = {len(notes)}")
        if examples:
            print(f"[DEBUG] best_retrieval_score = {examples[0][2]:.4f}")
        if notes:
            print(f"[DEBUG] best_note_score = {notes[0][1]:.4f}")
            print(f"[DEBUG] best_note_time = {notes[0][2]}")
        print(f"[DEBUG] use_api_because_not_found = {use_api_because_not_found}")

    if use_api_because_not_found:
        api_response = generate_api_response(prompt, examples, notes, memory)

        if api_response and not is_bad_response(api_response, prompt):
            final_response = api_response
            if DEBUG_MODE:
                print("[DEBUG] Final source = API")
        else:
            final_response = build_fallback_response(prompt, examples, notes)
            if DEBUG_MODE:
                print("[DEBUG] Final source = fallback (API unavailable/weak)")
    else:
        model_response = generate_model_response(prompt, examples, notes, memory, chat_history)
        fallback_response = build_fallback_response(prompt, examples, notes)

        if DEBUG_MODE:
            print(f"[DEBUG] model_response = {model_response}")
            print(f"[DEBUG] fallback_response = {fallback_response}")

        if is_bad_response(model_response, prompt) or is_repetitive_response(model_response, chat_history):
            final_response = fallback_response
            if DEBUG_MODE:
                print("[DEBUG] Final source = local fallback")
        else:
            final_response = model_response
            if DEBUG_MODE:
                print("[DEBUG] Final source = local model/retrieval")

            if len(final_response.split()) < 10 and examples:
                final_response = normalize_output(f"{final_response} {examples[0][1]}")

    if memory["name"] and len(chat_history) == 0:
        final_response = f"Hi {memory['name']}, {safe_capitalize_after_name(final_response)}"

    chat_history.append(f"<USER> {clean_text(prompt)}")
    chat_history.append(f"<BOT> {clean_text(final_response)}")

    return final_response


if __name__ == "__main__":
    print("\n" + "=" * 50)
    print("CHATBOT ACTIVE")
    print("=" * 50)

    if DEBUG_MODE:
        print("[DEBUG] GEMINI_API_KEY loaded:", bool(GEMINI_API_KEY))
        print(f"[DEBUG] Retrieval API threshold = {RETRIEVAL_API_THRESHOLD}")
        print(f"[DEBUG] Users with notes loaded = {len(notes_by_user)}")
        print("[DEBUG] Standalone test mode active")

    while True:
        user_email = input("\nUser email: ").strip().lower()
        user_input = input("You: ").strip()

        if user_input.lower() in ["exit", "quit"]:
            print("See you later.")
            break

        try:
            reply = generate_response(user_input, user_email)
            print(f"Chatbot: {reply}")
        except Exception as e:
            print(f"Error Occurred: {e}")

import os
import re
import csv
import torch
import torch.nn as nn
from torch.nn import functional as F

# =========================
# 1. AYARLAR
# =========================
device = "cuda" if torch.cuda.is_available() else "cpu"

batch_size = 32
block_size = 128
n_embd = 256
n_head = 8
n_layer = 6
dropout = 0.2
learning_rate = 3e-4
max_iters = 6000
eval_interval = 300

data_path = r"C:\Users\aslan\OneDrive\Belgeler\ceng v2\mentalhealth_cleaned_final.csv"
checkpoint_path = r"C:\Users\aslan\OneDrive\Belgeler\ceng v2\mental_health_bot_v3.pth"

SPECIAL_TOKENS = ["<PAD>", "<UNK>", "<USER>", "<BOT>", "<SEP>", "<EOS>"]


# =========================
# 2. VERİ HAZIRLAMA
# =========================
def clean_text(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"\s+", " ", s)
    return s


def tokenize(text: str):
    return re.findall(r"<[^>]+>|[\w']+|[.,!?;:]", text.lower())


def load_and_format_data(file_path: str):
    records = []

    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Dosya bulunamadı: {file_path}")

    with open(file_path, "r", encoding="utf-8", errors="ignore", newline="") as f:
        reader = csv.reader(f)
        next(reader, None)  # header atla

        for row in reader:
            if len(row) < 3:
                continue

            q = clean_text(row[1])
            a = clean_text(row[2])

            if not q or not a:
                continue

            sample = f"<USER> {q} <SEP> <BOT> {a} <EOS>"
            records.append((q, a, sample))

    if not records:
        raise ValueError("Veri setinden geçerli kayıt okunamadı.")

    return records


records = load_and_format_data(data_path)
all_text = " ".join(sample for _, _, sample in records)

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


def decode(token_ids):
    return " ".join([itos.get(i, "<UNK>") for i in token_ids])


encoded_samples = [torch.tensor(encode(sample), dtype=torch.long) for _, _, sample in records]

# train / val split
n = int(0.9 * len(encoded_samples))
train_samples = encoded_samples[:n]
val_samples = encoded_samples[n:] if len(encoded_samples[n:]) > 0 else encoded_samples[:max(1, len(encoded_samples)//10)]


def get_batch(split="train"):
    source = train_samples if split == "train" else val_samples
    batch = []

    while len(batch) < batch_size:
        seq = source[torch.randint(0, len(source), (1,)).item()]

        if len(seq) < 2:
            continue

        target_len = block_size + 1

        if len(seq) < target_len:
            pad_len = target_len - len(seq)
            seq = torch.cat([seq, torch.full((pad_len,), PAD_ID, dtype=torch.long)])
        else:
            start = torch.randint(0, len(seq) - target_len + 1, (1,)).item()
            seq = seq[start:start + target_len]

        batch.append(seq)

    batch = torch.stack(batch)
    x = batch[:, :-1]
    y = batch[:, 1:]
    return x.to(device), y.to(device)


@torch.no_grad()
def estimate_loss():
    out = {}
    model.eval()

    for split in ["train", "val"]:
        losses = []
        for _ in range(20):
            xb, yb = get_batch(split)
            _, loss = model(xb, yb)
            losses.append(loss.item())
        out[split] = sum(losses) / len(losses)

    model.train()
    return out


# =========================
# 3. MODEL
# =========================
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

        loss = None
        if targets is not None:
            loss = F.cross_entropy(
                logits.reshape(-1, vocab_size),
                targets.reshape(-1),
                ignore_index=PAD_ID
            )

        return logits, loss


model = ChatBot(vocab_size).to(device)
optimizer = torch.optim.AdamW(model.parameters(), lr=learning_rate)


# =========================
# 4. CHECKPOINT RESUME
# =========================
start_iter = 0

if os.path.exists(checkpoint_path):
    print(f"---> Checkpoint bulundu: {checkpoint_path}")
    checkpoint = torch.load(checkpoint_path, map_location=device)

    try:
        if checkpoint.get("vocab") == vocab:
            model.load_state_dict(checkpoint["model_state_dict"])
            optimizer.load_state_dict(checkpoint["optimizer_state_dict"])
            start_iter = checkpoint.get("iter", 0)
            print(f"---> Eğitim kaldığı yerden devam ediyor. Başlangıç iterasyonu: {start_iter}")
        else:
            print("---> Vocab değişmiş. Eğitim sıfırdan başlayacak.")
    except Exception as e:
        print(f"---> Checkpoint yüklenemedi, sıfırdan başlanıyor. Sebep: {e}")


# =========================
# 5. EĞİTİM
# =========================
print("Model eğitiliyor...")

model.train()
for i in range(start_iter, max_iters):
    xb, yb = get_batch("train")
    logits, loss = model(xb, yb)

    optimizer.zero_grad(set_to_none=True)
    loss.backward()
    torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
    optimizer.step()

    if i % eval_interval == 0 or i == max_iters - 1:
        losses = estimate_loss()
        print(f"Adım {i}: train loss={losses['train']:.4f}, val loss={losses['val']:.4f}")

        torch.save(
            {
                "model_state_dict": model.state_dict(),
                "optimizer_state_dict": optimizer.state_dict(),
                "stoi": stoi,
                "itos": itos,
                "vocab": vocab,
                "vocab_size": vocab_size,
                "iter": i,
                "config": {
                    "block_size": block_size,
                    "n_embd": n_embd,
                    "n_head": n_head,
                    "n_layer": n_layer,
                    "dropout": dropout,
                },
            },
            checkpoint_path,
        )

print("\nEğitim tamamlandı.")
print(f"Model kaydedildi: {checkpoint_path}")
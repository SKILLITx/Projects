# Running the Legal RAG System

A complete, step-by-step guide from a fresh machine to a working review.
Written for **Windows** (your setup); macOS and Linux differences are noted inline.

You will run **two processes side by side**: the FastAPI backend on port 8000 and the
Vite dev server on port 5173. Keep two terminals open.

---

## Part 0 — Prerequisites

| Requirement | Version | Check with | Where to get it |
|---|---|---|---|
| Python | 3.11 or newer | `python --version` | [python.org/downloads](https://www.python.org/downloads/) — tick **"Add Python to PATH"** during install |
| Node.js | 20 or newer | `node --version` | [nodejs.org](https://nodejs.org/) — the LTS build |
| Groq API key | — | — | [console.groq.com/keys](https://console.groq.com/keys) — free, no card |

### Optional but recommended: OCR toolchain

Without these, scanned or photographed PDFs produce **no text at all** and the review
will fail with a clear message. Text-based PDFs work fine without them.

**Tesseract OCR** — reads text out of page images.

1. Download the Windows installer from
   [github.com/UB-Mannheim/tesseract/wiki](https://github.com/UB-Mannheim/tesseract/wiki)
2. During installation, expand **"Additional language data"** and tick **Urdu (`urd`)**.
   This is the step people skip, and it is the one that matters for Pakistani revenue
   records.
3. Install to the default path `C:\Program Files\Tesseract-OCR\` — the system finds it
   there automatically.

**Poppler** — turns PDF pages into images for Tesseract to read.

1. Download the latest release from
   [github.com/oschwartz10612/poppler-windows/releases](https://github.com/oschwartz10612/poppler-windows/releases)
2. Extract to e.g. `C:\poppler`
3. Add `C:\poppler\Library\bin` to your **PATH**:
   Start → "Edit the system environment variables" → Environment Variables →
   select **Path** under *User variables* → New → paste the path → OK.
4. **Close and reopen your terminal** — PATH changes do not apply to already-open windows.

> *macOS:* `brew install tesseract tesseract-lang poppler`
> *Ubuntu/Debian:* `sudo apt install tesseract-ocr tesseract-ocr-urd poppler-utils`

---

## Part 1 — Backend setup

Open a terminal (PowerShell or Command Prompt) and navigate to the backend:

```powershell
cd "C:\Users\Ghafoor\Downloads\skillSYNC Project\legal-rag-system\backendd"
```

### 1.1 Create and activate the virtual environment

Any existing `backendd\venv` holds packages from the previous build, so start fresh.

> ### ⚠ Read this first if you are on Windows
>
> **Put the virtual environment outside the project folder.** Your project lives at
> `C:\Users\Ghafoor\Downloads\skillSYNC Project\legal-rag-system\...`, which is 94
> characters deep before a package name is even added. PyTorch ships license files nested
> about fifteen directories deep, and the resulting path lands at **261 characters** —
> one over the Windows 260-character `MAX_PATH` limit. `pip` then fails with
> `[WinError 206] The filename or extension is too long`, roughly 70% of the way through
> the install.
>
> Putting the venv at `C:\venvs\legalrag` cuts 58 characters off every package path and
> leaves 57 to spare. Nothing else in the project needs to move.

```powershell
python -m venv C:\venvs\legalrag
C:\venvs\legalrag\Scripts\activate
```

If a broken `backendd\venv` already exists from a failed attempt, remove it first. Plain
`rmdir` can itself fail on those over-long paths, so use the `robocopy` mirror trick,
which handles them:

```powershell
mkdir C:\emptydir
robocopy C:\emptydir "C:\Users\Ghafoor\Downloads\skillSYNC Project\legal-rag-system\backendd\venv" /purge /nfl /ndl /njh /njs
rmdir /s /q "C:\Users\Ghafoor\Downloads\skillSYNC Project\legal-rag-system\backendd\venv"
rmdir C:\emptydir
```

> *Prefer to keep the venv inside the project?* Then enable long-path support once, in an
> **Administrator** PowerShell, and reboot:
> ```powershell
> New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
>   -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
> ```
> That removes the limit permanently for every tool on the machine, not just this project.
>
> *PowerShell activation blocked?* Run
> `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first.
> *macOS/Linux:* no path limit — `python3 -m venv venv && source venv/bin/activate`

Your prompt should now start with `(venv)`. **Every backend command below assumes the
venv is active.** To reactivate it in a new terminal, run
`C:\venvs\legalrag\Scripts\activate` again.

### 1.2 Install dependencies

Install the CPU-only build of PyTorch **first**. The default wheel bundles CUDA and is
roughly 2.5 GB; the CPU build is about 200 MB, and this system runs embeddings on CPU
anyway. Installing it up front means the next command sees the requirement already
satisfied and skips the large download entirely.

```powershell
python -m pip install --upgrade pip
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements.txt
```

Expect **5–15 minutes**. The bulk is `sentence-transformers` and the LlamaIndex stack.

> If you still hit `[WinError 206]`, the venv is not at a short path — check that your
> prompt shows `(legalrag)` and that `pip -V` reports `C:\venvs\legalrag\...`.

### 1.3 Add your Groq API key

Open `backendd\.env` in a text editor. It should contain:

```ini
GROQ_API_KEY=gsk_your_actual_key_here
```

If the file is missing, copy the template and edit it:

```powershell
copy .env.example .env
notepad .env
```

Everything else in `.env` has a sensible default. Leave `API_KEY=` **empty** for local
work — that keeps authentication off so no header is needed. Set it to any string when
you want the API locked down.

### 1.4 Confirm the statute corpus is present

```powershell
dir data\legal_corpus
```

You should see four PDFs: `constitution.pdf`, `property-act.pdf`, `reg-act.pdf`,
`stamp-act.pdf`. They are already indexed (2,510 vectors in `chroma_db`), so the first
review will not need to rebuild them.

To extend the system's statutory reach, drop more Act PDFs into this folder — the index
detects the change and rebuilds itself once, automatically.

### 1.5 Run the pre-flight check

```powershell
python verify_setup.py
```

This reports honestly on configuration, dependencies, the OCR toolchain (including which
language packs are actually installed), storage, the corpus and checklist assembly. Fix
anything it marks **FAIL** before continuing. `WARN` items are optional — the system runs
without them, with reduced capability.

Expected on a correct setup:

```
[PASS] Groq API key present
[PASS] City profiles          4 cities: islamabad, karachi, lahore, rawalpindi
[PASS] Tesseract binary
[PASS] Poppler (pdftoppm)
[PASS] Urdu language pack
[PASS] Corpus indexed         2510 vectors, chunk_size=512, overlap=64
[PASS] Red-flag rules         9 deterministic rules
All essential checks passed — the system is ready.
```

### 1.6 Start the backend

```powershell
uvicorn main:app --reload
```

Leave this running. You should see:

```
Legal RAG System v2.0.0 starting
Authentication: disabled (open)
Language model: openai/gpt-oss-120b
Uvicorn running on http://127.0.0.1:8000
```

**Verify it:** open <http://localhost:8000/api/health> in a browser. You want
`"status": "healthy"`. Interactive API documentation is at <http://localhost:8000/docs>.

---

## Part 2 — Frontend setup

Open a **second terminal** — leave the backend running in the first.

```powershell
cd "C:\Users\Ghafoor\Downloads\skillSYNC Project\legal-rag-system\frontendd"
npm install
npm run dev
```

Then open <http://localhost:5173>.

You do not need a `.env` file for the frontend — it defaults to `http://localhost:8000`.
Create one only if you change the backend port or enable `API_KEY`:

```powershell
copy .env.example .env
```

```ini
VITE_API_URL=http://localhost:8000
VITE_API_KEY=          # must match backendd/.env if you set one there
```

---

## Part 3 — Running a review

1. **Choose a firm profile.** Pick "Josh and Mak International" or "Mumtaz & Brohi" to
   auto-fill the letterhead, or enter your own. Leave the name blank for an unbranded memo.
2. **Set the review parameters.** Transaction type (property / loan / acquisition), city,
   and optionally a housing society. The city genuinely matters — it changes which
   authority the checklist asks about (CDA for Islamabad, SBCA for Karachi, and so on).
3. **Add PDFs.** Drag and drop, or click to browse. Up to 10 files, 50 MB each, 150 MB
   total. Invalid files are rejected before upload with a reason.
4. **Click "Run due diligence review."** The stage indicator moves through
   Extract → Index → Analyse → Generate → Done. Typically **2–5 minutes** depending on
   bundle size and how many pages need OCR.
   You can safely refresh or close the tab — the review continues on the server and the
   page reattaches to it when you return.
5. **Read the findings.** They arrive sorted by risk with HIGH items already expanded.
   Filter by risk level, topic or free text. Red flags appear at the top.
6. **Ask follow-up questions** on the "Ask a question" tab. Answers draw on your documents
   *and* the statutes together, and accumulate as a history so you can compare them.
7. **Download the memorandum** in Word or PDF from the "Download memo" tab.
8. **"Start a new review"** erases the session, its documents, its vectors and its
   memoranda from the server immediately.

---

## Part 4 — Running the tests

```powershell
cd "C:\Users\Ghafoor\Downloads\skillSYNC Project\legal-rag-system\backendd"
C:\venvs\legalrag\Scripts\activate
pip install -r requirements-dev.txt
pytest
```

Expect **303 passed** in under five seconds. The suite needs no API key, no GPU and no
network — every model-dependent path is stubbed.

With a coverage report:

```powershell
pytest --cov=core --cov-report=term-missing
```

Frontend checks:

```powershell
cd ..\frontendd
npm run lint      # expect no output and exit 0
npm run build     # expect "✓ built in ..."
```

---

## Part 5 — Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `[WinError 206] The filename or extension is too long` during `pip install` | Windows 260-character `MAX_PATH`. Your project path is 94 characters deep; PyTorch's nested license files push the total to 261 | Create the venv at a short path — `python -m venv C:\venvs\legalrag` — or enable `LongPathsEnabled` in the registry and reboot. See the warning box in Part 1.1 |
| `rmdir /s /q venv` fails with "path too long" | Same limit applies to deletion | Use the `robocopy C:\emptydir <venv> /purge` mirror trick in Part 1.1 |
| PyTorch download is enormous (multiple GB) | Default wheel bundles CUDA | `pip install torch --index-url https://download.pytorch.org/whl/cpu` **before** installing requirements |
| `'uvicorn' is not recognized` | venv not active | Run `C:\venvs\legalrag\Scripts\activate` — your prompt should show `(legalrag)` |
| `ModuleNotFoundError: No module named 'fastapi'` | Dependencies not installed, or wrong venv | Confirm `pip -V` points at your venv, then re-run `pip install -r requirements.txt` |
| Frontend shows *"Could not reach the review server"* | Backend not running, or on a different port | Check terminal 1; confirm <http://localhost:8000/api/health> responds |
| Review fails: *"No readable text could be extracted"* | Scanned PDFs with no OCR toolchain | Install Tesseract and Poppler (Part 0), reopen the terminal, re-run `verify_setup.py` |
| `verify_setup.py` says Poppler not found, but you installed it | PATH change not picked up | Close **all** terminals and open a new one |
| Urdu pages come out as gibberish | Urdu language pack missing | Re-run the Tesseract installer and tick **Urdu** under additional language data |
| Review fails: *"GROQ_API_KEY is not set"* | Key missing or file misnamed | Confirm the file is `backendd\.env` — not `.env.txt`, which Notepad adds silently |
| Review is very slow | Free-tier rate limit | Expected. Raise `TOKENS_PER_MINUTE` in `.env` on a paid plan, or lower `CHECKLIST_WORKERS` to 1 if you see repeated 429s |
| Port 8000 or 5173 already in use | Another process has it | `uvicorn main:app --reload --port 8001`, and set `VITE_API_URL` to match |
| First review takes an extra minute | Corpus index being built | One-time only; subsequent reviews reload it instantly |
| Everything worked, then stopped after editing `.env` | Backend caches settings at start-up | Restart uvicorn (Ctrl-C, then re-run) |

### Reading the logs

The backend terminal is the first place to look. Each review logs its stage transitions
and a summary line:

```
Session a3f19c2b complete in 143.2s — 3 HIGH, 6 MEDIUM, 7 LOW, 2 red flag(s)
```

An unhandled error prints a correlation id that also appears in the client's error
message, so you can match a user report to a specific log entry.

---

## Part 6 — Locking it down

For anything beyond local demonstration:

1. **Set an API key.** In `backendd\.env` set `API_KEY=some-long-random-string`, and put
   the same value in `frontendd\.env` as `VITE_API_KEY`. Restart both. Every
   session-scoped route now requires it.
2. **Restrict origins.** Set `CORS_ORIGINS` to exactly the domains that should reach the
   API.
3. **Terminate TLS.** Run behind a reverse proxy (nginx, Caddy) with HTTPS. Uploaded
   documents are privileged material and must not travel in clear text.
4. **Shorten retention.** Lower `SESSION_TTL_HOURS` to match the firm's retention policy.
   The cleanup worker purges documents, vectors and memoranda on that schedule.
5. **Serve the built frontend.** `npm run build` produces `dist/`; serve it as static
   files rather than running the dev server.

---

## Quick reference

```powershell
# Terminal 1 — backend
cd "C:\Users\Ghafoor\Downloads\skillSYNC Project\legal-rag-system\backendd"
C:\venvs\legalrag\Scripts\activate
uvicorn main:app --reload

# Terminal 2 — frontend
cd "C:\Users\Ghafoor\Downloads\skillSYNC Project\legal-rag-system\frontendd"
npm run dev

# Browser
http://localhost:5173        the application
http://localhost:8000/docs   interactive API documentation
http://localhost:8000/api/health   dependency status
```

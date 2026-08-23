# Legal RAG System — Day 4 Demo Script
**Target:** Josh and Mak International / Mumtaz & Brohi  
**Duration:** 30 minutes  
**Format:** In-person or video call

---

## Opening (2 minutes)

"Thank you for your time. We are AI engineering interns at skillSYNC who have built
a legal technology system specifically for Pakistani law firms. It automates first-pass
property due diligence review and produces a structured memorandum in under 5 minutes.
We would like to show you a live demonstration."

---

## Problem Statement (3 minutes)

- "How long does a typical property due diligence review take your team currently?"
- [Listen — expected answer: 3–7 days]
- "Your clients expect turnaround in 48 hours for competitive transactions."
- "Our system compresses that to same-day delivery."

---

## Live Demo (20 minutes)

### Step 1 — Setup (1 min)
- Open browser to localhost:5173
- Select: Transaction Type = Property
- Select: City = Islamabad (or Rawalpindi)
- Select firm profile: Josh and Mak International (or Mumtaz & Brohi)
- Firm details auto-populate

### Step 2 — Upload (1 min)
- Upload a sample 5–10 page property PDF bundle
- Say: "In production this would be your 30–50 page document bundle"
- Click: Run Due Diligence Review

### Step 3 — Processing (3–5 min)
- Show the step indicator (Extract → Index → Analyse → Generate → Done)
- Explain each stage:
  - "It is extracting text from your documents"
  - "Now it is building a vector index — this means it understands the meaning of every clause"
  - "Now it is running 15 due diligence questions against your documents AND Pakistani statutes simultaneously"
  - "It is generating the structured review memo"

### Step 4 — Results (10 min)
- Show Review Findings tab
  - Point to risk summary: "4 HIGH, 7 MEDIUM, 4 LOW — at a glance"
  - Show a red flag: "It detected undisclosed litigation — this is a HIGH risk flag"
  - Scroll through findings: "Every finding cites the specific statute and constitutional article"
  - Point to reasoning: "This is not just a yes/no — it shows legal reasoning a junior associate would write"

- Show Ask a Question tab
  - Type: "Does this agreement comply with Section 54 of the Transfer of Property Act?"
  - Show response: "You can ask anything. It searches both your documents and our Pakistani statute database simultaneously"

- Show Download Memo tab
  - Download the Word document
  - Open it: "Your firm's letterhead is on it. This is the deliverable your associate would have spent 5 days producing."

---

## Key Differentiators to Mention (3 min)

1. "This knows Pakistani law — Constitution, Transfer of Property Act, Registration Act, LDA bye-laws — not just generic AI"
2. "It handles Urdu content in documents — the embedding model is trained on Urdu"
3. "It detects inherited property and triggers additional succession compliance questions automatically"
4. "Every finding cites the specific constitutional article, not just a statute"
5. "Your letterhead on every memo — branded output"

---

## Pricing Discussion (2 min)

| Tier | Price | Reviews |
|---|---|---|
| Starter | PKR 15,000/month | 25 reviews |
| Professional | PKR 35,000/month | 100 reviews |
| Enterprise | PKR 70,000/month | Unlimited |

"At PKR 35,000 per month, you replace approximately PKR 500,000 per month in senior associate time.
That is a 14× return in month one."

---

## Closing Questions to Ask

1. "Which transaction type do you review most frequently — property, loan, or acquisition?"
2. "What does your current review memo look like? We can match your format."
3. "How many reviews does your firm handle per month?"
4. "What would be most important for you to see in a second demo?"

---

## Objection Responses

**"Is this data secure?"**
"The system runs entirely locally on your machine — no documents are sent to any cloud server. 
The only external call is to the LLM API for text generation, not for document storage."

**"What if the AI makes a mistake?"**
"The memo is always reviewed by your lawyer before being finalised. It is a first draft, 
not a final opinion. Every finding shows the reasoning so your associate can verify it 
in under 2 hours instead of writing it from scratch in 5 days."

**"What about Urdu documents?"**
"The embedding model natively handles mixed Urdu-English. We can demonstrate this with 
an Urdu document if you have one available."
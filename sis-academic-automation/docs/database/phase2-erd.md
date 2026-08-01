# Phase 2 Entity-Relationship Diagrams

The overview shows the domain flow. The detailed Mermaid source contains every detected foreign-key relationship from the Phase 2 migrations.

```mermaid
flowchart LR
  INST[Institution & Configuration] --> AUTH[Identity & Authorization]
  INST --> CURR[Curriculum & Scheduling]
  AUTH --> STUD[Students & Documents]
  CURR --> ENR[Enrollment]
  STUD --> ENR
  ENR --> MARKS[Marks & Results]
  MARKS --> TRANS[Transcripts]
  ENR --> REPORT[Reporting & HEC]
  TRANS --> OPS[Notifications & Operations]
  REPORT --> OPS
  AUTH --> AUDIT[Audit]
  OPS --> AUDIT
```

Detailed source: `database/schema/phase2-erd.mmd`.

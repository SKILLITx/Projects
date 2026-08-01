# Data-Flow Diagrams

The diagrams use Mermaid syntax and can be rendered by GitHub, Mermaid Live Editor or compatible Markdown tools.

## 1. System context

```mermaid
flowchart LR
    S[Students] --> PF[Public Google Forms]
    T[Teachers] --> TF[Restricted Teacher Forms]
    A[Registrar / Campus Admin / Super Admin] --> P[Minimal Staff Portal]

    PF --> RS[Linked Response Sheets]
    TF --> RS
    RS --> N[n8n 2.4.0 on Windows]
    P -->|Bearer access token through ngrok| N

    N -->|Public RPC wrappers| DB[(Supabase PostgreSQL)]
    DB --> OUT[(Notification Outbox)]
    OUT --> ND[Notification Dispatcher]
    ND --> GM[Gmail]

    N --> GD[Google Docs]
    N --> DR[Google Drive]
    N --> GS[Google Sheets Dashboards / Reports]

    N --> EH[Global Error Workflow]
    EH --> OPS[(Ops Incidents)]
```

## 2. Database schema separation

```mermaid
flowchart TB
    N[n8n]
    PUB[public schema\nRLS tables + stable RPC wrappers]
    APP[app schema\ntransactional business logic]
    AUD[audit schema\nimmutable history]
    OPS[ops schema\nruns, outbox, incidents, deliveries]
    REP[reporting schema\ninternal reporting models]

    N --> PUB
    PUB --> APP
    APP --> PUB
    APP --> AUD
    APP --> OPS
    APP --> REP

    N -. no direct PostgREST access .-> APP
    N -. no direct PostgREST access .-> AUD
    N -. no direct PostgREST access .-> OPS
    N -. no direct PostgREST access .-> REP
```

## 3. Public student intake

```mermaid
sequenceDiagram
    participant Student
    participant Form as Google Form
    participant Sheet as Response Sheet
    participant N as n8n
    participant RPC as public.rpc_submit_student_profile
    participant DB as PostgreSQL
    participant Outbox

    Student->>Form: Submit profile data
    Form->>Sheet: Append response row
    Sheet->>N: Trigger or idempotent polling
    N->>N: Normalize, sanitize, create correlation ID
    N->>RPC: Standard request envelope
    RPC->>DB: Validate and transact
    DB->>Outbox: Insert acknowledgment event
    DB-->>RPC: One JSON result
    RPC-->>N: Stable success/failure object
    N->>Sheet: Record processed state
```

## 4. Authenticated staff operation

```mermaid
sequenceDiagram
    participant Staff
    participant Portal
    participant Auth as Supabase Auth
    participant N as n8n Webhook
    participant RPC as Authenticated RPC
    participant DB as PostgreSQL

    Staff->>Portal: Sign in
    Portal->>Auth: Authenticate with anon client
    Auth-->>Portal: Access token
    Portal->>N: Request + Bearer token
    N->>Auth: Validate token / resolve user
    Auth-->>N: Authenticated user
    N->>RPC: Call using user token
    RPC->>DB: auth.uid(), role, institution and campus checks
    DB-->>RPC: Transactional JSON result
    RPC-->>N: Stable response
    N-->>Portal: Sanitized response
```

## 5. Enrollment transaction

```mermaid
flowchart TD
    R[Enrollment request] --> I[Idempotency reservation]
    I --> A{Student active?}
    A -- No --> REJ[Reject]
    A -- Yes --> W{Period open and offering valid?}
    W -- No --> REJ
    W -- Yes --> P{Prerequisites and documents valid?}
    P -- No --> REJ
    P -- Yes --> L{Load and timetable valid?}
    L -- No --> REJ
    L -- Yes --> S[Lock candidate sections]
    S --> C{Capacity available?}
    C -- Preferred --> ALLOC[Allocate preferred section]
    C -- Fallback --> ALLOC2[Allocate valid fallback]
    C -- None, waitlist policy --> WAIT[Create waitlist entry]
    C -- None, manual policy --> MAN[Manual review]
    C -- None, reject policy --> REJ
    ALLOC --> H[Decision history + outbox]
    ALLOC2 --> H
    WAIT --> H
    MAN --> H
    REJ --> H
    H --> J[One JSON result]
```

## 6. Results and transcript flow

```mermaid
flowchart LR
    M[Teacher marks batch] --> V[Validate and finalize]
    V --> AP[Registrar approval]
    AP --> CALC[PostgreSQL grade/GPA calculation]
    CALC --> PUB[Publish results]
    PUB --> TR[Transcript request]
    TR --> MODEL[Complete transcript model]
    MODEL --> DOC[Google Docs template]
    DOC --> PDF[PDF export]
    PDF --> DRIVE[Drive storage]
    DRIVE --> OUT[Delivery outbox / record]
    OUT --> MAIL[Gmail]
```

## 7. Notification outbox

```mermaid
stateDiagram-v2
    [*] --> pending
    pending --> claimed: dispatcher atomically claims
    claimed --> delivered: Gmail accepted and record saved
    claimed --> retry_wait: temporary error
    retry_wait --> claimed: next bounded attempt
    claimed --> dead_letter: permanent error or attempts exhausted
    delivered --> [*]
    dead_letter --> [*]
```

## 8. Incident handling

```mermaid
flowchart LR
    E[Workflow failure] --> F[Sanitized fingerprint]
    F --> D{Existing unresolved incident?}
    D -- Yes --> EV[Append incident event]
    D -- No --> NEW[Create root incident]
    EV --> A{Alert already requested?}
    NEW --> A
    A -- No --> O[Create one alert outbox record]
    A -- Yes --> DONE[Return incident]
    O --> DONE
```

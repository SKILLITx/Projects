(() => {
  "use strict";

  const config = window.SIS_PORTAL_CONFIG || null;
  const state = {
    client: null,
    session: null,
    user: null,
    staffProfile: null,
    roles: [],
    campusAssignments: [],
    institutions: [],
    campuses: [],
    dashboardTerms: []
  };

  const byId = (id) => document.getElementById(id);
  const setText = (id, value) => { byId(id).textContent = value == null ? "" : String(value); };
  const show = (id, visible) => { byId(id).hidden = !visible; };
  const uuid = () => crypto.randomUUID();
  const uuidShape = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

  function validateConfig() {
    if (!config) return "config.local.js was not loaded.";
    if (!config.supabaseUrl || !/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(config.supabaseUrl)) {
      return "The Supabase URL is missing or invalid.";
    }
    if (!config.supabaseAnonKey || config.supabaseAnonKey.includes("REPLACE_LOCALLY")) {
      return "The Supabase anon key has not been configured.";
    }
    if (String(config.supabaseAnonKey).toLowerCase().includes("service_role")) {
      return "A service-role key must never be used in browser code.";
    }
    if (!window.supabase || !window.supabase.createClient) return "Supabase JavaScript client failed to load.";
    return null;
  }

  async function init() {
    const configError = validateConfig();
    if (configError) {
      show("configuration-panel", true);
      show("login-panel", false);
      setText("configuration-error", configError);
      return;
    }

    state.client = window.supabase.createClient(config.supabaseUrl, config.supabaseAnonKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    });

    bindEvents();
    const { data, error } = await state.client.auth.getSession();
    if (error) throw error;
    await applySession(data.session);

    state.client.auth.onAuthStateChange((_event, session) => {
      window.setTimeout(() => applySession(session).catch(handleFatal), 0);
    });
  }

  function bindEvents() {
    byId("login-form").addEventListener("submit", login);
    byId("sign-out-button").addEventListener("click", () => state.client.auth.signOut());
    byId("institution-select").addEventListener("change", async () => {
      updateCampusOptions();
      resetDashboardTerms();
      clearStudentSearch();
      await refreshDashboard();
    });
    byId("campus-select").addEventListener("change", async () => {
      resetDashboardTerms();
      clearStudentSearch();
      await refreshDashboard();
    });
    byId("dashboard-term-select").addEventListener("change", refreshDashboard);
    byId("refresh-dashboard-button").addEventListener("click", refreshDashboard);
    byId("student-search-form").addEventListener("submit", searchStudents);
    byId("student-search-clear").addEventListener("click", clearStudentSearch);
    byId("enrollment-form").addEventListener("submit", decideEnrollment);
    byId("marks-form").addEventListener("submit", decideMarks);
    byId("correction-form").addEventListener("submit", decideCorrection);
    byId("publication-form").addEventListener("submit", publishResults);
    document.querySelectorAll(".tabs button").forEach((button) => {
      button.addEventListener("click", () => activateView(button.dataset.panel, button));
    });
  }

  async function login(event) {
    event.preventDefault();
    const button = event.submitter;
    button.disabled = true;
    setStatus("login-status", "Signing in…");
    try {
      const { error } = await state.client.auth.signInWithPassword({
        email: byId("login-email").value.trim(),
        password: byId("login-password").value
      });
      if (error) throw error;
      byId("login-form").reset();
      setStatus("login-status", "Signed in.", "success");
    } catch (error) {
      setStatus("login-status", sanitizeError(error), "error");
    } finally {
      button.disabled = false;
    }
  }

  async function applySession(session) {
    state.session = session;
    state.user = session ? session.user : null;
    const authenticated = Boolean(session);

    show("login-panel", !authenticated);
    show("portal-panel", authenticated);
    show("sign-out-button", authenticated);
    setText("session-label", authenticated ? session.user.email : "Signed out");

    if (!authenticated) {
      state.staffProfile = null;
      state.roles = [];
      return;
    }

    await loadAuthorizationContext();
    await refreshDashboard();
  }

  async function loadAuthorizationContext() {
    const userId = state.user.id;
    const profileResult = await state.client
      .from("staff_profiles")
      .select("id,auth_user_id,email,full_name,employee_code,status")
      .eq("auth_user_id", userId)
      .maybeSingle();
    if (profileResult.error) throw profileResult.error;
    if (!profileResult.data || profileResult.data.status !== "active") {
      throw new Error("No active staff profile is linked to this Supabase Auth user.");
    }
    state.staffProfile = profileResult.data;

    const roleResult = await state.client
      .from("role_assignments")
      .select("id,institution_id,role,status,valid_from,valid_to")
      .eq("staff_profile_id", state.staffProfile.id)
      .eq("status", "active");
    if (roleResult.error) throw roleResult.error;
    state.roles = roleResult.data || [];

    const roleIds = state.roles.map((item) => item.id);
    if (roleIds.length) {
      const campusAssignmentResult = await state.client
        .from("campus_assignments")
        .select("id,role_assignment_id,institution_id,campus_id,status,valid_from,valid_to")
        .in("role_assignment_id", roleIds)
        .eq("status", "active");
      if (campusAssignmentResult.error) throw campusAssignmentResult.error;
      state.campusAssignments = campusAssignmentResult.data || [];
    } else {
      state.campusAssignments = [];
    }

    const institutionResult = await state.client
      .from("institutions")
      .select("id,code,name,institution_type,academic_model,timezone,status")
      .eq("status", "active")
      .order("code");
    if (institutionResult.error) throw institutionResult.error;
    state.institutions = institutionResult.data || [];

    const campusResult = await state.client
      .from("campuses")
      .select("id,institution_id,code,name,city,status")
      .eq("status", "active")
      .order("code");
    if (campusResult.error) throw campusResult.error;
    state.campuses = campusResult.data || [];

    renderScope();
    renderReadableSession();
  }

  function renderReadableSession() {
    const roleRows = state.roles.map((role) => {
      const institution = state.institutions.find((item) => item.id === role.institution_id);
      return {
        role: role.role,
        institution: institution ? `${institution.code} — ${institution.name}` : "Global or unavailable"
      };
    });
    const campusRows = state.campusAssignments.map((assignment) => {
      const campus = state.campuses.find((item) => item.id === assignment.campus_id);
      return campus ? `${campus.code} — ${campus.name}` : "Assigned campus";
    });
    setText("session-output", JSON.stringify({
      signed_in_email: state.user.email,
      staff_name: state.staffProfile.full_name,
      employee_code: state.staffProfile.employee_code,
      roles: roleRows,
      campus_assignments: campusRows,
      visible_institutions: state.institutions.map((item) => `${item.code} — ${item.name}`),
      visible_campuses: state.campuses.map((item) => `${item.code} — ${item.name}`)
    }, null, 2));
  }

  function renderScope() {
    setText("staff-name", state.staffProfile.full_name);
    setText("staff-role-summary", state.roles.map((item) => item.role).join(", ") || "No active role");

    const institutionSelect = byId("institution-select");
    institutionSelect.innerHTML = "";
    state.institutions.forEach((institution) => {
      const option = document.createElement("option");
      option.value = institution.id;
      option.textContent = `${institution.code} — ${institution.name}`;
      institutionSelect.append(option);
    });
    updateCampusOptions();
  }

  function updateCampusOptions() {
    const institutionId = byId("institution-select").value;
    const campusSelect = byId("campus-select");
    campusSelect.innerHTML = "";

    const institutionRoles = state.roles.filter((role) => role.institution_id === institutionId);
    const canUseInstitutionScope =
      state.roles.some((role) => role.role === "super_administrator") ||
      institutionRoles.some((role) => role.role === "registrar_admin");

    if (canUseInstitutionScope) {
      const blank = document.createElement("option");
      blank.value = "";
      blank.textContent = "All permitted campuses";
      campusSelect.append(blank);
    }

    const campuses = allowedCampuses(institutionId);
    campuses.forEach((campus) => {
      const option = document.createElement("option");
      option.value = campus.id;
      option.textContent = `${campus.code} — ${campus.name}`;
      campusSelect.append(option);
    });

    if (!canUseInstitutionScope && campuses.length > 0) campusSelect.value = campuses[0].id;
  }

  function allowedCampuses(institutionId) {
    const rolesForInstitution = state.roles.filter((role) => role.institution_id === institutionId);
    const isGlobal = state.roles.some((role) => role.role === "super_administrator");
    const isRegistrar = rolesForInstitution.some((role) => role.role === "registrar_admin");
    if (isGlobal || isRegistrar) return state.campuses.filter((campus) => campus.institution_id === institutionId);

    const allowedIds = new Set(state.campusAssignments
      .filter((item) => item.institution_id === institutionId)
      .map((item) => item.campus_id));
    return state.campuses.filter((campus) => allowedIds.has(campus.id));
  }

  function workflow07Envelope(operation, payload) {
    const correlationId = uuid();
    return {
      operation,
      correlation_id: correlationId,
      idempotency_key: `portal:${operation}:${correlationId}`,
      source: { channel: "staff_portal" },
      context: {
        institution_id: byId("institution-select").value || null,
        campus_id: byId("campus-select").value || null
      },
      requester: { email: state.user.email },
      submitted_at: new Date().toISOString(),
      payload
    };
  }

  function legacyEnvelope(payload = {}, options = {}) {
    return {
      operation: options.operation || "portal.request",
      correlation_id: uuid(),
      idempotency_key: options.idempotent ? `portal:${options.operation}:${uuid()}` : null,
      institution_id: byId("institution-select").value || null,
      campus_id: byId("campus-select").value || null,
      requester: {
        auth_user_id: state.user.id,
        email: state.user.email,
        staff_profile_id: state.staffProfile.id
      },
      submitted_at: new Date().toISOString(),
      source: "staff_portal",
      payload
    };
  }

  async function callWorkflow07(routeName, request) {
    if (!config.n8nBaseUrl) throw new Error("The current n8n public base URL is not configured in config.local.js.");
    if (!state.session?.access_token) throw new Error("The authenticated staff session is unavailable.");

    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), Number(config.requestTimeoutMs || 30000));
    try {
      const response = await fetch(`${config.n8nBaseUrl.replace(/\/$/, "")}/webhook/staff/${routeName}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "authorization": `Bearer ${state.session.access_token}`
        },
        body: JSON.stringify(request),
        signal: controller.signal
      });
      const body = await response.json().catch(() => ({
        success: false,
        error: { code: "HTTP_INVALID_JSON", message: "The workflow returned invalid JSON.", retryable: false }
      }));
      return { status: response.status, body };
    } finally {
      window.clearTimeout(timeout);
    }
  }

  async function callLegacyOperation(rpcName, request) {
    if (config.portalMode === "n8n-authenticated-webhook") {
      const result = await callWorkflow07(rpcName, request);
      if (result.status < 200 || result.status >= 300) throw new Error(result.body?.error?.message || `HTTP ${result.status}`);
      return result.body;
    }
    const { data, error } = await state.client.rpc(rpcName, { p_request: request });
    if (error) throw error;
    return data;
  }

  async function refreshDashboard() {
    if (!state.user) return;
    const button = byId("refresh-dashboard-button");
    button.disabled = true;
    setStatus("dashboard-status", "Refreshing dashboard…", "loading");
    try {
      const request = workflow07Envelope("dashboard.snapshot", {
        term_id: byId("dashboard-term-select").value || null
      });
      const { status, body } = await callWorkflow07("rpc_get_dashboard_snapshot", request);
      renderSupportOutput("dashboard-output", body);
      if (status < 200 || status >= 300 || !body?.success) {
        throw responseError(status, body, "Dashboard refresh failed.");
      }
      const data = body.data || {};
      renderDashboardCards(data.metrics || {});
      renderDashboardTerms(data.available_terms || [], data.scope?.term_id || null);
      renderGradeDistribution(data.grade_distribution || []);
      renderCourseCapacity(data.course_capacity || []);
      renderDashboardScope(data.scope || {});
      const generated = new Date(data.generated_at || Date.now()).toLocaleString();
      setStatus("dashboard-status", `Dashboard updated ${generated}.`, "success");
    } catch (error) {
      renderDashboardCards({});
      renderGradeDistribution([]);
      renderCourseCapacity([]);
      setStatus("dashboard-status", sanitizeError(error), classifyErrorKind(error));
    } finally {
      button.disabled = false;
    }
  }

  function resetDashboardTerms() {
    state.dashboardTerms = [];
    byId("dashboard-term-select").innerHTML = '<option value="">Current active term</option>';
  }

  function renderDashboardTerms(terms, selectedTermId) {
    const select = byId("dashboard-term-select");
    const prior = select.value;
    state.dashboardTerms = Array.isArray(terms) ? terms : [];
    select.innerHTML = '<option value="">Current active term</option>';
    state.dashboardTerms.forEach((term) => {
      const option = document.createElement("option");
      option.value = term.id || term.term_id;
      const termCode = term.code || term.term_code || "TERM";
      const termName = term.name || term.term_name || "Academic term";
      option.textContent = `${termCode} — ${termName}${term.academic_year_code ? ` (${term.academic_year_code})` : ""}`;
      select.append(option);
    });
    const preferred = selectedTermId || prior;
    if (preferred && [...select.options].some((option) => option.value === preferred)) select.value = preferred;
  }

  function renderDashboardScope(scope) {
    const institution = [scope.institution_code, scope.institution_name].filter(Boolean).join(" — ") || "Selected institution";
    const campus = scope.campus_name || "All permitted campuses";
    const term = [scope.term_code, scope.term_name].filter(Boolean).join(" — ") || "No term filter";
    setText("dashboard-scope-label", `${institution} | ${campus} | ${term}`);
  }

  function renderDashboardCards(metrics) {
    const items = [
      ["Students", metrics.students_total],
      ["Active students", metrics.students_active],
      ["Active enrollments", metrics.active_enrollments],
      ["Waitlist", metrics.waitlist_count],
      ["Rejected / ineligible", metrics.rejected_or_ineligible_requests],
      ["Marks completion", `${numberOrZero(metrics.marks_completion_percent)}%`],
      ["At risk", metrics.at_risk_students],
      ["Average GPA", numberOrZero(metrics.average_gpa).toFixed(2)],
      ["Average CGPA", numberOrZero(metrics.average_cgpa).toFixed(2)],
      ["Pending transcripts", metrics.pending_transcripts],
      ["Notification backlog", metrics.notification_backlog],
      ["Open incidents", metrics.open_incidents]
    ];
    const container = byId("dashboard-cards");
    container.innerHTML = "";
    items.forEach(([label, value]) => {
      const card = document.createElement("article");
      card.className = "card";
      const span = document.createElement("span");
      span.textContent = label;
      const strong = document.createElement("strong");
      strong.textContent = value == null ? "0" : String(value);
      card.append(span, strong);
      container.append(card);
    });
  }

  function renderGradeDistribution(rows) {
    renderSimpleTable(
      "dashboard-grades",
      ["Letter grade", "Count"],
      rows.map((row) => [row.letter_grade, row.count]),
      "No published grades for this scope."
    );
  }

  function renderCourseCapacity(rows) {
    renderSimpleTable(
      "dashboard-capacity",
      ["Course", "Section", "Capacity", "Enrolled", "Remaining", "Waitlisted"],
      rows.map((row) => [
        `${row.course_code || ""}${row.course_title ? ` — ${row.course_title}` : ""}`,
        row.section_code,
        row.capacity,
        row.enrolled,
        row.remaining,
        row.waitlisted
      ]),
      "No course-capacity data for this scope."
    );
  }

  async function searchStudents(event) {
    event.preventDefault();
    const button = event.submitter;
    button.disabled = true;
    setStatus("student-search-status", "Searching…", "loading");
    try {
      const request = workflow07Envelope("student.search", {
        query: byId("student-search-query").value.trim(),
        search_type: byId("student-search-type").value,
        limit: 25,
        offset: 0
      });
      const { status, body } = await callWorkflow07("rpc_search_students", request);
      renderSupportOutput("student-search-output", body);
      if (status < 200 || status >= 300 || !body?.success) {
        throw responseError(status, body, "Student search failed.");
      }
      const students = body.data?.students || [];
      renderStudents(students);
      setStatus(
        "student-search-status",
        students.length ? `${body.data?.count || students.length} student record(s) found.` : "No students matched this search and scope.",
        students.length ? "success" : ""
      );
    } catch (error) {
      renderStudents([]);
      setStatus("student-search-status", sanitizeError(error), classifyErrorKind(error));
    } finally {
      button.disabled = false;
    }
  }

  function clearStudentSearch() {
    byId("student-search-form").reset();
    byId("student-search-type").value = "auto";
    setText("student-search-status", "");
    setText("student-search-output", "");
    byId("student-results").innerHTML = "";
  }

  function renderStudents(students) {
    const container = byId("student-results");
    container.innerHTML = "";
    if (!students.length) return;
    const rows = students.map((student) => [
      student.student_number,
      student.full_name,
      student.primary_email || "—",
      readableEntity(student.institution),
      readableEntity(student.campus),
      readableEntity(student.program),
      student.student_status || "—",
      student.current_gpa == null ? "—" : Number(student.current_gpa).toFixed(2),
      student.current_cgpa == null ? "—" : Number(student.current_cgpa).toFixed(2),
      student.academic_standing || "—",
      student.at_risk ? "Yes" : "No",
      student.identity_reference_masked || "—"
    ]);
    renderSimpleTable(
      "student-results",
      ["Student number", "Student name", "Email", "Institution", "Campus", "Program", "Status", "GPA", "CGPA", "Standing", "At risk", "Identity"],
      rows,
      "No students matched this search and scope."
    );
  }

  function readableEntity(entity) {
    if (!entity) return "—";
    return [entity.code, entity.name].filter(Boolean).join(" — ") || "—";
  }

  function renderSimpleTable(containerId, headings, rows, emptyMessage) {
    const container = byId(containerId);
    container.innerHTML = "";
    if (!rows.length) {
      const message = document.createElement("p");
      message.className = "muted";
      message.textContent = emptyMessage;
      container.append(message);
      return;
    }
    const table = document.createElement("table");
    const head = document.createElement("thead");
    const headRow = document.createElement("tr");
    headings.forEach((heading) => {
      const cell = document.createElement("th");
      cell.textContent = heading;
      headRow.append(cell);
    });
    head.append(headRow);
    const body = document.createElement("tbody");
    rows.forEach((values) => {
      const row = document.createElement("tr");
      values.forEach((value) => {
        const cell = document.createElement("td");
        cell.textContent = value == null ? "—" : String(value);
        row.append(cell);
      });
      body.append(row);
    });
    table.append(head, body);
    container.append(table);
  }

  function renderSupportOutput(elementId, value) {
    setText(elementId, JSON.stringify(sanitizeDebugValue(value), null, 2));
  }

  function sanitizeDebugValue(value, key = "") {
    if (Array.isArray(value)) return value.map((item) => sanitizeDebugValue(item));
    if (!value || typeof value !== "object") {
      if (typeof value === "string" && uuidShape.test(value) && key !== "correlation_id") return "[internal identifier hidden]";
      return value;
    }
    const output = {};
    Object.entries(value).forEach(([childKey, childValue]) => {
      const normalized = childKey.toLowerCase();
      if (/(access|refresh|authorization|apikey|password|secret|service.?role|token)/.test(normalized)) return;
      if (normalized === "identity_reference" || normalized === "cnic") return;
      if ((normalized === "id" || normalized.endsWith("_id")) && normalized !== "correlation_id") return;
      output[childKey] = sanitizeDebugValue(childValue, normalized);
    });
    return output;
  }

  async function decideEnrollment(event) {
    event.preventDefault();
    await submitDecision(event, "rpc_decide_enrollment", "enrollment-output", {
      enrollment_request_item_id: byId("enrollment-item-id").value.trim(),
      decision: byId("enrollment-decision").value,
      section_id: byId("enrollment-section-id").value.trim() || null,
      reason: byId("enrollment-reason").value.trim() || null
    }, "enrollment.decision");
  }

  async function decideMarks(event) {
    event.preventDefault();
    await submitDecision(event, "rpc_decide_marks_batch", "marks-output", {
      marks_batch_id: byId("marks-batch-id").value.trim(),
      decision: byId("marks-decision").value,
      reason: byId("marks-reason").value.trim() || null
    }, "marks.batch.decision");
  }

  async function decideCorrection(event) {
    event.preventDefault();
    await submitDecision(event, "rpc_decide_mark_correction", "correction-output", {
      correction_request_id: byId("correction-request-id").value.trim(),
      decision: byId("correction-decision").value,
      reason: byId("correction-reason").value.trim() || null
    }, "marks.correction.decision");
  }

  async function publishResults(event) {
    event.preventDefault();
    await submitDecision(event, "rpc_publish_results", "publication-output", {
      course_offering_id: byId("publication-offering-id").value.trim(),
      force_recalculate: byId("publication-force").checked
    }, "results.publish");
  }

  async function submitDecision(event, rpcName, outputId, payload, operation) {
    const button = event.submitter;
    button.disabled = true;
    try {
      const result = await callLegacyOperation(rpcName, legacyEnvelope(payload, { operation, idempotent: true }));
      setText(outputId, JSON.stringify(sanitizeDebugValue(result), null, 2));
    } catch (error) {
      setText(outputId, JSON.stringify({ success: false, error: sanitizeError(error) }, null, 2));
    } finally {
      button.disabled = false;
    }
  }

  function activateView(panelId, button) {
    document.querySelectorAll(".view").forEach((panel) => { panel.hidden = panel.id !== panelId; });
    document.querySelectorAll(".tabs button").forEach((item) => item.classList.toggle("active", item === button));
  }

  function responseError(status, body, fallback) {
    const error = new Error(body?.error?.message || fallback);
    error.httpStatus = status;
    error.code = body?.error?.code || "WORKFLOW_REQUEST_FAILED";
    error.retryable = Boolean(body?.error?.retryable);
    return error;
  }

  function classifyErrorKind(error) {
    if (error?.httpStatus === 401 || error?.httpStatus === 403) return "error authorization";
    if (error?.retryable || error?.httpStatus >= 500 || error?.name === "AbortError") return "error temporary";
    return "error";
  }

  function setStatus(id, message, kind = "") {
    const element = byId(id);
    element.textContent = message;
    element.className = `status ${kind}`.trim();
  }

  function numberOrZero(value) {
    const number = Number(value);
    return Number.isFinite(number) ? number : 0;
  }

  function sanitizeError(error) {
    if (error?.name === "AbortError") return "The request timed out. Retry once the local n8n and ngrok services are healthy.";
    const message = error && error.message ? error.message : String(error);
    return message.replace(/(eyJ[a-zA-Z0-9._-]+)/g, "[token removed]").slice(0, 500);
  }

  function handleFatal(error) {
    console.error(sanitizeError(error));
    show("configuration-panel", true);
    setText("configuration-error", sanitizeError(error));
  }

  init().catch(handleFatal);
})();

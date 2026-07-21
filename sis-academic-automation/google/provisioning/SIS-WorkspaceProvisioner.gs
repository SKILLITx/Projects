/**
 * SIS Phase 3 Google Workspace Provisioner
 *
 * Run provisionPhase3Workspace() once from a new standalone Apps Script project.
 * Run verifyPhase3Assets() after provisioning and copy the returned JSON.
 *
 * The script is idempotent through a Drive-stored asset registry and Script Properties.
 */

const SIS_PHASE3_VERSION = '2026.07.17.1';
const SIS_ROOT_FOLDER_NAME = 'SIS Automation Pilot';
const SIS_FORM_DEFINITIONS = [{"code": "student-profile", "title": "SIS — Student Profile and Admission", "operation": "student.profile.submit", "audience": "student_or_admissions_staff", "collect_email": true, "confirmation": "Your profile submission has been recorded. Keep the response receipt for reference.", "description": "Collects new-student admission information and controlled profile updates. Submission does not guarantee admission.", "fields": [{"key": "institution_code", "title": "Institution code", "type": "list", "required": true, "choices": ["DMU", "DCS"]}, {"key": "campus_code", "title": "Campus code", "type": "list", "required": true, "choices": ["ISB", "FSD", "NORTH", "SOUTH"]}, {"key": "submission_type", "title": "Submission type", "type": "multiple_choice", "required": true, "choices": ["New admission/profile", "Update existing profile"]}, {"key": "student_number", "title": "Student number (leave blank only for a new admission)", "type": "text", "required": false}, {"key": "full_name", "title": "Full legal name", "type": "text", "required": true}, {"key": "date_of_birth", "title": "Date of birth", "type": "date", "required": true}, {"key": "gender", "title": "Gender", "type": "list", "required": false, "choices": ["Female", "Male", "Other", "Prefer not to say"]}, {"key": "primary_email", "title": "Primary email address", "type": "text", "required": true, "validation": "email"}, {"key": "mobile_phone", "title": "Mobile phone number", "type": "text", "required": true}, {"key": "guardian_name", "title": "Guardian name (required for school students)", "type": "text", "required": false}, {"key": "guardian_phone", "title": "Guardian phone (required for school students)", "type": "text", "required": false}, {"key": "identity_reference", "title": "Institution-approved identity reference", "type": "text", "required": false}, {"key": "program_code", "title": "Program or qualification code", "type": "text", "required": true}, {"key": "academic_year_code", "title": "Academic year code", "type": "text", "required": true}, {"key": "admission_term_code", "title": "Admission term code", "type": "text", "required": true}, {"key": "previous_qualification", "title": "Previous qualification or school", "type": "paragraph", "required": false}, {"key": "document_links", "title": "Required document Drive links (one per line)", "type": "paragraph", "required": false}, {"key": "additional_notes", "title": "Additional notes", "type": "paragraph", "required": false}, {"key": "consent", "title": "I confirm that the information is accurate and may be processed for academic administration.", "type": "checkbox", "required": true, "choices": ["I confirm"]}]}, {"code": "enrollment-request", "title": "SIS — Course or Subject Enrollment Request", "operation": "enrollment.submit", "audience": "student", "collect_email": true, "confirmation": "Your enrollment request has been recorded for validation and allocation.", "description": "Supports university course registration and school/Cambridge subject enrollment.", "fields": [{"key": "institution_code", "title": "Institution code", "type": "list", "required": true, "choices": ["DMU", "DCS"]}, {"key": "campus_code", "title": "Campus code", "type": "list", "required": true, "choices": ["ISB", "FSD", "NORTH", "SOUTH"]}, {"key": "student_number", "title": "Student number", "type": "text", "required": true}, {"key": "program_code", "title": "Program or qualification code", "type": "text", "required": true}, {"key": "term_code", "title": "Term or semester code", "type": "text", "required": true}, {"key": "requested_course_codes", "title": "Requested course or subject codes (comma-separated)", "type": "paragraph", "required": true}, {"key": "preferred_section_codes", "title": "Preferred section codes in the same order (optional, comma-separated)", "type": "paragraph", "required": false}, {"key": "allow_fallback", "title": "Allow another valid section when the preferred section is unavailable?", "type": "multiple_choice", "required": true, "choices": ["Yes", "No"]}, {"key": "request_notes", "title": "Enrollment notes", "type": "paragraph", "required": false}, {"key": "consent", "title": "I understand that prerequisites, capacity, timetable, document and load rules will be checked.", "type": "checkbox", "required": true, "choices": ["I confirm"]}]}, {"code": "teacher-marks", "title": "SIS — Teacher Marks Submission", "operation": "marks.batch.submit", "audience": "authorized_teacher", "collect_email": true, "confirmation": "The marks submission has been recorded. Final submissions remain subject to authorization and validation.", "description": "Manual class marks entry for small batches. Use the file-upload form for larger classes.", "fields": [{"key": "institution_code", "title": "Institution code", "type": "list", "required": true, "choices": ["DMU", "DCS"]}, {"key": "campus_code", "title": "Campus code", "type": "list", "required": true, "choices": ["ISB", "FSD", "NORTH", "SOUTH"]}, {"key": "term_code", "title": "Term or semester code", "type": "text", "required": true}, {"key": "course_offering_code", "title": "Course offering code", "type": "text", "required": true}, {"key": "section_code", "title": "Section code", "type": "text", "required": true}, {"key": "assessment_code", "title": "Assessment code", "type": "text", "required": true}, {"key": "submission_state", "title": "Submission state", "type": "multiple_choice", "required": true, "choices": ["Draft", "Finalize after validation"]}, {"key": "marks_lines", "title": "Marks — one line per student: student_number,marks,absent,remarks", "type": "paragraph", "required": true}, {"key": "teacher_notes", "title": "Teacher notes", "type": "paragraph", "required": false}, {"key": "declaration", "title": "I confirm that I am assigned to this class and that these marks are accurate.", "type": "checkbox", "required": true, "choices": ["I confirm"]}]}, {"code": "marks-file-upload", "title": "SIS — Marks CSV or Excel Upload", "operation": "marks.file.submit", "audience": "authorized_teacher", "collect_email": true, "confirmation": "The marks-file submission has been recorded.", "description": "Upload the CSV/XLSX to the designated Uploaded Marks folder, then paste its Drive URL below.", "fields": [{"key": "institution_code", "title": "Institution code", "type": "list", "required": true, "choices": ["DMU", "DCS"]}, {"key": "campus_code", "title": "Campus code", "type": "list", "required": true, "choices": ["ISB", "FSD", "NORTH", "SOUTH"]}, {"key": "term_code", "title": "Term or semester code", "type": "text", "required": true}, {"key": "course_offering_code", "title": "Course offering code", "type": "text", "required": true}, {"key": "section_code", "title": "Section code", "type": "text", "required": true}, {"key": "assessment_code", "title": "Assessment code", "type": "text", "required": true}, {"key": "submission_state", "title": "Submission state", "type": "multiple_choice", "required": true, "choices": ["Draft", "Finalize after validation"]}, {"key": "file_drive_url", "title": "Uploaded CSV or Excel Google Drive URL", "type": "text", "required": true, "validation": "url"}, {"key": "original_file_name", "title": "Original file name", "type": "text", "required": true}, {"key": "file_notes", "title": "File notes", "type": "paragraph", "required": false}, {"key": "declaration", "title": "I confirm that I am authorized to submit this class file.", "type": "checkbox", "required": true, "choices": ["I confirm"]}]}, {"code": "mark-correction", "title": "SIS — Mark Correction Request", "operation": "marks.correction.request", "audience": "authorized_teacher", "collect_email": true, "confirmation": "The correction request has been recorded for review.", "description": "Requests a controlled correction after marks finalization or approval.", "fields": [{"key": "institution_code", "title": "Institution code", "type": "list", "required": true, "choices": ["DMU", "DCS"]}, {"key": "campus_code", "title": "Campus code", "type": "list", "required": true, "choices": ["ISB", "FSD", "NORTH", "SOUTH"]}, {"key": "marks_batch_id", "title": "Marks batch ID", "type": "text", "required": true}, {"key": "student_mark_id", "title": "Student mark ID", "type": "text", "required": true}, {"key": "student_number", "title": "Student number", "type": "text", "required": true}, {"key": "assessment_code", "title": "Assessment code", "type": "text", "required": true}, {"key": "current_marks", "title": "Current marks", "type": "text", "required": true}, {"key": "proposed_marks", "title": "Proposed corrected marks", "type": "text", "required": true}, {"key": "reason", "title": "Detailed reason for correction", "type": "paragraph", "required": true}, {"key": "evidence_drive_url", "title": "Supporting evidence Drive URL (optional)", "type": "text", "required": false, "validation": "url"}, {"key": "declaration", "title": "I confirm that this request is accurate and auditable.", "type": "checkbox", "required": true, "choices": ["I confirm"]}]}, {"code": "transcript-request", "title": "SIS — Transcript Request", "operation": "transcript.request", "audience": "student_or_authorized_staff", "collect_email": true, "confirmation": "Your transcript request has been recorded. Delivery occurs only after identity and record checks.", "description": "Requests an official academic transcript for an approved recipient.", "fields": [{"key": "institution_code", "title": "Institution code", "type": "list", "required": true, "choices": ["DMU", "DCS"]}, {"key": "campus_code", "title": "Campus code", "type": "list", "required": true, "choices": ["ISB", "FSD", "NORTH", "SOUTH"]}, {"key": "student_number", "title": "Student number", "type": "text", "required": true}, {"key": "requester_relationship", "title": "Requester relationship", "type": "multiple_choice", "required": true, "choices": ["Student", "Parent/guardian", "Authorized institutional staff"]}, {"key": "student_date_of_birth", "title": "Student date of birth", "type": "date", "required": true}, {"key": "recipient_email", "title": "Approved recipient email", "type": "text", "required": true, "validation": "email"}, {"key": "purpose", "title": "Purpose of transcript", "type": "list", "required": true, "choices": ["Personal record", "Admission", "Employment", "Scholarship", "HEC/official verification", "Other"]}, {"key": "purpose_details", "title": "Purpose details", "type": "paragraph", "required": false}, {"key": "delivery_preference", "title": "Delivery preference", "type": "multiple_choice", "required": true, "choices": ["PDF by email", "PDF saved for staff collection"]}, {"key": "consent", "title": "I authorize verification and delivery to the stated recipient.", "type": "checkbox", "required": true, "choices": ["I authorize"]}]}];
const SIS_FOLDER_DEFINITIONS = [{"code": "forms", "name": "01 Forms", "purpose": "Provisioned Google Forms"}, {"code": "responses", "name": "02 Response Sheets", "purpose": "Linked form-response spreadsheets"}, {"code": "student_documents", "name": "03 Student Documents", "purpose": "Admission and registration documents"}, {"code": "uploaded_marks", "name": "04 Uploaded Marks", "purpose": "CSV/XLSX marks files submitted by teachers"}, {"code": "transcript_docs", "name": "05 Transcript Google Docs", "purpose": "Generated editable transcript documents"}, {"code": "transcript_pdfs", "name": "06 Transcript PDFs", "purpose": "Final exported transcript PDFs"}, {"code": "hec_reports", "name": "07 HEC Reports", "purpose": "Generated HEC enrollment reports"}, {"code": "dashboard", "name": "08 Dashboard", "purpose": "Operational dashboard spreadsheet"}, {"code": "failed", "name": "09 Failed Files", "purpose": "Rejected or unprocessable files with sanitized failure evidence"}, {"code": "archive", "name": "10 Archive", "purpose": "Completed-period assets retained according to policy"}, {"code": "templates", "name": "11 Templates", "purpose": "Master Docs and Sheets templates"}, {"code": "registry", "name": "12 Asset Registry", "purpose": "Provisioning registry and manifest"}];
const SIS_QUEUE_COLUMNS = ["Form Response ID", "Submitted At UTC", "Respondent Email", "Operation", "Source Form ID", "Source Spreadsheet ID", "Raw Response JSON", "Processing Status", "Processed At UTC", "Correlation ID", "Idempotency Key", "Error Code", "Error Message", "Retry Count", "Last Attempt At UTC", "n8n Execution ID"];

function provisionPhase3Workspace() {
  const state = loadState_();
  const root = getOrCreateRootFolder_(state);
  const folders = provisionFolders_(root, state);
  const assets = {
    version: SIS_PHASE3_VERSION,
    provisionedAt: new Date().toISOString(),
    rootFolderId: root.getId(),
    rootFolderUrl: root.getUrl(),
    folders: {},
    forms: {},
    templates: {},
    registry: null,
  };

  Object.keys(folders).forEach(function(key) {
    assets.folders[key] = {
      id: folders[key].getId(),
      name: folders[key].getName(),
      url: folders[key].getUrl(),
    };
  });

  SIS_FORM_DEFINITIONS.forEach(function(definition) {
    assets.forms[definition.code] = provisionForm_(definition, folders, state);
  });

  removePhase3FormTriggers_();
  Object.keys(assets.forms).forEach(function(code) {
    ScriptApp.newTrigger('handleFormSubmit')
      .forForm(FormApp.openById(assets.forms[code].formId))
      .onFormSubmit()
      .create();
  });

  assets.templates.transcript = provisionTranscriptTemplate_(folders.templates, state);
  assets.templates.hec = provisionHecTemplate_(folders.templates, state);
  assets.templates.dashboard = provisionDashboardTemplate_(folders.dashboard, state);
  assets.registry = writeAssetRegistry_(folders.registry, assets, state);

  state.assets = assets;
  saveState_(state);

  const result = {
    success: true,
    suite: 'phase3-google-workspace-provisioning',
    version: SIS_PHASE3_VERSION,
    root_folder_id: assets.rootFolderId,
    forms: Object.keys(assets.forms).length,
    response_spreadsheets: Object.keys(assets.forms).length,
    form_submit_triggers: Object.keys(assets.forms).length,
    folders: Object.keys(assets.folders).length,
    transcript_templates: 1,
    hec_templates: 1,
    dashboard_templates: 1,
    asset_registry_url: assets.registry.url,
  };

  console.log(JSON.stringify(result));
  return JSON.stringify(result);
}

function verifyPhase3Assets() {
  const state = loadState_();
  const assets = state.assets || {};
  const missing = [];
  let formCount = 0;
  let responseSheetCount = 0;
  let folderCount = 0;

  Object.keys(assets.folders || {}).forEach(function(key) {
    try {
      const folder = DriveApp.getFolderById(assets.folders[key].id);
      if (folder.isTrashed()) missing.push('folder:' + key);
      else folderCount++;
    } catch (error) {
      missing.push('folder:' + key);
    }
  });

  Object.keys(assets.forms || {}).forEach(function(code) {
    const item = assets.forms[code];
    try {
      FormApp.openById(item.formId);
      formCount++;
    } catch (error) {
      missing.push('form:' + code);
    }
    try {
      SpreadsheetApp.openById(item.responseSpreadsheetId);
      responseSheetCount++;
    } catch (error) {
      missing.push('response_sheet:' + code);
    }
  });

  const templateChecks = [
    ['transcript', 'document'],
    ['hec', 'spreadsheet'],
    ['dashboard', 'spreadsheet'],
  ];
  let transcriptTemplates = 0;
  let hecTemplates = 0;
  let dashboardTemplates = 0;

  templateChecks.forEach(function(entry) {
    const key = entry[0];
    const item = (assets.templates || {})[key];
    if (!item || !item.id) {
      missing.push('template:' + key);
      return;
    }
    try {
      if (entry[1] === 'document') DocumentApp.openById(item.id);
      else SpreadsheetApp.openById(item.id);
      if (key === 'transcript') transcriptTemplates++;
      if (key === 'hec') hecTemplates++;
      if (key === 'dashboard') dashboardTemplates++;
    } catch (error) {
      missing.push('template:' + key);
    }
  });

  const triggers = ScriptApp.getProjectTriggers().filter(function(trigger) {
    return trigger.getHandlerFunction() === 'handleFormSubmit';
  }).length;

  const expectedForms = SIS_FORM_DEFINITIONS.length;
  const expectedFolders = SIS_FOLDER_DEFINITIONS.length;
  const success = missing.length === 0
    && formCount === expectedForms
    && responseSheetCount === expectedForms
    && triggers === expectedForms
    && folderCount === expectedFolders
    && transcriptTemplates === 1
    && hecTemplates === 1
    && dashboardTemplates === 1;

  const result = {
    success: success,
    suite: 'phase3-google-workspace-verification',
    version: SIS_PHASE3_VERSION,
    forms: formCount,
    response_spreadsheets: responseSheetCount,
    form_submit_triggers: triggers,
    folders: folderCount,
    transcript_templates: transcriptTemplates,
    hec_templates: hecTemplates,
    dashboard_templates: dashboardTemplates,
    missing: missing,
    asset_registry_url: assets.registry ? assets.registry.url : null,
  };

  console.log(JSON.stringify(result));
  return JSON.stringify(result);
}

function handleFormSubmit(event) {
  if (!event || !event.response || !event.source) {
    throw new Error('A Google Forms installable submit event is required.');
  }

  const form = event.source;
  const response = event.response;
  const state = loadState_();
  const formAsset = findFormAssetById_(state.assets, form.getId());
  if (!formAsset) throw new Error('The submitted form is not registered in the Phase 3 asset state.');

  const spreadsheet = SpreadsheetApp.openById(formAsset.responseSpreadsheetId);
  const queue = spreadsheet.getSheetByName('Automation Queue');
  if (!queue) throw new Error('Automation Queue sheet is missing.');

  const raw = {};
  response.getItemResponses().forEach(function(itemResponse) {
    const title = itemResponse.getItem().getTitle();
    const value = itemResponse.getResponse();
    raw[title] = Array.isArray(value) ? value : String(value == null ? '' : value);
  });

  const responseId = response.getId();
  const submittedAt = response.getTimestamp();
  const respondentEmail = response.getRespondentEmail() || '';
  const idempotencyKey = 'google-form:' + form.getId() + ':' + responseId;

  queue.appendRow([
    responseId,
    Utilities.formatDate(submittedAt, 'UTC', "yyyy-MM-dd'T'HH:mm:ss'Z'"),
    respondentEmail,
    formAsset.operation,
    form.getId(),
    spreadsheet.getId(),
    JSON.stringify(raw),
    'pending',
    '',
    '',
    idempotencyKey,
    '',
    '',
    0,
    '',
    '',
  ]);
}

function getOrCreateRootFolder_(state) {
  if (state.rootFolderId) {
    try {
      const folder = DriveApp.getFolderById(state.rootFolderId);
      if (!folder.isTrashed()) return folder;
    } catch (error) {}
  }

  const existing = DriveApp.getFoldersByName(SIS_ROOT_FOLDER_NAME);
  const folder = existing.hasNext() ? existing.next() : DriveApp.createFolder(SIS_ROOT_FOLDER_NAME);
  state.rootFolderId = folder.getId();
  saveState_(state);
  return folder;
}

function provisionFolders_(root, state) {
  const result = {};
  SIS_FOLDER_DEFINITIONS.forEach(function(definition) {
    const stateKey = 'folder_' + definition.code;
    let folder = null;

    if (state[stateKey]) {
      try {
        folder = DriveApp.getFolderById(state[stateKey]);
        if (folder.isTrashed()) folder = null;
      } catch (error) {
        folder = null;
      }
    }

    if (!folder) {
      const matches = root.getFoldersByName(definition.name);
      folder = matches.hasNext() ? matches.next() : root.createFolder(definition.name);
      state[stateKey] = folder.getId();
    }

    result[definition.code] = folder;
  });
  saveState_(state);
  return result;
}

function provisionForm_(definition, folders, state) {
  const stateKey = 'form_' + definition.code;
  let form = null;
  let responseSpreadsheet = null;

  if (state[stateKey] && state[stateKey].formId) {
    try {
      form = FormApp.openById(state[stateKey].formId);
      responseSpreadsheet = SpreadsheetApp.openById(state[stateKey].responseSpreadsheetId);
    } catch (error) {
      form = null;
      responseSpreadsheet = null;
    }
  }

  if (!form) {
    form = FormApp.create(definition.title, true);
    form.setDescription(definition.description);
    form.setConfirmationMessage(definition.confirmation);
    form.setCollectEmail(definition.collect_email);
    form.setAllowResponseEdits(false);
    form.setLimitOneResponsePerUser(false);
    form.setShowLinkToRespondAgain(true);

    definition.fields.forEach(function(field) {
      addFormItem_(form, field);
    });

    responseSpreadsheet = SpreadsheetApp.create(definition.title + ' — Responses');
    form.setDestination(FormApp.DestinationType.SPREADSHEET, responseSpreadsheet.getId());

    moveFileToFolder_(form.getId(), folders.forms);
    moveFileToFolder_(responseSpreadsheet.getId(), folders.responses);

    configureResponseSpreadsheet_(responseSpreadsheet, form, definition);

    state[stateKey] = {
      formId: form.getId(),
      responseSpreadsheetId: responseSpreadsheet.getId(),
      operation: definition.operation,
    };
    saveState_(state);
  } else {
    configureResponseSpreadsheet_(responseSpreadsheet, form, definition);
  }

  return {
    code: definition.code,
    operation: definition.operation,
    formId: form.getId(),
    editUrl: form.getEditUrl(),
    publishedUrl: form.getPublishedUrl(),
    responseSpreadsheetId: responseSpreadsheet.getId(),
    responseSpreadsheetUrl: responseSpreadsheet.getUrl(),
  };
}

function addFormItem_(form, field) {
  let item;
  if (field.type === 'text') {
    item = form.addTextItem().setTitle(field.title).setRequired(field.required);
    if (field.validation === 'email') {
      item.setValidation(FormApp.createTextValidation().requireTextIsEmail().build());
    }
    if (field.validation === 'url') {
      item.setValidation(FormApp.createTextValidation().requireTextIsUrl().build());
    }
  } else if (field.type === 'paragraph') {
    item = form.addParagraphTextItem().setTitle(field.title).setRequired(field.required);
  } else if (field.type === 'date') {
    item = form.addDateItem().setTitle(field.title).setIncludesYear(true).setRequired(field.required);
  } else if (field.type === 'list') {
    item = form.addListItem().setTitle(field.title).setChoiceValues(field.choices || []).setRequired(field.required);
  } else if (field.type === 'multiple_choice') {
    item = form.addMultipleChoiceItem().setTitle(field.title).setChoiceValues(field.choices || []).setRequired(field.required);
  } else if (field.type === 'checkbox') {
    item = form.addCheckboxItem().setTitle(field.title).setChoiceValues(field.choices || []).setRequired(field.required);
  } else {
    throw new Error('Unsupported form field type: ' + field.type);
  }

  item.setHelpText('Field key: ' + field.key);
}

function configureResponseSpreadsheet_(spreadsheet, form, definition) {
  let queue = spreadsheet.getSheetByName('Automation Queue');
  if (!queue) queue = spreadsheet.insertSheet('Automation Queue');

  if (queue.getLastRow() === 0) {
    queue.getRange(1, 1, 1, SIS_QUEUE_COLUMNS.length).setValues([SIS_QUEUE_COLUMNS]);
  } else {
    const existingHeaders = queue.getRange(1, 1, 1, SIS_QUEUE_COLUMNS.length).getValues()[0];
    if (JSON.stringify(existingHeaders) !== JSON.stringify(SIS_QUEUE_COLUMNS)) {
      throw new Error('Automation Queue headers do not match the Phase 3 contract for ' + definition.code);
    }
  }

  queue.getRange(1, 1, 1, SIS_QUEUE_COLUMNS.length).setFontWeight('bold');
  queue.setFrozenRows(1);
  queue.getRange('H2:H').setDataValidation(
    SpreadsheetApp.newDataValidation()
      .requireValueInList(['pending','processing','completed','failed','dead_letter','ignored'], true)
      .setAllowInvalid(false)
      .build()
  );

  let metadata = spreadsheet.getSheetByName('Setup Metadata');
  if (!metadata) metadata = spreadsheet.insertSheet('Setup Metadata');
  metadata.clear();
  metadata.getRange(1, 1, 8, 2).setValues([
    ['Key','Value'],
    ['phase3_version', SIS_PHASE3_VERSION],
    ['form_code', definition.code],
    ['operation', definition.operation],
    ['form_id', form.getId()],
    ['response_spreadsheet_id', spreadsheet.getId()],
    ['configured_at', new Date().toISOString()],
    ['queue_tab', 'Automation Queue'],
  ]);
  metadata.getRange(1, 1, 1, 2).setFontWeight('bold');
  metadata.setFrozenRows(1);
}

function provisionTranscriptTemplate_(folder, state) {
  const stateKey = 'template_transcript';
  if (state[stateKey]) {
    try {
      const existing = DocumentApp.openById(state[stateKey]);
      return { id: existing.getId(), url: existing.getUrl(), name: existing.getName() };
    } catch (error) {}
  }

  const doc = DocumentApp.create('SIS — Official Transcript Template');
  const body = doc.getBody();
  body.clear();

  const header = body.appendTable([
    ['{INSTITUTION_LOGO}', '{INSTITUTION_NAME}\n{INSTITUTION_ADDRESS}\n{INSTITUTION_PHONE} | {INSTITUTION_EMAIL}'],
  ]);
  header.setBorderWidth(0);
  header.getCell(0, 1).getChild(0).asParagraph().setAlignment(DocumentApp.HorizontalAlignment.CENTER);
  body.appendParagraph('OFFICIAL ACADEMIC TRANSCRIPT')
    .setHeading(DocumentApp.ParagraphHeading.HEADING1)
    .setAlignment(DocumentApp.HorizontalAlignment.CENTER);

  body.appendTable([
    ['Student Name', '{STUDENT_NAME}', 'Student Number', '{STUDENT_NUMBER}'],
    ['Date of Birth', '{DATE_OF_BIRTH}', 'Campus', '{CAMPUS_NAME}'],
    ['Program', '{PROGRAM_NAME}', 'Program Code', '{PROGRAM_CODE}'],
    ['Admission Date', '{ADMISSION_DATE}', 'Completion Date', '{COMPLETION_DATE}'],
  ]);

  body.appendParagraph('ACADEMIC RECORD').setHeading(DocumentApp.ParagraphHeading.HEADING2);
  body.appendTable([
    ['Term','Course/Subject Code','Course/Subject Title','Credit Hours','Grade','Grade Points'],
    ['{RESULT_ROWS_START}','','','','',''],
    ['{RESULT_ROWS_END}','','','','',''],
  ]);

  body.appendParagraph('ACADEMIC SUMMARY').setHeading(DocumentApp.ParagraphHeading.HEADING2);
  body.appendTable([
    ['Credits Attempted','{TOTAL_CREDITS_ATTEMPTED}','Credits Earned','{TOTAL_CREDITS_EARNED}'],
    ['CGPA','{CGPA}','Academic Standing','{ACADEMIC_STANDING}'],
  ]);

  body.appendParagraph('ISSUANCE AND VERIFICATION').setHeading(DocumentApp.ParagraphHeading.HEADING2);
  body.appendTable([
    ['Issue Date','{ISSUE_DATE}'],
    ['Transcript Reference','{TRANSCRIPT_REFERENCE}'],
    ['Verification Code','{VERIFICATION_CODE}'],
    ['Verification URL','{VERIFICATION_URL}'],
  ]);
  body.appendParagraph('{OFFICIAL_DISCLAIMER}');
  body.appendParagraph('This document is valid only when issued through the authorized academic administration process.');

  doc.saveAndClose();
  moveFileToFolder_(doc.getId(), folder);
  state[stateKey] = doc.getId();
  saveState_(state);
  return { id: doc.getId(), url: doc.getUrl(), name: doc.getName() };
}

function provisionHecTemplate_(folder, state) {
  const stateKey = 'template_hec';
  if (state[stateKey]) {
    try {
      const existing = SpreadsheetApp.openById(state[stateKey]);
      return { id: existing.getId(), url: existing.getUrl(), name: existing.getName() };
    } catch (error) {}
  }

  const book = SpreadsheetApp.create('SIS — HEC Enrollment Report Template');
  const report = book.getSheets()[0];
  report.setName('HEC_Enrollment_Report');
  const headers = [
    'institution_code','institution_name','campus_code','campus_name',
    'academic_year','term_code','program_code','program_name','degree_level',
    'student_number','student_name','gender','admission_date','enrollment_status',
    'current_term','registered_credit_hours','cumulative_earned_credits','cgpa',
    'standing_code','identity_reference','domicile','nationality',
    'report_run_id','generated_at_utc'
  ];
  report.getRange(1,1,1,headers.length).setValues([headers]).setFontWeight('bold');
  report.setFrozenRows(1);

  const metadata = book.insertSheet('Report_Metadata');
  metadata.getRange(1,1,10,2).setValues([
    ['Field','Value'],
    ['institution_code',''],
    ['campus_code',''],
    ['academic_year',''],
    ['term_code',''],
    ['report_run_id',''],
    ['generated_at_utc',''],
    ['record_count',''],
    ['template_version',SIS_PHASE3_VERSION],
    ['official_format_confirmed','NO — demonstration template'],
  ]);
  metadata.getRange(1,1,1,2).setFontWeight('bold');

  const lists = book.insertSheet('Validation_Lists');
  lists.getRange(1,1,6,3).setValues([
    ['enrollment_status','gender','standing_code'],
    ['active','Female','GOOD'],
    ['completed','Male','PROBATION'],
    ['withdrawn','Other','AT_RISK'],
    ['suspended','Prefer not to say','SUSPENDED'],
    ['cancelled','',''],
  ]);

  const instructions = book.insertSheet('Instructions');
  instructions.getRange('A1').setValue('SIS HEC Demonstration Report Template').setFontWeight('bold');
  instructions.getRange('A3').setValue('This template must be mapped to the institution’s current official HEC reporting specification before submission.');
  instructions.getRange('A5').setValue('The Phase 4 HEC workflow writes report rows, metadata, generated file identifiers and delivery evidence.');

  moveFileToFolder_(book.getId(), folder);
  state[stateKey] = book.getId();
  saveState_(state);
  return { id: book.getId(), url: book.getUrl(), name: book.getName() };
}

function provisionDashboardTemplate_(folder, state) {
  const stateKey = 'template_dashboard';
  if (state[stateKey]) {
    try {
      const existing = SpreadsheetApp.openById(state[stateKey]);
      return { id: existing.getId(), url: existing.getUrl(), name: existing.getName() };
    } catch (error) {}
  }

  const book = SpreadsheetApp.create('SIS — Operational Dashboard');
  const dashboard = book.getSheets()[0];
  dashboard.setName('Dashboard');
  dashboard.getRange('A1:H1').merge().setValue('SIS Operational Dashboard').setFontWeight('bold').setFontSize(18);
  dashboard.getRange('A2:H2').merge().setValue('Generated from the institution-scoped dashboard RPC.');

  const labels = [
    ['Students — Total','students.total'],
    ['Students — Active','students.active'],
    ['Students — At Risk','students.at_risk'],
    ['Active Enrollments','enrollment.active_count'],
    ['Waitlist','enrollment.waitlist_count'],
    ['Rejected Requests','enrollment.rejected_requests'],
    ['Draft Marks Batches','marks.draft_batches'],
    ['Finalized Marks Batches','marks.finalized_batches'],
    ['Approved Marks Batches','marks.approved_batches'],
    ['Pending Transcripts','transcripts.pending'],
    ['Ready Transcripts','transcripts.ready'],
    ['Notification Backlog','operations.notification_backlog'],
    ['Open Incidents','operations.open_incidents'],
  ];
  dashboard.getRange(4,1,labels.length,1).setValues(labels.map(function(row) { return [row[0]]; }));
  labels.forEach(function(row, index) {
    dashboard.getRange(4 + index, 2).setFormula(
      '=IFERROR(VLOOKUP("' + row[1] + '",Metrics!A:B,2,FALSE),0)'
    );
  });
  dashboard.getRange('A4:B16').setBorder(true,true,true,true,true,true);
  dashboard.getRange('A4:A16').setFontWeight('bold');
  dashboard.setFrozenRows(2);

  const metrics = book.insertSheet('Metrics');
  metrics.getRange(1,1,1,3).setValues([['metric_key','metric_value','refreshed_at_utc']]).setFontWeight('bold');
  metrics.getRange(2,1,labels.length + 1,3).setValues(
    labels.map(function(row) { return [row[1],0,'']; }).concat([['generated_at','','']])
  );
  metrics.setFrozenRows(1);

  const capacity = book.insertSheet('Section_Capacity');
  capacity.getRange(1,1,1,6).setValues([[
    'section_id','section_code','capacity','enrolled_count','remaining_capacity','waitlist_count'
  ]]).setFontWeight('bold');
  capacity.setFrozenRows(1);

  const refresh = book.insertSheet('Refresh_Log');
  refresh.getRange(1,1,1,7).setValues([[
    'refreshed_at_utc','institution_id','campus_id','term_id',
    'correlation_id','n8n_execution_id','status'
  ]]).setFontWeight('bold');

  const instructions = book.insertSheet('Instructions');
  instructions.getRange('A1').setValue('SIS Operational Dashboard').setFontWeight('bold');
  instructions.getRange('A3').setValue('Phase 4 workflow 07 refreshes Metrics, Section_Capacity and Refresh_Log from rpc_get_dashboard_snapshot.');

  moveFileToFolder_(book.getId(), folder);
  state[stateKey] = book.getId();
  saveState_(state);
  return { id: book.getId(), url: book.getUrl(), name: book.getName() };
}

function writeAssetRegistry_(folder, assets, state) {
  const stateKey = 'asset_registry';
  let book = null;
  if (state[stateKey]) {
    try {
      book = SpreadsheetApp.openById(state[stateKey]);
    } catch (error) {
      book = null;
    }
  }
  if (!book) {
    book = SpreadsheetApp.create('SIS — Phase 3 Asset Registry');
    moveFileToFolder_(book.getId(), folder);
    state[stateKey] = book.getId();
  }

  const registry = book.getSheets()[0];
  registry.setName('Assets');
  registry.clear();
  registry.getRange(1,1,1,6).setValues([[
    'asset_type','asset_code','name','id','url','phase3_version'
  ]]).setFontWeight('bold');

  const rows = [];
  Object.keys(assets.folders).forEach(function(code) {
    const item = assets.folders[code];
    rows.push(['folder',code,item.name,item.id,item.url,SIS_PHASE3_VERSION]);
  });
  Object.keys(assets.forms).forEach(function(code) {
    const item = assets.forms[code];
    rows.push(['form',code,code,item.formId,item.publishedUrl,SIS_PHASE3_VERSION]);
    rows.push(['response_spreadsheet',code,code + ' responses',item.responseSpreadsheetId,item.responseSpreadsheetUrl,SIS_PHASE3_VERSION]);
  });
  Object.keys(assets.templates).forEach(function(code) {
    const item = assets.templates[code];
    rows.push(['template',code,item.name,item.id,item.url,SIS_PHASE3_VERSION]);
  });

  if (rows.length) registry.getRange(2,1,rows.length,6).setValues(rows);
  registry.setFrozenRows(1);
  registry.autoResizeColumns(1,6);

  const jsonSheet = book.getSheetByName('Manifest_JSON') || book.insertSheet('Manifest_JSON');
  jsonSheet.clear();
  jsonSheet.getRange('A1').setValue(JSON.stringify(assets));

  saveState_(state);
  return { id: book.getId(), url: book.getUrl(), name: book.getName() };
}

function removePhase3FormTriggers_() {
  ScriptApp.getProjectTriggers().forEach(function(trigger) {
    if (trigger.getHandlerFunction() === 'handleFormSubmit') {
      ScriptApp.deleteTrigger(trigger);
    }
  });
}

function findFormAssetById_(assets, formId) {
  const forms = (assets || {}).forms || {};
  const codes = Object.keys(forms);
  for (let i = 0; i < codes.length; i++) {
    if (forms[codes[i]].formId === formId) return forms[codes[i]];
  }
  return null;
}

function moveFileToFolder_(fileId, folder) {
  const file = DriveApp.getFileById(fileId);
  folder.addFile(file);
  try {
    DriveApp.getRootFolder().removeFile(file);
  } catch (error) {
    // Shared-drive and modern Drive behavior may not expose a removable My Drive parent.
  }
}

function loadState_() {
  const raw = PropertiesService.getScriptProperties().getProperty('SIS_PHASE3_STATE');
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error('Stored Phase 3 state is invalid JSON.');
  }
}

function saveState_(state) {
  PropertiesService.getScriptProperties().setProperty('SIS_PHASE3_STATE', JSON.stringify(state));
}

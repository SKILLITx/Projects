/**
 * Append this function to the existing SIS Phase 3 Workspace Provisioner project.
 * Run getPhase4Wave1N8nConfiguration() and copy only the returned non-secret JSON.
 */
function getPhase4Wave1N8nConfiguration() {
  const state = loadState_();
  const assets = state.assets || {};
  const student = assets.forms && assets.forms['student-profile'];
  const enrollment = assets.forms && assets.forms['enrollment-request'];
  if (!student || !enrollment) throw new Error('Run provisionPhase3Workspace first.');

  const studentBook = SpreadsheetApp.openById(student.responseSpreadsheetId);
  const enrollmentBook = SpreadsheetApp.openById(enrollment.responseSpreadsheetId);
  const studentQueue = studentBook.getSheetByName('Automation Queue');
  const enrollmentQueue = enrollmentBook.getSheetByName('Automation Queue');
  if (!studentQueue || !enrollmentQueue) throw new Error('Automation Queue tab is missing.');

  const result = {
    success: true,
    suite: 'phase4-wave1-google-config',
    SIS_STUDENT_PROFILE_RESPONSE_SHEET_ID: student.responseSpreadsheetId,
    SIS_STUDENT_PROFILE_QUEUE_TAB_ID: String(studentQueue.getSheetId()),
    SIS_ENROLLMENT_RESPONSE_SHEET_ID: enrollment.responseSpreadsheetId,
    SIS_ENROLLMENT_QUEUE_TAB_ID: String(enrollmentQueue.getSheetId()),
  };
  console.log(JSON.stringify(result));
  return JSON.stringify(result);
}

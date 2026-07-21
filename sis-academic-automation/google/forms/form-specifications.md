# Google Form Specifications

All six forms are provisioned by `google/provisioning/SIS-WorkspaceProvisioner.gs`.
The provisioner links each form to its own response spreadsheet and installs a form-submit trigger that writes a normalized row to the `Automation Queue` tab.

## SIS — Student Profile and Admission

- Code: `student-profile`
- Operation: `student.profile.submit`
- Audience: `student_or_admissions_staff`
- Collect verified Google account email: `true`

| Key | Question | Type | Required |
|---|---|---|---|
| `institution_code` | Institution code | list | Yes |
| `campus_code` | Campus code | list | Yes |
| `submission_type` | Submission type | multiple_choice | Yes |
| `student_number` | Student number (leave blank only for a new admission) | text | No |
| `full_name` | Full legal name | text | Yes |
| `date_of_birth` | Date of birth | date | Yes |
| `gender` | Gender | list | No |
| `primary_email` | Primary email address | text | Yes |
| `mobile_phone` | Mobile phone number | text | Yes |
| `guardian_name` | Guardian name (required for school students) | text | No |
| `guardian_phone` | Guardian phone (required for school students) | text | No |
| `identity_reference` | Institution-approved identity reference | text | No |
| `program_code` | Program or qualification code | text | Yes |
| `academic_year_code` | Academic year code | text | Yes |
| `admission_term_code` | Admission term code | text | Yes |
| `previous_qualification` | Previous qualification or school | paragraph | No |
| `document_links` | Required document Drive links (one per line) | paragraph | No |
| `additional_notes` | Additional notes | paragraph | No |
| `consent` | I confirm that the information is accurate and may be processed for academic administration. | checkbox | Yes |

## SIS — Course or Subject Enrollment Request

- Code: `enrollment-request`
- Operation: `enrollment.submit`
- Audience: `student`
- Collect verified Google account email: `true`

| Key | Question | Type | Required |
|---|---|---|---|
| `institution_code` | Institution code | list | Yes |
| `campus_code` | Campus code | list | Yes |
| `student_number` | Student number | text | Yes |
| `program_code` | Program or qualification code | text | Yes |
| `term_code` | Term or semester code | text | Yes |
| `requested_course_codes` | Requested course or subject codes (comma-separated) | paragraph | Yes |
| `preferred_section_codes` | Preferred section codes in the same order (optional, comma-separated) | paragraph | No |
| `allow_fallback` | Allow another valid section when the preferred section is unavailable? | multiple_choice | Yes |
| `request_notes` | Enrollment notes | paragraph | No |
| `consent` | I understand that prerequisites, capacity, timetable, document and load rules will be checked. | checkbox | Yes |

## SIS — Teacher Marks Submission

- Code: `teacher-marks`
- Operation: `marks.batch.submit`
- Audience: `authorized_teacher`
- Collect verified Google account email: `true`

| Key | Question | Type | Required |
|---|---|---|---|
| `institution_code` | Institution code | list | Yes |
| `campus_code` | Campus code | list | Yes |
| `term_code` | Term or semester code | text | Yes |
| `course_offering_code` | Course offering code | text | Yes |
| `section_code` | Section code | text | Yes |
| `assessment_code` | Assessment code | text | Yes |
| `submission_state` | Submission state | multiple_choice | Yes |
| `marks_lines` | Marks — one line per student: student_number,marks,absent,remarks | paragraph | Yes |
| `teacher_notes` | Teacher notes | paragraph | No |
| `declaration` | I confirm that I am assigned to this class and that these marks are accurate. | checkbox | Yes |

## SIS — Marks CSV or Excel Upload

- Code: `marks-file-upload`
- Operation: `marks.file.submit`
- Audience: `authorized_teacher`
- Collect verified Google account email: `true`

| Key | Question | Type | Required |
|---|---|---|---|
| `institution_code` | Institution code | list | Yes |
| `campus_code` | Campus code | list | Yes |
| `term_code` | Term or semester code | text | Yes |
| `course_offering_code` | Course offering code | text | Yes |
| `section_code` | Section code | text | Yes |
| `assessment_code` | Assessment code | text | Yes |
| `submission_state` | Submission state | multiple_choice | Yes |
| `file_drive_url` | Uploaded CSV or Excel Google Drive URL | text | Yes |
| `original_file_name` | Original file name | text | Yes |
| `file_notes` | File notes | paragraph | No |
| `declaration` | I confirm that I am authorized to submit this class file. | checkbox | Yes |

## SIS — Mark Correction Request

- Code: `mark-correction`
- Operation: `marks.correction.request`
- Audience: `authorized_teacher`
- Collect verified Google account email: `true`

| Key | Question | Type | Required |
|---|---|---|---|
| `institution_code` | Institution code | list | Yes |
| `campus_code` | Campus code | list | Yes |
| `marks_batch_id` | Marks batch ID | text | Yes |
| `student_mark_id` | Student mark ID | text | Yes |
| `student_number` | Student number | text | Yes |
| `assessment_code` | Assessment code | text | Yes |
| `current_marks` | Current marks | text | Yes |
| `proposed_marks` | Proposed corrected marks | text | Yes |
| `reason` | Detailed reason for correction | paragraph | Yes |
| `evidence_drive_url` | Supporting evidence Drive URL (optional) | text | No |
| `declaration` | I confirm that this request is accurate and auditable. | checkbox | Yes |

## SIS — Transcript Request

- Code: `transcript-request`
- Operation: `transcript.request`
- Audience: `student_or_authorized_staff`
- Collect verified Google account email: `true`

| Key | Question | Type | Required |
|---|---|---|---|
| `institution_code` | Institution code | list | Yes |
| `campus_code` | Campus code | list | Yes |
| `student_number` | Student number | text | Yes |
| `requester_relationship` | Requester relationship | multiple_choice | Yes |
| `student_date_of_birth` | Student date of birth | date | Yes |
| `recipient_email` | Approved recipient email | text | Yes |
| `purpose` | Purpose of transcript | list | Yes |
| `purpose_details` | Purpose details | paragraph | No |
| `delivery_preference` | Delivery preference | multiple_choice | Yes |
| `consent` | I authorize verification and delivery to the stated recipient. | checkbox | Yes |


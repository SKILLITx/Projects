const source = $('Normalize Marks File Queue Row').first().json;
const inputItems = $input.all();
const now = new Date().toISOString();

const failure = (errorCode, errorMessage, incrementRetry = false) => [
  {
    json: {
      ...source,
      requestReady: false,
      'Form Response ID': source.queue.formResponseId,
      'Processing Status': 'failed',
      'Processed At UTC': now,
      'Correlation ID': source.correlationId,
      'Error Code': String(errorCode || 'FILE_VALIDATION_FAILED')
        .trim()
        .toUpperCase()
        .replace(/[^A-Z0-9_]+/g, '_')
        .slice(0, 100),
      'Error Message': String(
        errorMessage || 'The uploaded marks file did not pass validation.'
      ).slice(0, 300),
      'Retry Count':
        source.queue.retryCount + (incrementRetry ? 1 : 0),
      'Last Attempt At UTC': now,
      'n8n Execution ID': $execution.id,
      success: false,
    },
  },
];

if (inputItems.length === 0) {
  return failure(
    'FILE_EMPTY',
    'The uploaded marks file contains no data rows.'
  );
}

const extractionError = inputItems.find(
  (item) =>
    item.json?.error ||
    item.json?.errorMessage ||
    Number(item.json?.statusCode || item.json?.status || 0) >= 400
);

if (extractionError) {
  const extractionMessage =
    extractionError.json?.error?.message ||
    extractionError.json?.errorMessage ||
    extractionError.json?.error ||
    extractionError.json?.message ||
    'The uploaded marks file could not be parsed.';

  return failure(
    'FILE_PARSE_FAILED',
    extractionMessage,
    false
  );
}

const normalizeHeader = (value) =>
  String(value ?? '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');

const truthy = new Set([
  'true',
  'yes',
  'y',
  '1',
  'absent',
  'missing',
]);

const falsy = new Set([
  '',
  'false',
  'no',
  'n',
  '0',
  'present',
]);

const getColumn = (row, aliases) => {
  const mapped = {};

  for (const [key, value] of Object.entries(row || {})) {
    mapped[normalizeHeader(key)] = value;
  }

  for (const alias of aliases) {
    const normalizedAlias = normalizeHeader(alias);

    if (
      Object.prototype.hasOwnProperty.call(
        mapped,
        normalizedAlias
      )
    ) {
      return mapped[normalizedAlias];
    }
  }

  return undefined;
};

try {
  const marks = inputItems.map((item, index) => {
    const row = item.json || {};
    const line = index + 2;

    const studentNumber = String(
      getColumn(row, [
        'student_number',
        'student number',
        'student_id',
        'student id',
      ]) ?? ''
    )
      .trim()
      .toUpperCase();

    if (!studentNumber) {
      throw new Error(
        `FILE_ROW_${line}_STUDENT_NUMBER_REQUIRED`
      );
    }

    const absentValue = String(
      getColumn(row, ['absent', 'is_absent']) ?? ''
    )
      .trim()
      .toLowerCase();

    const missingValue = String(
      getColumn(row, ['missing', 'is_missing']) ?? ''
    )
      .trim()
      .toLowerCase();

    if (
      !truthy.has(absentValue) &&
      !falsy.has(absentValue)
    ) {
      throw new Error(
        `FILE_ROW_${line}_ABSENT_INVALID`
      );
    }

    if (
      !truthy.has(missingValue) &&
      !falsy.has(missingValue)
    ) {
      throw new Error(
        `FILE_ROW_${line}_MISSING_INVALID`
      );
    }

    const isAbsent = truthy.has(absentValue);
    const isMissing = truthy.has(missingValue);

    if (isAbsent && isMissing) {
      throw new Error(
        `FILE_ROW_${line}_ABSENT_AND_MISSING`
      );
    }

    const marksRaw = getColumn(row, [
      'marks',
      'marks_obtained',
      'obtained_marks',
      'score',
    ]);

    let marksObtained = null;

    if (!isAbsent && !isMissing) {
      const marksText = String(marksRaw ?? '').trim();

      if (marksText === '') {
        throw new Error(
          `FILE_ROW_${line}_MARKS_REQUIRED`
        );
      }

      const parsedMarks = Number(marksText);

      if (
        !Number.isFinite(parsedMarks) ||
        parsedMarks < 0
      ) {
        throw new Error(
          `FILE_ROW_${line}_MARKS_INVALID`
        );
      }

      marksObtained = parsedMarks;
    } else if (String(marksRaw ?? '').trim() !== '') {
      throw new Error(
        `FILE_ROW_${line}_NON_PRESENT_MARKS_VALUE`
      );
    }

    return {
      student_number: studentNumber,
      marks_obtained: marksObtained,
      is_absent: isAbsent,
      is_missing: isMissing,
      remarks:
        String(
          getColumn(row, [
            'remarks',
            'comment',
            'comments',
            'notes',
          ]) ?? ''
        ).trim() || null,
    };
  });

  const studentNumbers = marks.map(
    (mark) => mark.student_number
  );

  const duplicateStudentNumbers = [
    ...new Set(
      studentNumbers.filter(
        (studentNumber, index) =>
          studentNumbers.indexOf(studentNumber) !== index
      )
    ),
  ];

  if (duplicateStudentNumbers.length > 0) {
    return failure(
      'VALIDATION_DUPLICATE_STUDENT_NUMBER',
      `Duplicate student number detected: ${duplicateStudentNumbers.join(', ')}.`
    );
  }

  const context = source.formContext;

  return [
    {
      json: {
        ...source,
        requestReady: true,
        markCount: marks.length,
        request: {
          operation: 'marks.batch.submit',
          correlation_id: source.correlationId,
          idempotency_key: source.idempotencyKey,
          requester: {
            email: context.teacherEmail,
            type:
              'authorized_teacher_google_form_file_upload',
          },
          submitted_at: source.submittedAt,
          source: {
            channel: 'google_forms_drive_upload',
            source_submission_id:
              source.queue.formResponseId,
            source_form_id: source.sourceFormId,
            source_spreadsheet_id:
              source.sourceSpreadsheetId,
            source_file_id: source.fileId,
            source_file_name: source.originalFileName,
          },
          payload: {
            institution_code:
              context.institutionCode,
            campus_code: context.campusCode,
            term_code: context.termCode,
            course_offering_code:
              context.courseOfferingCode,
            section_code: context.sectionCode,
            assessment_code:
              context.assessmentCode,
            submission_state:
              context.submissionState,
            teacher_email: context.teacherEmail,
            teacher_notes: context.teacherNotes,
            marks,
          },
        },
      },
    },
  ];
} catch (error) {
  const code =
    error instanceof Error && error.message
      ? error.message
      : 'FILE_VALIDATION_FAILED';

  return failure(
    code,
    code.startsWith('FILE_ROW_')
      ? `The uploaded marks file contains an invalid value (${code}).`
      : 'The uploaded marks file did not pass validation.'
  );
}

# Phase 3 Secret-Scan Regression Fixture Repair

## Failure

The secret scanner correctly detected a secret-shaped literal inside its own regression-test script before that script could create and test the temporary probe file.

## Root cause

The test fixture contained the complete fake server-key pattern as source text. Because the regression script is itself a portable project file, the scanner correctly rejected it.

## Repair

The regression script now constructs the fake variable name and fake key prefix from separate string fragments at runtime. Therefore:

- the portable regression script contains no complete secret-shaped literal;
- the temporary test file still receives a complete fake secret;
- the validator must reject the temporary file;
- the temporary file is removed;
- the validator runs again and must pass.

The production validator itself is unchanged.

# Supabase URL test correction

The previous preflight test used this fragment inside a double-quoted
PowerShell string:

```powershell
"SUPABASE_URL=$ExpectedUrl"
```

With `Set-StrictMode`, PowerShell tried to read `$ExpectedUrl` from the test
script itself before the repair script ran, causing:

```text
The variable '$ExpectedUrl' cannot be retrieved because it has not been set.
```

The corrected test treats the fragment as literal text:

```powershell
'SUPABASE_URL=$ExpectedUrl'
```

The actual Supabase URL repair script was not executed and did not change the
environment during the failed attempt.

# Supabase Auth Staff Portal Setup

## First user

1. In Supabase Dashboard, create one Auth user with email/password.
2. From PowerShell run:

```powershell
& ".\scripts\Copy-FirstStaffBootstrap.ps1"
```

3. Enter the same email and choose the staff role locally.
4. Paste the generated SQL into Supabase SQL Editor and run it once.

## Browser configuration

Run:

```powershell
& ".\scripts\Initialize-PortalConfig.ps1"
```

Enter the Supabase anon key locally. The script writes `portal/config.local.js`, updates `.gitignore`, and never prints the key.

## Start

```powershell
& ".\scripts\Start-Portal.ps1"
```

Open `http://127.0.0.1:4173`.

## Security boundary

- The portal uses Supabase Auth sessions and public authenticated RPCs.
- The service-role key is server-side only and is not accepted by the portal setup.
- The local portal server is for development and controlled-pilot testing, not public production hosting.

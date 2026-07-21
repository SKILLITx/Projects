# Role and Authorization Matrix

## 1. Identity model

### Staff identities

`auth.users` is linked to `public.staff_profiles`. Roles and scopes are assigned through:

- `role_assignments`
- `campus_assignments`
- optional fine-grained `permission_grants`

### Teacher identities

Teachers are represented as staff profiles. `auth_user_id` may be absent for a teacher who uses only a domain-restricted Google Form. Their verified Google email must match the staff profile and a current teacher assignment.

### Student identities

Students exist independently of Supabase Auth. Optional authenticated access uses `student_auth_links` to associate an Auth user with one student record. Public Forms do not create broad direct database access.

## 2. Scope rules

- Every operational role assignment is institution-scoped.
- Campus administrators require explicit campus assignments.
- Registrar/Admin defaults to institution scope and may optionally be further campus-limited.
- Teacher access is limited to assigned offerings and sections.
- Student access is limited to the linked student record.
- Super Administrator is cross-institution but every elevated operation is audited.

## 3. Permission matrix

| Capability | Student | Teacher | Registrar/Admin | Campus Administrator | Super Administrator |
|---|---:|---:|---:|---:|---:|
| Submit public student profile request | Yes | No | On behalf | On behalf in campus | On behalf |
| View own permitted profile/results | Optional Auth only | No | Scoped | Assigned campuses | All |
| Submit enrollment request | Yes | No | On behalf | On behalf in campus | On behalf |
| Review enrollment | No | No | Institution | Assigned campuses | All |
| Decide enrollment | No | No | Institution | Assigned campuses if granted | All |
| View assigned sections | No | Yes | Institution | Assigned campuses | All |
| Submit marks draft | No | Assigned sections | If separately assigned | If separately assigned | Yes |
| Finalize marks | No | Own assigned batch | If separately assigned | If separately assigned | Yes |
| Approve/reject marks | No | No by default | Yes | If granted for campus | Yes |
| Request correction | Own published result only through controlled route | Own batch | Yes | Scoped | Yes |
| Approve correction | No | No | Yes | If granted | Yes |
| Publish results | No | No | Yes | If granted | Yes |
| Request transcript | Own | No | Scoped | Assigned campuses | All |
| Generate HEC report | No | No | Yes | Assigned campuses if granted | Yes |
| Search students | Own only | Assigned sections only | Institution | Assigned campuses | All |
| View dashboard | No | Assigned section summary | Institution | Assigned campuses | All |
| Configure institution | No | No | Limited policy administration if granted | No | Yes |
| View incidents | No | Own submission errors only | Institution | Assigned campuses | All |
| Resolve incidents | No | No | Operational incidents if granted | Scoped if granted | Yes |

## 4. Authorization evaluation order

Every authenticated operation evaluates:

1. valid Supabase Auth token;
2. active user and active staff profile;
3. active role assignment;
4. requested operation allowed for role;
5. institution matches the role assignment;
6. campus is inside assigned scope when applicable;
7. resource belongs to that institution/campus;
8. domain-specific ownership, such as teacher assignment;
9. operation-specific state transition is valid.

Failure at any step returns a stable sanitized code and writes private diagnostics when appropriate.

## 5. RLS strategy

- Enable RLS on all applicable public tables.
- Deny by default.
- Use helper functions that read `auth.uid()` and return authorized institution/campus scope.
- Avoid policies that trust client-supplied role names or institution IDs.
- Prefer RPCs for multi-table state changes.
- Keep service-role usage out of browsers.
- Audit all security-definer functions.

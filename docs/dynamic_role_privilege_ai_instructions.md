# Dynamic Role and Privilege System for Grace Connect

Use this guide when replacing hard-coded Grace Connect roles with a dynamic role and privilege system. It is based on `Dynamic Role and Privilege System for Grace Connect.pdf` and the current Flutter/Supabase codebase.

## Goal

Roles must be templates, not hard-coded permission logic. When a pastor or authorized leader assigns a role, the app must ask which app privileges should be granted for that assignment. The assigned user receives those privileges immediately, and the UI should show or hide features by privilege, not by role name.

Keep legacy roles working during migration, but new code should check privilege keys.

## Current Code To Inspect

- `lib/config/rbac_config.dart`: currently maps roles to `AppPermission`.
- `lib/models/role_system/church_role.dart`: current role registry.
- `lib/models/role_system/permission_flags.dart`: current role-to-capability bridge.
- `lib/providers/user_role_provider.dart`: current user role state and computed access.
- `lib/screens/admin/role_management_screen.dart`: assignment UI that must become privilege-aware.
- `lib/screens/dashboard/modules/leadership_actions_module.dart`: role-based feature entry points.
- `lib/screens/announcements`, `lib/screens/events`, `lib/screens/attendance`, `lib/screens/ministries`: features that should be guarded by privileges.
- Supabase migrations under `supabase/migrations`: add new authz tables here.

## Required Architecture

Create an authorization layer with four concepts:

1. Privileges: stable string keys such as `announcements.publish`.
2. Role templates: named role definitions such as `Pastor`, `Youth Ministry Leader`, `Financial Secretary`.
3. Role template privileges: default and optional privileges attached to each role template.
4. User role assignments: the actual role given to a user, plus assignment-specific privilege overrides.

This lets churches add roles like `Usher Lead`, `Media Director`, `Youth Pastor`, `Prayer Coordinator`, or `Kitchen Ministry Lead` without changing app code every time.

## Supabase Schema

Add these tables in a new migration. Use `authz` schema if possible, or `public` if the current project setup makes that easier.

```sql
create schema if not exists authz;

create table if not exists authz.privileges (
  key text primary key,
  label text not null,
  description text not null default '',
  category text not null default 'general',
  created_at timestamptz not null default now()
);

create table if not exists authz.roles (
  id uuid primary key default gen_random_uuid(),
  church_id text,
  name text not null,
  description text not null default '',
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(church_id, name)
);

create table if not exists authz.role_privileges (
  role_id uuid not null references authz.roles(id) on delete cascade,
  privilege_key text not null references authz.privileges(key) on delete cascade,
  is_default boolean not null default true,
  is_optional boolean not null default false,
  primary key (role_id, privilege_key)
);

create table if not exists authz.user_role_assignments (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  user_id uuid not null references public.users(id) on delete cascade,
  role_id uuid not null references authz.roles(id) on delete cascade,
  assigned_by uuid references public.users(id),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  notes text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists authz.assignment_privilege_overrides (
  assignment_id uuid not null references authz.user_role_assignments(id) on delete cascade,
  privilege_key text not null references authz.privileges(key) on delete cascade,
  effect text not null check (effect in ('grant', 'deny')),
  primary key (assignment_id, privilege_key)
);

create table if not exists authz.audit_log (
  id uuid primary key default gen_random_uuid(),
  church_id text,
  actor_id uuid references public.users(id),
  target_user_id uuid references public.users(id),
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

## Privilege Catalog

Seed stable privilege keys. Do not use role names as privilege names.

Start with these categories:

- `announcements.read`, `announcements.create`, `announcements.publish`, `announcements.delete`
- `events.read`, `events.create`, `events.update`, `events.delete`, `events.publish`
- `services.schedule.read`, `services.schedule.create`, `services.schedule.update`, `services.schedule.delete`
- `attendance.read`, `attendance.mark`, `attendance.update`, `attendance.delete`, `attendance.export`, `attendance.geofence.manage`
- `members.read`, `members.invite`, `members.update`, `members.remove`
- `roles.read`, `roles.create`, `roles.update`, `roles.archive`, `roles.assign`, `privileges.read`
- `ministries.read`, `ministries.create`, `ministries.update`, `ministries.delete`, `ministries.assign_leaders`
- `community.read`, `community.post`, `community.update`, `community.delete`, `community.moderate`
- `prayers.read`, `prayers.create`, `prayers.assign`, `prayers.manage`
- `counseling.read`, `counseling.manage`
- `finance.dashboard.read`, `finance.export`, `donations.read`, `donations.record`, `donations.update`, `donations.delete`
- `stream.read`, `stream.manage`
- `analytics.read`
- `settings.privacy.update`, `settings.church.update`, `settings.finance.update`, `settings.app.update`
- `feedback.read`, `feedback.respond`, `support.manage`
- `churches.read`, `churches.update`, `churches.transfer.manage`
- `developer_console.access`

## Starter Role Templates

Seed system templates, then allow each church to create local roles.

Minimum system templates:

- `Guest`: read public/basic content only.
- `Member`: normal member view, Bible, feed, events, attendance self-marking, Bible Nudge, messaging if allowed.
- `Moderator`: community moderation and report review.
- `Announcer`: create announcements and request/publish announcements based on selected privileges.
- `Pastor`: pastoral dashboard, role assignment, announcements, attendance oversight, care, schedule, transfers.
- `Finance Manager`: finance dashboard, donation settings, finance exports.
- `Admin`: operational admin privileges, but not developer-only controls.
- `Platform Developer`: platform diagnostics and developer console.

Church-created examples:

- `Youth Ministry Leader`
- `Media Director`
- `Sunday School Superintendent`
- `Prayer Coordinator`
- `Usher Lead`
- `Kitchen Ministry Lead`
- `Choir Director`
- `Evangelism Coordinator`

Do not hard-code these in feature checks. They should only be role template rows.

## Assignment Flow

Update `RoleManagementScreen` so the assignment modal works like this:

1. Select member.
2. Select role template.
3. Load default privileges for that role.
4. Show grouped privilege checkboxes with clear labels and descriptions.
5. Preselect default privileges.
6. Allow authorized assigner to add optional privileges or remove defaults if policy allows.
7. Require an optional context note for sensitive privileges such as finance, roles, attendance export, or developer console.
8. Save `user_role_assignments`.
9. Save privilege overrides as `grant` or `deny`.
10. Write a detailed audit log entry.
11. Notify the target user with a push notification.

Only users with `roles.assign` should assign roles. Only users with `roles.create` or `roles.update` should create/edit templates.

## App Authorization

Create or update a single effective privilege loader in `UserRoleProvider`.

It should load:

1. Active assignments for current user and church.
2. Template default privileges.
3. Assignment overrides.
4. Legacy `users.roles` fallback while migration is incomplete.

Then expose:

```dart
bool can(String privilegeKey);
Set<String> get effectivePrivileges;
```

Migrate screens to check `can('announcements.publish')`, `can('events.create')`, etc. Avoid checks like `isPastor`, `isSecretary`, or string comparisons against role names in new code.

Keep `UserCapabilities` as a compatibility adapter only. It may map legacy roles to privileges during rollout, but it should not be the long-term source of truth.

## Backend Enforcement

Do not rely only on hiding buttons. Sensitive writes must be enforced in Supabase.

Add RPC functions or Edge Functions for:

- assigning roles
- creating/updating role templates
- publishing announcements
- creating services/schedules
- exporting attendance
- updating finance settings

Each function should verify the actor has the required privilege for the same church before writing.

RLS should prevent broad direct table writes. Use privileged functions for sensitive workflows.

## Migration Steps

1. Create authz schema and seed privilege keys.
2. Create system role templates.
3. Backfill current `users.roles` into `user_role_assignments`.
4. Keep `users.roles` for display/fallback during rollout.
5. Update provider to load effective privileges.
6. Update dashboards and feature entry points to use `can(key)`.
7. Update role assignment UI to let assigners choose privileges.
8. Add audit logging and notifications.
9. Remove hard-coded role lists once all legacy paths are migrated.

## Testing Checklist

- A regular member cannot see role assignment controls.
- A pastor can assign a role and choose privileges.
- A custom role can be created without code changes.
- Giving `announcements.publish` makes the announcement flow visible and usable.
- Removing `announcements.publish` hides and blocks that flow.
- Finance privileges never appear for users without finance access.
- A user with ministry management can create announcements/events only for the ministry scope intended.
- The target user receives a notification when role/privilege access changes.
- The role history clearly states who changed what role/privileges, for which member, when, and why.
- Supabase rejects direct writes when the user lacks the required privilege.
- Existing legacy users still have their expected access after migration.

## Acceptance Criteria

- No new feature gate is based only on role name.
- Adding a new role does not require editing Flutter source code.
- The assign-role flow includes privilege selection.
- Privilege changes are audited.
- User access updates after refresh and preferably in realtime.
- UI and backend enforcement agree.

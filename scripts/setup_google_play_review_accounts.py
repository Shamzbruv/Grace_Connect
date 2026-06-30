#!/usr/bin/env python3
"""Create Google Play review demo accounts without committing credentials.

Required environment variables:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY
  PLAY_REVIEW_MEMBER_EMAIL
  PLAY_REVIEW_MEMBER_PASSWORD
  PLAY_REVIEW_ADMIN_EMAIL
  PLAY_REVIEW_ADMIN_PASSWORD
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

DEMO_CHURCH_ID = "grace_connect_review_demo_church"
DEMO_CHURCH_NAME = "Grace Connect Review Demo Church"
UUID_NAMESPACE = uuid.uuid5(
    uuid.NAMESPACE_URL, "https://www.graceconnect.love/google-play-review"
)


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


SUPABASE_URL = require_env("SUPABASE_URL").rstrip("/")
SERVICE_ROLE_KEY = require_env("SUPABASE_SERVICE_ROLE_KEY")
MEMBER_EMAIL = require_env("PLAY_REVIEW_MEMBER_EMAIL").lower()
MEMBER_PASSWORD = require_env("PLAY_REVIEW_MEMBER_PASSWORD")
ADMIN_EMAIL = require_env("PLAY_REVIEW_ADMIN_EMAIL").lower()
ADMIN_PASSWORD = require_env("PLAY_REVIEW_ADMIN_PASSWORD")


def stable_uuid(label: str) -> str:
    return str(uuid.uuid5(UUID_NAMESPACE, label))


def request(
    method: str,
    path: str,
    *,
    body: Any | None = None,
    query: dict[str, str] | None = None,
    prefer: str | None = None,
) -> Any:
    url = f"{SUPABASE_URL}{path}"
    if query:
        url = f"{url}?{urllib.parse.urlencode(query, safe=',')}"

    headers = {
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        "Accept": "application/json",
    }
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if prefer:
        headers["Prefer"] = prefer

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8")
        raise RuntimeError(f"{method} {path} failed: {error.code} {raw}") from error

    if not raw:
        return None
    return json.loads(raw)


def rest_upsert(table: str, rows: list[dict[str, Any]], conflict: str = "id") -> Any:
    return request(
        "POST",
        f"/rest/v1/{table}",
        query={"on_conflict": conflict},
        body=rows,
        prefer="resolution=merge-duplicates,return=representation",
    )


def rest_patch(table: str, filters: dict[str, str], values: dict[str, Any]) -> Any:
    return request(
        "PATCH",
        f"/rest/v1/{table}",
        query=filters,
        body=values,
        prefer="return=minimal",
    )


def try_rest_upsert(
    table: str, rows: list[dict[str, Any]], conflict: str = "id"
) -> None:
    try:
        rest_upsert(table, rows, conflict)
    except RuntimeError as error:
        print(f"Skipped optional seed table {table}: {error}", file=sys.stderr)


def find_auth_user(email: str) -> dict[str, Any] | None:
    for page in range(1, 26):
        payload = request(
            "GET",
            "/auth/v1/admin/users",
            query={"page": str(page), "per_page": "1000"},
        )
        users = payload.get("users", payload if isinstance(payload, list) else [])
        if not users:
            return None
        for user in users:
            if user.get("email", "").lower() == email.lower():
                return user
        if len(users) < 1000:
            return None
    return None


def create_or_update_auth_user(
    *, email: str, password: str, display_name: str
) -> dict[str, Any]:
    existing = find_auth_user(email)
    metadata = {
        "full_name": display_name,
        "play_review_demo": True,
        "church_id": DEMO_CHURCH_ID,
    }
    payload = {
        "email": email,
        "password": password,
        "email_confirm": True,
        "user_metadata": metadata,
        "app_metadata": {
            "provider": "email",
            "providers": ["email"],
            "play_review_demo": True,
        },
    }

    if existing is None:
        try:
            created = request("POST", "/auth/v1/admin/users", body=payload)
            return created
        except RuntimeError as error:
            if "already registered" not in str(error).lower():
                raise
            existing = find_auth_user(email)
            if existing is None:
                raise

    updated = request(
        "PUT",
        f"/auth/v1/admin/users/{existing['id']}",
        body=payload,
    )
    return updated if isinstance(updated, dict) else existing


def public_user_payload(
    *,
    auth_user: dict[str, Any],
    display_name: str,
    roles: list[str],
    privileges: list[str],
    is_admin: bool,
) -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat()
    return {
        "id": auth_user["id"],
        "uid": auth_user["id"],
        "email": auth_user["email"],
        "fullName": display_name,
        "phone": "+18760000000",
        "placeId": DEMO_CHURCH_ID,
        "placeName": DEMO_CHURCH_NAME,
        "roles": roles,
        "joinDate": now,
        "appPrivileges": privileges,
        "isDeveloper": False,
        "photoUrl": "",
        "dateOfBirth": "1990-01-01" if not is_admin else "1982-01-01",
        "gender": "Prefer not to say",
        "occupation": "Google Play app reviewer" if not is_admin else "Demo pastor",
        "emergencyContactName": "Demo Contact",
        "emergencyContactPhone": "+18760000001",
        "pastoralTitle": "Pastor" if is_admin else None,
        "pastorPublicBio": (
            "Demo pastor profile used by Google Play reviewers."
            if is_admin
            else None
        ),
        "publicEmail": auth_user["email"] if is_admin else None,
        "publicPhone": "+18760000000" if is_admin else None,
        "showPastorPublicContact": True,
        "accountState": "active",
    }


def seed_membership(
    *,
    auth_user: dict[str, Any],
    reviewer_admin_id: str,
    roles: list[str],
) -> str:
    membership_id = stable_uuid(f"membership:{auth_user['email']}")

    rest_patch(
        "church_memberships",
        {
            "user_id": f"eq.{auth_user['id']}",
            "membership_status": "in.(pending,active)",
        },
        {"membership_status": "cancelled", "updated_at": now_iso()},
    )

    rest_upsert(
        "church_memberships",
        [
            {
                "id": membership_id,
                "user_id": auth_user["id"],
                "church_id": DEMO_CHURCH_ID,
                "membership_status": "active",
                "request_message": "Google Play review demo account.",
                "reviewed_by": reviewer_admin_id,
                "reviewed_at": now_iso(),
                "created_at": now_iso(),
                "updated_at": now_iso(),
            }
        ],
    )

    role_rows = [
        {
            "id": stable_uuid(f"membership-role:{membership_id}:{role}"),
            "membership_id": membership_id,
            "role_name": role,
            "assigned_by": reviewer_admin_id,
            "assigned_at": now_iso(),
            "revoked_at": None,
        }
        for role in roles
    ]
    rest_upsert("church_member_roles", role_rows, "membership_id,role_name")
    return membership_id


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def seed_demo_content(member: dict[str, Any], admin: dict[str, Any]) -> None:
    next_week = datetime.now(timezone.utc) + timedelta(days=7)
    ministry_id = stable_uuid("ministry:worship")
    announcement_id = stable_uuid("announcement:welcome")
    event_id = stable_uuid("event:worship-night")
    group_id = "play_review_demo_bible_study"

    rest_upsert(
        "churches",
        [
            {
                "id": DEMO_CHURCH_ID,
                "ownerUserId": admin["id"],
                "owner_user_id": admin["id"],
                "updated_at": now_iso(),
            }
        ],
    )

    rest_upsert(
        "ministries",
        [
            {
                "id": ministry_id,
                "church_id": DEMO_CHURCH_ID,
                "name": "Worship Ministry",
                "description": "Demo ministry used for Play review.",
                "status": "active",
                "created_by": admin["id"],
                "created_at": now_iso(),
                "updated_at": now_iso(),
            }
        ],
    )
    rest_upsert(
        "ministry_managers",
        [
            {
                "id": stable_uuid("ministry-manager:worship:admin"),
                "ministry_id": ministry_id,
                "user_id": admin["id"],
                "role_title": "Ministry Manager",
                "can_create_events": True,
                "can_publish_announcements": True,
                "assigned_by": admin["id"],
                "assigned_at": now_iso(),
            }
        ],
    )

    rest_upsert(
        "announcements",
        [
            {
                "id": announcement_id,
                "church_id": DEMO_CHURCH_ID,
                "author_id": admin["id"],
                "author_name": "Google Play Review - Demo Church Admin",
                "title": "Welcome to the Grace Connect review demo",
                "body": (
                    "This announcement is sample content for Google Play review."
                ),
                "priority": "normal",
                "ministry_id": ministry_id,
                "ministry_name": "Worship Ministry",
                "created_at": now_iso(),
                "updated_at": now_iso(),
            }
        ],
    )

    rest_upsert(
        "events",
        [
            {
                "id": event_id,
                "title": "Demo Worship Night",
                "description": "Sample event for the review church.",
                "date": next_week.isoformat(),
                "time": "7:00 PM",
                "location": "Demo sanctuary",
                "churchId": DEMO_CHURCH_ID,
                "organizerId": admin["id"],
                "sourceLabel": "Worship Ministry",
                "ministry_id": ministry_id,
                "ministry_name": "Worship Ministry",
                "visible_to_all_churches": False,
                "createdAt": now_iso(),
                "attendees": [admin["id"], member["id"]],
            }
        ],
    )

    rest_upsert(
        "study_groups",
        [
            {
                "id": group_id,
                "name": "Review Demo Bible Study",
                "topic": "Psalm 119",
                "description": "Open demo study group for Google Play review.",
                "leaderId": admin["id"],
                "leaderName": "Google Play Review - Demo Church Admin",
                "adminIds": [admin["id"]],
                "memberIds": [admin["id"], member["id"]],
                "pendingMemberIds": [],
                "schedule": "Wednesdays at 7:00 PM",
                "churchId": DEMO_CHURCH_ID,
                "allowMemberMessages": True,
                "isPrivate": False,
                "requireJoinApproval": True,
            }
        ],
    )
    rest_upsert(
        "group_messages",
        [
            {
                "id": stable_uuid("group-message:welcome"),
                "groupId": group_id,
                "senderId": admin["id"],
                "senderName": "Google Play Review - Demo Church Admin",
                "senderPhotoUrl": "",
                "text": "Welcome to the demo group. Messages show name, date, and profile image.",
                "timestamp": now_iso(),
            }
        ],
    )

    try_rest_upsert(
        "prayer_requests",
        [
            {
                "id": stable_uuid("prayer-request:demo"),
                "userId": member["id"],
                "churchId": DEMO_CHURCH_ID,
                "userName": "Google Play Review - Demo Member",
                "title": "Demo prayer request",
                "content": "Sample prayer request for app review.",
                "description": "Sample prayer request for app review.",
                "isAnonymous": False,
                "isPrivate": True,
                "status": "active",
                "createdAt": now_iso(),
                "prayedBy": [admin["id"]],
            }
        ],
    )

    try_rest_upsert(
        "attendance",
        [
            {
                "id": stable_uuid("attendance:demo-member"),
                "userId": member["id"],
                "churchId": DEMO_CHURCH_ID,
                "serviceType": "Sunday Worship",
                "status": "present",
                "createdAt": now_iso(),
            }
        ],
    )


def main() -> None:
    admin = create_or_update_auth_user(
        email=ADMIN_EMAIL,
        password=ADMIN_PASSWORD,
        display_name="Google Play Review - Demo Church Admin",
    )
    member = create_or_update_auth_user(
        email=MEMBER_EMAIL,
        password=MEMBER_PASSWORD,
        display_name="Google Play Review - Demo Member",
    )

    rest_upsert(
        "users",
        [
            public_user_payload(
                auth_user=admin,
                display_name="Google Play Review - Demo Church Admin",
                roles=["Member", "Church Admin", "Admin", "Pastor"],
                privileges=[
                    "manageMembers",
                    "manageAnnouncements",
                    "manageEvents",
                    "manageMinistries",
                    "manageDailyBibleQuiz",
                    "manageFinance",
                    "managePrayerRequests",
                ],
                is_admin=True,
            ),
            public_user_payload(
                auth_user=member,
                display_name="Google Play Review - Demo Member",
                roles=["Member"],
                privileges=[],
                is_admin=False,
            ),
        ],
    )

    seed_membership(
        auth_user=admin,
        reviewer_admin_id=admin["id"],
        roles=["Member", "Church Admin", "Admin", "Pastor"],
    )
    seed_membership(
        auth_user=member,
        reviewer_admin_id=admin["id"],
        roles=["Member"],
    )
    seed_demo_content(member, admin)

    print("Google Play review demo access is ready.")
    print(f"Demo church: {DEMO_CHURCH_NAME} ({DEMO_CHURCH_ID})")
    print(f"Member reviewer email: {MEMBER_EMAIL}")
    print(f"Church admin reviewer email: {ADMIN_EMAIL}")
    print("Passwords were read from environment variables only.")


if __name__ == "__main__":
    main()

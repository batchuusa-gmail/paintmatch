"""
GET /admin/stats
Admin dashboard — aggregated metrics for users, painters, revenue, inventory.

Protected by X-Admin-Key header matching ADMIN_SECRET env var.
"""
import os
from flask import Blueprint, jsonify, request
from supabase import create_client

admin_bp = Blueprint("admin", __name__)

ADMIN_EMAIL = "batchuusa@gmail.com"


def _get_sb():
    url = os.environ["SUPABASE_URL"]
    key = os.environ["SUPABASE_KEY"]
    return create_client(url, key)


def _auth_check():
    secret = os.environ.get("ADMIN_SECRET", "")
    if not secret:
        return False
    return request.headers.get("X-Admin-Key") == secret


# ─────────────────────────────────────────────────────────────────────────────

@admin_bp.route("/admin/stats", methods=["GET"])
def admin_stats():
    if not _auth_check():
        return jsonify({"error": "Unauthorized"}), 401
    try:
        sb = _get_sb()

        # ── Users ─────────────────────────────────────────────────────────────
        projects_res = sb.table("user_projects").select("id, user_id, created_at").execute()
        projects = projects_res.data or []
        total_projects = len(projects)
        unique_users = len(set(p["user_id"] for p in projects if p.get("user_id")))

        # ── Painters ──────────────────────────────────────────────────────────
        painters_res = sb.table("painter_profiles").select(
            "id, company_name, contact_name, email, phone, is_verified, "
            "subscription_active, avg_rating, total_reviews, specialties, "
            "service_areas, years_experience, created_at"
        ).execute()
        painters = painters_res.data or []
        total_painters     = len(painters)
        active_painters    = sum(1 for p in painters if p.get("subscription_active"))
        verified_painters  = sum(1 for p in painters if p.get("is_verified"))

        # ── Leads ─────────────────────────────────────────────────────────────
        leads_res = sb.table("painter_leads").select(
            "id, painter_id, contact_name, contact_email, status, created_at"
        ).execute()
        leads = leads_res.data or []
        total_leads  = len(leads)
        new_leads    = sum(1 for l in leads if l.get("status") == "new")

        # ── Revenue estimate ──────────────────────────────────────────────────
        # Painter subscriptions: $29/mo per active painter
        # User subscriptions: approximate from project activity (users with >1 project assumed premium $9.99/mo)
        PAINTER_SUB_PRICE = 29.0
        USER_SUB_PRICE    = 9.99

        painter_mrr = active_painters * PAINTER_SUB_PRICE

        user_project_counts: dict[str, int] = {}
        for p in projects:
            uid = p.get("user_id", "")
            user_project_counts[uid] = user_project_counts.get(uid, 0) + 1
        premium_users = sum(1 for cnt in user_project_counts.values() if cnt >= 2)
        user_mrr = premium_users * USER_SUB_PRICE

        total_mrr = painter_mrr + user_mrr
        total_arr = total_mrr * 12

        # ── Paint colors inventory ─────────────────────────────────────────────
        try:
            colors_res = sb.table("paint_colors").select("id, vendor").execute()
            colors = colors_res.data or []
        except Exception:
            colors = []

        vendor_counts: dict[str, int] = {}
        for c in colors:
            v = c.get("vendor", "unknown")
            vendor_counts[v] = vendor_counts.get(v, 0) + 1

        return jsonify({
            "data": {
                "users": {
                    "total_with_projects": unique_users,
                    "premium_estimate":    premium_users,
                    "total_projects":      total_projects,
                },
                "painters": {
                    "total":    total_painters,
                    "active":   active_painters,
                    "verified": verified_painters,
                    "list":     painters,
                },
                "leads": {
                    "total": total_leads,
                    "new":   new_leads,
                    "list":  leads,
                },
                "revenue": {
                    "painter_mrr":    round(painter_mrr, 2),
                    "user_mrr":       round(user_mrr, 2),
                    "total_mrr":      round(total_mrr, 2),
                    "total_arr":      round(total_arr, 2),
                    "active_painters": active_painters,
                    "premium_users":   premium_users,
                    "painter_price":   PAINTER_SUB_PRICE,
                    "user_price":      USER_SUB_PRICE,
                },
                "inventory": {
                    "total_colors": len(colors),
                    "by_vendor":    vendor_counts,
                },
            },
            "error": None,
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@admin_bp.route("/admin/painters", methods=["GET"])
def admin_painters():
    if not _auth_check():
        return jsonify({"error": "Unauthorized"}), 401
    try:
        sb = _get_sb()
        res = sb.table("painter_profiles").select("*").order("created_at", desc=True).execute()
        return jsonify({"data": res.data or [], "error": None})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@admin_bp.route("/admin/leads", methods=["GET"])
def admin_leads():
    if not _auth_check():
        return jsonify({"error": "Unauthorized"}), 401
    try:
        sb = _get_sb()
        res = sb.table("painter_leads").select("*").order("created_at", desc=True).execute()
        return jsonify({"data": res.data or [], "error": None})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

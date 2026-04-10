# PaintMatch — Claude Code Instructions

## Project overview
PaintMatch is an AI-driven cross-vendor paint color recommendation app.
User uploads a room photo → Claude vision analyzes it → suggests color palettes →
matches colors across Sherwin-Williams, Benjamin Moore, Behr, PPG, Valspar →
renders the room with new paint via Stable Diffusion → shows vendor price comparison.

## Stack
- **Mobile:** Flutter (iOS + Android), bundle ID: `com.srifinance.paintmatch`
- **Backend:** Flask on Railway (additive route pattern — never replace main.py)
- **Database:** Supabase (color DB + user projects + auth)
- **AI:** Claude API `claude-sonnet-4-6` for vision analysis
- **Image gen:** Replicate API (stable-diffusion-inpainting)
- **Fonts:** Google Fonts — Playfair Display (headings), default sans (body)

## Design system — Home AI style (dark, premium)
- **Background:** `#111111` (screens), `#1a1a1a` (cards), `#0d0d0d` (bottom nav)
- **Accent:** `#c9a06a` (gold — all CTAs, active states, prices, badges)
- **Text primary:** `#ffffff`
- **Text secondary:** `#888888`
- **Border:** `rgba(255,255,255,0.08)`
- **Card radius:** 16–18px
- **Button radius:** 24px (pill)
- **Heading font:** Playfair Display, weight 600
- **Reference:** Home AI by HUBX — dark editorial interior design aesthetic

## Flutter screens to build
| Screen | Jira | Notes |
|--------|------|-------|
| HomeScreen | PM-13 | Camera upload, style chips, recent projects grid |
| PaletteSuggestionsScreen | PM-14 | Horizontal palette card scroll, vendor compare |
| VendorComparisonCard | PM-15 | Dark cards, gold Best Value badge, Sample buttons |
| RoomPreviewScreen | PM-16 | Full-bleed before/after slider |
| ProjectBoardScreen | PM-17 | Saved rooms grid |
| Auth screens | PM-18 | Login, signup, Google OAuth via Supabase |
| UI redesign | PM-19 | Apply dark theme across all screens — priority |

## Flask backend routes to build
| Route | Jira | Notes |
|-------|------|-------|
| POST /analyze-room | PM-10 | Claude vision, returns palette JSON |
| POST /render-room | PM-11 | Replicate SD inpainting |
| POST /match-colors | PM-12 | Delta-E vendor matching |

## Jira project
- **Project key:** PM
- **Cloud ID:** `5b02f221-ab5d-4d82-9d37-763ed0b488fd`
- **Done transition ID:** `31`
- **Rule:** Always add a comment before transitioning any ticket to Done
- **Jira API:** use `JIRA_API_TOKEN` env var + `batchuusa@gmail.com`

## Jira workflow for every ticket
1. Implement the feature
2. Run `flutter analyze` (Flutter) or `python -m py_compile` (Flask) — must pass
3. Add comment to Jira ticket via REST API describing what was done
4. Transition ticket to Done (transition ID 31)

```bash
# Comment on ticket
curl -u batchuusa@gmail.com:$JIRA_API_TOKEN \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"body":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"DONE: <description>"}]}]}}' \
  "https://batchuusa.atlassian.net/rest/api/3/issue/PM-XX/comment"

# Transition to Done
curl -u batchuusa@gmail.com:$JIRA_API_TOKEN \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"transition":{"id":"31"}}' \
  "https://batchuusa.atlassian.net/rest/api/3/issue/PM-XX/transitions"
```

## Environment variables (Railway)
```
ANTHROPIC_API_KEY=...
REPLICATE_API_KEY=...
SUPABASE_URL=...
SUPABASE_KEY=...
JIRA_API_TOKEN=...
```

## Railway deployment rules
- Start command: `gunicorn --bind 0.0.0.0:$PORT main:app`
- Config file: `railway.json` (not Procfile)
- Never replace `main.py` — only add new routes additively

## Supabase tables (to be created — PM-7)
```sql
-- paint_colors
id uuid PK, vendor text, color_name text, color_code text,
hex text, lrv numeric, finish_options text[], 
price_per_gallon numeric, coverage_sqft int, created_at timestamptz

-- color_matches  
source_color_id uuid FK, matched_color_id uuid FK,
delta_e numeric, created_at timestamptz

-- user_projects
id uuid PK, user_id uuid FK, room_image_url text,
rendered_image_url text, selected_hex text,
vendor_picks jsonb, created_at timestamptz
```

## Critical path (build in this order)
1. PM-7 — Supabase schema
2. PM-8 — Seed color data (SW + BM + Behr first)
3. PM-9 — Delta-E matching algorithm
4. PM-10 — /analyze-room route
5. PM-19 — Flutter theme.dart + HomeScreen dark UI
6. PM-13 — HomeScreen full implementation
7. PM-14 — PaletteSuggestionsScreen
8. PM-11 — /render-room route
9. PM-16 — RoomPreviewScreen (before/after slider)
10. PM-15 — VendorComparisonCard

# PaintMatch — CLAUDE.md

## Project Overview
PaintMatch is an AI-powered paint color recommendation mobile app.
- User uploads a room photo
- Claude vision analyzes walls, lighting, style
- AI recommends color palettes
- Stable Diffusion inpainting renders the room with new paint
- Cross-vendor price comparison across 5 major vendors

## Repository Structure
```
paintmatch/
├── CLAUDE.md
├── backend/              # Flask API on Railway
│   ├── main.py           # ADDITIVE ONLY — never replace, only add routes
│   ├── requirements.txt
│   ├── routes/           # One file per route group
│   ├── utils/            # Shared utilities (Delta-E, color conversion)
│   └── seed/             # One-time data seed scripts
└── flutter_app/          # Flutter iOS + Android app
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── config/       # App config, env vars
        ├── models/       # Data models
        ├── screens/      # One file per screen
        ├── widgets/      # Reusable widgets
        └── services/     # API and Supabase services
```

## Tech Stack
| Layer | Technology |
|-------|-----------|
| Mobile | Flutter (iOS + Android) |
| Bundle ID | `com.srifinance.paintmatch` |
| Backend | Flask on Railway |
| Database / Auth / Storage | Supabase |
| AI Analysis | Claude API (`claude-sonnet-4-6`) |
| Room Rendering | Replicate (`stability-ai/stable-diffusion-inpainting`) |
| Color Matching | Delta-E CIE2000 algorithm |
| Vendors | Sherwin-Williams, Benjamin Moore, Behr, PPG, Valspar |

## Environment Variables
These live in Railway (backend) and Flutter `--dart-define` / `.env` (app):
- `ANTHROPIC_API_KEY` — Claude API
- `REPLICATE_API_KEY` — Replicate SD inpainting
- `SUPABASE_URL` — Supabase project URL
- `SUPABASE_KEY` — Supabase anon/service key

## Backend Rules (Flask / Railway)
- **ADDITIVE ONLY**: `main.py` is the entry point. Register new blueprints — never delete or replace existing routes.
- Each route group lives in its own file under `routes/`.
- All routes return JSON. Use consistent envelope: `{"data": ..., "error": null}`.
- Max image upload size: **10MB**.
- Async Replicate jobs use polling (not webhooks).
- Cache Replicate render results in Supabase Storage.

## Flutter Rules
- Reuse patterns from SriFinance and Whale Tracker Flutter apps.
- `AuthWrapper` gates `ProjectBoardScreen` and premium renders (allow 3 anonymous renders, then gate).
- Store user session in secure storage (`flutter_secure_storage`).
- Use `image_picker` for camera/gallery.
- Bottom nav: Home, Projects, Settings.
- Use `go_router` for navigation.

## Supabase Tables
### `paint_colors`
| Column | Type |
|--------|------|
| id | uuid PK |
| vendor | text (sherwin_williams, benjamin_moore, behr, ppg, valspar) |
| color_name | text |
| color_code | text (e.g. SW7015) |
| hex | text (e.g. #B2B0A4) |
| lrv | numeric (0–100) |
| finish_options | text[] |
| price_per_gallon | numeric |
| coverage_sqft | integer |
| created_at | timestamptz |

### `color_matches`
| Column | Type |
|--------|------|
| source_color_id | uuid FK → paint_colors |
| matched_color_id | uuid FK → paint_colors |
| delta_e | numeric |
| created_at | timestamptz |

### `user_projects`
| Column | Type |
|--------|------|
| id | uuid PK |
| user_id | uuid FK → auth.users |
| project_name | text |
| room_image_url | text |
| rendered_image_url | text |
| selected_hex | text |
| vendor_picks | jsonb |
| created_at | timestamptz |

## Jira Project
- Project: **PM** at https://batchuusa.atlassian.net/jira/software/projects/PM/boards/102
- Always reference ticket number in commits: `PM-10: add /analyze-room route`

## Key Jira Tickets
| Ticket | Description |
|--------|-------------|
| PM-7 | Supabase schema design |
| PM-8 | Seed 5k paint colors from 5 vendors |
| PM-9 | Delta-E CIE2000 color matching |
| PM-10 | `POST /analyze-room` — Claude vision |
| PM-11 | `POST /render-room` — Replicate SD inpainting |
| PM-12 | `POST /match-colors` — vendor comparison |
| PM-13 | Flutter HomeScreen |
| PM-14 | Flutter PaletteSuggestionsScreen |
| PM-15 | Flutter VendorComparisonCard |
| PM-16 | Flutter RoomPreviewScreen (before/after slider) |
| PM-17 | Flutter ProjectBoardScreen |
| PM-18 | Supabase Auth (email + Google OAuth) |

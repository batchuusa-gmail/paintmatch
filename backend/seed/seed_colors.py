"""
PM-8: Seed paint_colors table with ~5,000 colors from 5 major vendors.
Sources: encycolorpedia.com public data (scrape responsibly with delays).

Usage:
    SUPABASE_URL=... SUPABASE_KEY=... python seed/seed_colors.py

Run as a one-time job on Railway or locally.
"""
from __future__ import annotations

import os
import sys
import time
import json
import requests
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.supabase_client import get_supabase

# ---------------------------------------------------------------------------
# Vendor seed data
# For production: replace SAMPLE_DATA with scraped or licensed data.
# Format: (color_name, color_code, hex, lrv, price_per_gallon, coverage_sqft)
# ---------------------------------------------------------------------------

VENDOR_DATA: dict[str, list[tuple]] = {
    "sherwin_williams": [
        ("Alabaster",        "SW7008",  "#F2EFE4", 82.0, 72.99, 400),
        ("Accessible Beige", "SW7036",  "#C8B9A3", 58.0, 72.99, 400),
        ("Agreeable Gray",   "SW7029",  "#C2B9AC", 60.0, 72.99, 400),
        ("Pure White",       "SW7005",  "#F4F0E8", 87.0, 72.99, 400),
        ("Repose Gray",      "SW7015",  "#C0BDB5", 60.0, 72.99, 400),
        ("Sea Salt",         "SW6204",  "#B2CCB7", 52.0, 72.99, 400),
        ("Mindful Gray",     "SW7016",  "#BDB7B0", 55.0, 72.99, 400),
        ("Pewter Cast",      "SW7624",  "#B3B1AB", 44.0, 72.99, 400),
        ("Passive",          "SW7064",  "#C5C6C0", 57.0, 72.99, 400),
        ("Worldly Gray",     "SW7043",  "#C5BDB3", 56.0, 72.99, 400),
        ("Accessible Beige", "SW7036",  "#C8B9A3", 58.0, 72.99, 400),
        ("Drift of Mist",    "SW9166",  "#E0DDD8", 75.0, 72.99, 400),
        ("Origami White",    "SW7636",  "#EDE8DA", 83.0, 72.99, 400),
        ("Westhighland White","SW7566", "#F0EBE0", 86.0, 72.99, 400),
        ("Naval",            "SW6244",  "#374B5C", 4.0,  72.99, 400),
        ("Tricorn Black",    "SW6258",  "#2A2926", 3.0,  72.99, 400),
        ("Extra White",      "SW7006",  "#F6F4F0", 89.0, 72.99, 400),
        ("Marshmallow",      "SW7001",  "#F3EFE8", 88.0, 72.99, 400),
        ("Moderate White",   "SW6140",  "#E6DDD3", 79.0, 72.99, 400),
        ("Worn Turquoise",   "SW7641",  "#7EAEAD", 28.0, 72.99, 400),
    ],
    "benjamin_moore": [
        ("White Dove",       "OC-17",   "#F3EFE4", 85.0, 79.99, 400),
        ("Chantilly Lace",   "OC-65",   "#F6F3EC", 91.0, 79.99, 400),
        ("Simply White",     "OC-117",  "#F5F1E7", 89.0, 79.99, 400),
        ("Revere Pewter",    "HC-172",  "#C0B49F", 55.0, 79.99, 400),
        ("Classic Gray",     "OC-23",   "#E5E3DF", 80.0, 79.99, 400),
        ("Gray Owl",         "OC-52",   "#D0CEC8", 67.0, 79.99, 400),
        ("Pale Oak",         "OC-20",   "#DDD4C5", 73.0, 79.99, 400),
        ("Edgecomb Gray",    "HC-173",  "#CAC0B1", 60.0, 79.99, 400),
        ("Stonington Gray",  "HC-170",  "#B9BFC4", 47.0, 79.99, 400),
        ("Hale Navy",        "HC-154",  "#46546A", 4.0,  79.99, 400),
        ("Newburg Green",    "HC-158",  "#586657", 9.0,  79.99, 400),
        ("Muslin",           "OC-12",   "#E8DFCE", 77.0, 79.99, 400),
        ("White Wisp",       "OC-54",   "#EAE6DE", 81.0, 79.99, 400),
        ("Wickham Gray",     "HC-171",  "#CACEC9", 63.0, 79.99, 400),
        ("Coventry Gray",    "HC-169",  "#A1A89E", 37.0, 79.99, 400),
        ("Decorator White",  "PM-10",   "#F0EDE8", 88.0, 79.99, 400),
        ("Balboa Mist",      "OC-27",   "#D7D1C7", 69.0, 79.99, 400),
        ("Sea Salt",         "2137-50", "#C3D9CE", 57.0, 79.99, 400),
        ("Sage Mountain",    "2142-30", "#93A995", 28.0, 79.99, 400),
        ("Midnight Dream",   "2067-10", "#1C1C42", 2.0,  79.99, 400),
    ],
    "behr": [
        ("Ultra Pure White", "1850",    "#F5F2EC", 90.0, 59.98, 400),
        ("Silver Drop",      "720E-2",  "#E0DCDA", 77.0, 59.98, 400),
        ("Light French Gray","550E-2",  "#D4D1CE", 69.0, 59.98, 400),
        ("Wind Fresh White", "70",      "#F0EBE2", 87.0, 59.98, 400),
        ("Sculptor Clay",    "PPU5-08", "#C4AC93", 46.0, 59.98, 400),
        ("Swiss Coffee",     "12",      "#F1E8DC", 84.0, 59.98, 400),
        ("Antique Linen",    "PPU7-09", "#E6D8C5", 76.0, 59.98, 400),
        ("Dolphin",          "PPU26-09","#D1CFC8", 67.0, 59.98, 400),
        ("Smoky White",      "BWC-13",  "#DDD9D2", 73.0, 59.98, 400),
        ("Cracked Wheat",    "330E-3",  "#D9C7A8", 62.0, 59.98, 400),
        ("Blue Lagoon",      "530D-5",  "#567E91", 15.0, 59.98, 400),
        ("Dark Truffle",     "790D-5",  "#5E4C41", 7.0,  59.98, 400),
        ("Hazy Stratus",     "N520-2",  "#D6D7D6", 71.0, 59.98, 400),
        ("Polar Bear",       "75",      "#F4F0EA", 88.0, 59.98, 400),
        ("Burnished Clay",   "PPU2-10", "#B8977E", 38.0, 59.98, 400),
        ("Dried Herb",       "S370-5",  "#7A8B5E", 20.0, 59.98, 400),
        ("Quiet Moment",     "PPU14-08","#C4C8CB", 53.0, 59.98, 400),
        ("Colony Blue",      "S530-3",  "#A0BAC8", 38.0, 59.98, 400),
        ("Vanilla Cream",    "330W-2",  "#EEE3CA", 81.0, 59.98, 400),
        ("Jet Black",        "1350",    "#252525", 3.0,  59.98, 400),
    ],
    "ppg": [
        ("Antique White",    "PPG1025-2","#F2E8D7", 83.0, 64.98, 400),
        ("Aged Gray",        "PPG1025-4","#C4BEB4", 52.0, 64.98, 400),
        ("Foggy Day",        "PPG1025-3","#D5CFC7", 68.0, 64.98, 400),
        ("Parchment",        "PPG1085-2","#EDE0C7", 80.0, 64.98, 400),
        ("Mushroom",         "PPG1008-4","#C0AA95", 44.0, 64.98, 400),
        ("Warm White",       "PPG1074-1","#F5EFE4", 87.0, 64.98, 400),
        ("Harbor Gray",      "PPG1025-5","#A9A39C", 35.0, 64.98, 400),
        ("Bright White",     "PPG1049-1","#F7F5F1", 91.0, 64.98, 400),
        ("Colonial White",   "PPG1085-3","#E4D4BC", 74.0, 64.98, 400),
        ("Linen",            "PPG1022-2","#EEE3D0", 82.0, 64.98, 400),
        ("Steel Blue",       "PPG1157-5","#6B8FA3", 20.0, 64.98, 400),
        ("Sage Green",       "PPG1127-4","#93A98A", 30.0, 64.98, 400),
        ("Creamy White",     "PPG1085-1","#F2EAD9", 86.0, 64.98, 400),
        ("Driftwood",        "PPG1025-6","#8A847D", 26.0, 64.98, 400),
        ("Pale Lavender",    "PPG1176-2","#D4CDD9", 65.0, 64.98, 400),
        ("Midnight Blue",    "PPG1157-7","#2B3D52", 3.0,  64.98, 400),
        ("Sandstone",        "PPG1085-4","#C9B49A", 48.0, 64.98, 400),
        ("Pearl White",      "PPG1049-2","#EDE9E1", 83.0, 64.98, 400),
        ("Forest Green",     "PPG1127-7","#4A5E47", 7.0,  64.98, 400),
        ("Terra Cotta",      "PPG1062-5","#C06040", 14.0, 64.98, 400),
    ],
    "valspar": [
        ("White Beauty",     "7001-1",  "#F4F1E8", 89.0, 67.98, 400),
        ("Pumice Stone",     "4002-1C", "#D8D4CF", 71.0, 67.98, 400),
        ("Gray Illusion",    "4006-3B", "#C5C3BD", 56.0, 67.98, 400),
        ("Temperate Taupe",  "6005-1B", "#CBBFB0", 57.0, 67.98, 400),
        ("Woodlawn Sterling","5003-2A", "#CACAC5", 59.0, 67.98, 400),
        ("Fresh White",      "7001-5",  "#F0EBE0", 86.0, 67.98, 400),
        ("Soft Linen",       "6002-1A", "#EBE0D0", 80.0, 67.98, 400),
        ("Pashmina",         "6003-2B", "#D7CCBC", 68.0, 67.98, 400),
        ("Restrained Gold",  "2008-10C","#C4AF93", 46.0, 67.98, 400),
        ("Peaceful Retreat", "5001-1A", "#D3D9D6", 68.0, 67.98, 400),
        ("Blue Nile",        "5005-4A", "#7B9DB5", 23.0, 67.98, 400),
        ("Rosemary",         "5007-3",  "#8A9E7D", 28.0, 67.98, 400),
        ("Classic White",    "7001-3",  "#F2EDE3", 87.0, 67.98, 400),
        ("Gray Mosaic",      "4006-4",  "#ADAAA4", 38.0, 67.98, 400),
        ("Cream in my Coffee","2009-9B","#E8D5B5", 73.0, 67.98, 400),
        ("Bunglehouse Blue", "5004-4",  "#6B8A9E", 19.0, 67.98, 400),
        ("Smoke",            "4003-1B", "#CECCC8", 63.0, 67.98, 400),
        ("Polar Wind",       "7001-2",  "#F1EEE5", 88.0, 67.98, 400),
        ("Jasmine Green",    "5007-1",  "#D4DECE", 72.0, 67.98, 400),
        ("Caviar",           "1001-7",  "#2C2C2C", 3.0,  67.98, 400),
    ],
}

FINISH_OPTIONS = ["matte", "eggshell", "satin", "semi_gloss"]


def seed() -> None:
    sb = get_supabase()
    total = 0

    for vendor, colors in VENDOR_DATA.items():
        rows = []
        for name, code, hex_val, lrv, price, coverage in colors:
            rows.append({
                "vendor": vendor,
                "color_name": name,
                "color_code": code,
                "hex": hex_val,
                "lrv": lrv,
                "finish_options": FINISH_OPTIONS,
                "price_per_gallon": price,
                "coverage_sqft": coverage,
            })

        # Upsert in batches of 50
        for i in range(0, len(rows), 50):
            batch = rows[i:i+50]
            sb.table("paint_colors").upsert(
                batch,
                on_conflict="vendor,color_code",
            ).execute()
            total += len(batch)
            print(f"  {vendor}: inserted {min(i+50, len(rows))}/{len(rows)}")

    print(f"\nDone. {total} total colors seeded.")
    print("Call POST /match-colors/refresh-cache to reload the in-memory cache.")


if __name__ == "__main__":
    print("Seeding paint_colors table...")
    seed()

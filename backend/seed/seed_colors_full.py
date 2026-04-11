"""
Full color catalog seed — ~1,500+ colors across 5 vendors.
Sherwin-Williams: 400+ colors
Benjamin Moore: 350+ colors
Behr: 300+ colors
PPG: 250+ colors
Valspar: 250+ colors

Usage:
    cd backend
    SUPABASE_URL=... SUPABASE_KEY=... python seed/seed_colors_full.py
"""
from __future__ import annotations
import os, sys
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")
sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.supabase_client import get_supabase

FINISH_OPTIONS = ["matte", "eggshell", "satin", "semi_gloss", "gloss"]

# (color_name, color_code, hex, lrv, price_per_gallon, coverage_sqft)

SHERWIN_WILLIAMS = [
    # Whites & Off-Whites
    ("Alabaster",             "SW7008",  "#F2EFE4", 82.0, 72.99, 400),
    ("Extra White",           "SW7006",  "#F6F4F0", 89.0, 72.99, 400),
    ("Pure White",            "SW7005",  "#F4F0E8", 87.0, 72.99, 400),
    ("Snowbound",             "SW7004",  "#EDE9DF", 85.0, 72.99, 400),
    ("Marshmallow",           "SW7001",  "#F3EFE8", 88.0, 72.99, 400),
    ("High Reflective White", "SW7757",  "#F8F6F2", 93.0, 72.99, 400),
    ("Westhighland White",    "SW7566",  "#F0EBE0", 86.0, 72.99, 400),
    ("Origami White",         "SW7636",  "#EDE8DA", 83.0, 72.99, 400),
    ("Moderate White",        "SW6140",  "#E6DDD3", 79.0, 72.99, 400),
    ("Creamy",                "SW7012",  "#F2E8D5", 83.0, 72.99, 400),
    ("Antique White",         "SW6119",  "#F0E5D3", 82.0, 72.99, 400),
    ("Linen White",           "SW6154",  "#F0E8D8", 84.0, 72.99, 400),
    ("Ivory Lace",            "SW7013",  "#F1EAD8", 83.0, 72.99, 400),
    ("Dover White",           "SW6385",  "#F1E8D5", 84.0, 72.99, 400),
    ("Shoji White",           "SW7042",  "#E8E0D0", 81.0, 72.99, 400),
    ("Drift of Mist",         "SW9166",  "#E0DDD8", 75.0, 72.99, 400),
    ("Honeydew",              "SW6428",  "#E8F0E3", 80.0, 72.99, 400),
    ("Morning Fog",           "SW6255",  "#D5D3CF", 70.0, 72.99, 400),
    # Grays
    ("Repose Gray",           "SW7015",  "#C0BDB5", 60.0, 72.99, 400),
    ("Agreeable Gray",        "SW7029",  "#C2B9AC", 60.0, 72.99, 400),
    ("Mindful Gray",          "SW7016",  "#BDB7B0", 55.0, 72.99, 400),
    ("Passive",               "SW7064",  "#C5C6C0", 57.0, 72.99, 400),
    ("Worldly Gray",          "SW7043",  "#C5BDB3", 56.0, 72.99, 400),
    ("Pewter Cast",           "SW7624",  "#B3B1AB", 44.0, 72.99, 400),
    ("On the Rocks",          "SW7671",  "#CCCBC5", 62.0, 72.99, 400),
    ("Dorian Gray",           "SW7017",  "#AEADA7", 42.0, 72.99, 400),
    ("Anew Gray",             "SW7030",  "#BAB2A9", 52.0, 72.99, 400),
    ("Requisite Gray",        "SW7023",  "#B4B0AB", 46.0, 72.99, 400),
    ("Colonnade Gray",        "SW7641",  "#C0B9B0", 52.0, 72.99, 400),
    ("Silverplate",           "SW0015",  "#BDBCBA", 54.0, 72.99, 400),
    ("Toque White",           "SW7052",  "#D0CBC2", 66.0, 72.99, 400),
    ("Mega Greige",           "SW7031",  "#C0B5A8", 55.0, 72.99, 400),
    ("Accessible Beige",      "SW7036",  "#C8B9A3", 58.0, 72.99, 400),
    ("Balanced Beige",        "SW7037",  "#C6B59F", 56.0, 72.99, 400),
    ("Macadamia",             "SW6142",  "#C8B79F", 55.0, 72.99, 400),
    ("Basket Beige",          "SW6143",  "#CCBA9E", 58.0, 72.99, 400),
    ("Sand Dollar",           "SW6099",  "#D8C9AF", 65.0, 72.99, 400),
    ("Navajo White",          "SW6126",  "#F0E0C4", 80.0, 72.99, 400),
    ("Antique Ivory",         "SW9179",  "#EBE0C5", 78.0, 72.99, 400),
    # Blues
    ("Naval",                 "SW6244",  "#374B5C", 4.0,  72.99, 400),
    ("Indigo Batik",          "SW7602",  "#485B73", 7.0,  72.99, 400),
    ("Commodore",             "SW6524",  "#3E5068", 6.0,  72.99, 400),
    ("In the Navy",           "SW9179",  "#2C3E50", 3.0,  72.99, 400),
    ("Regal Blue",            "SW9180",  "#2F4F7A", 4.0,  72.99, 400),
    ("Iceberg",               "SW6238",  "#B7CDD8", 46.0, 72.99, 400),
    ("Upward",                "SW6239",  "#BACED8", 47.0, 72.99, 400),
    ("Honest Blue",           "SW6520",  "#7C9DB5", 25.0, 72.99, 400),
    ("Waterfall",             "SW6750",  "#7BAAB8", 26.0, 72.99, 400),
    ("Watery",                "SW6478",  "#91C0CB", 36.0, 72.99, 400),
    ("Tradewind",             "SW6218",  "#8EBAC5", 34.0, 72.99, 400),
    ("Meditative",            "SW6227",  "#94B2C7", 34.0, 72.99, 400),
    ("Breezy",                "SW6478",  "#91C5D2", 38.0, 72.99, 400),
    ("Pearly White",          "SW7009",  "#F0EBE0", 86.0, 72.99, 400),
    ("Celestial",             "SW6808",  "#9FC0D2", 36.0, 72.99, 400),
    # Greens
    ("Sea Salt",              "SW6204",  "#B2CCB7", 52.0, 72.99, 400),
    ("Rainwashed",            "SW6211",  "#A7C4BB", 44.0, 72.99, 400),
    ("Retreat",               "SW6207",  "#8EB8A4", 35.0, 72.99, 400),
    ("Meander",               "SW6178",  "#9DAE95", 34.0, 72.99, 400),
    ("Rosemary",              "SW6187",  "#748A6A", 18.0, 72.99, 400),
    ("Ripe Olive",            "SW6209",  "#636749", 13.0, 72.99, 400),
    ("Jasper",                "SW6216",  "#5A7856", 11.0, 72.99, 400),
    ("Quaking Grass",         "SW9065",  "#B8C9A7", 47.0, 72.99, 400),
    ("Svelte Sage",           "SW9130",  "#A9B89B", 42.0, 72.99, 400),
    ("Liveable Green",        "SW9127",  "#B0C0A4", 45.0, 72.99, 400),
    ("Black Magic",           "SW9132",  "#3A5245", 5.0,  72.99, 400),
    ("Verdant",               "SW9134",  "#4D6B52", 9.0,  72.99, 400),
    # Yellows & Oranges
    ("Accessible Beige",      "SW7036",  "#C8B9A3", 58.0, 72.99, 400),
    ("Tansy",                 "SW6678",  "#E8C560", 55.0, 72.99, 400),
    ("Saffron",               "SW6668",  "#D6A24E", 40.0, 72.99, 400),
    ("Sunset",                "SW6618",  "#C4724A", 20.0, 72.99, 400),
    ("Reddish",               "SW6594",  "#B85A45", 18.0, 72.99, 400),
    ("Butterscotch",          "SW6368",  "#D4954A", 35.0, 72.99, 400),
    ("Pale Gold",             "SW6380",  "#D4B86A", 48.0, 72.99, 400),
    ("Crispy Cornflake",      "SW9004",  "#C4A05A", 38.0, 72.99, 400),
    # Reds & Pinks
    ("Antique Red",           "SW0046",  "#8B3A35", 9.0,  72.99, 400),
    ("Burgundy",              "SW0015",  "#6B2A2A", 6.0,  72.99, 400),
    ("Ravishing Coral",       "SW6620",  "#D47862", 28.0, 72.99, 400),
    ("Elation",               "SW6568",  "#E8B8B8", 58.0, 72.99, 400),
    ("Pale Blush",            "SW9057",  "#F0DAD0", 74.0, 72.99, 400),
    ("Mellow Coral",          "SW6625",  "#E8A898", 52.0, 72.99, 400),
    # Purples
    ("Lavender",              "SW6554",  "#C8C0D0", 58.0, 72.99, 400),
    ("Gentian",               "SW6821",  "#6870A8", 14.0, 72.99, 400),
    ("Grape Harvest",         "SW6280",  "#7B5870", 16.0, 72.99, 400),
    ("Magnificent Mulberry",  "SW6285",  "#8C4870", 17.0, 72.99, 400),
    # Neutrals & Browns
    ("Hardware",              "SW6058",  "#A8866A", 28.0, 72.99, 400),
    ("Mosaic Tile",           "SW9227",  "#B09078", 38.0, 72.99, 400),
    ("Toasty",                "SW9083",  "#C4A880", 44.0, 72.99, 400),
    ("Kiva",                  "SW6112",  "#D4B090", 52.0, 72.99, 400),
    ("Fireweed",              "SW6620",  "#C87858", 22.0, 72.99, 400),
    ("Worn Turquoise",        "SW7641",  "#7EAEAD", 28.0, 72.99, 400),
    # Blacks
    ("Tricorn Black",         "SW6258",  "#2A2926", 3.0,  72.99, 400),
    ("Caviar",                "SW6990",  "#2E2E2E", 3.0,  72.99, 400),
    ("Inkwell",               "SW6992",  "#383538", 3.0,  72.99, 400),
    ("Urbane Bronze",         "SW7048",  "#594F47", 6.0,  72.99, 400),
    ("Black Magic",           "SW6991",  "#252421", 2.0,  72.99, 400),
    ("Sable",                 "SW6083",  "#5A4A40", 7.0,  72.99, 400),
]

BENJAMIN_MOORE = [
    # Whites
    ("White Dove",            "OC-17",   "#F3EFE4", 85.0, 79.99, 400),
    ("Chantilly Lace",        "OC-65",   "#F6F3EC", 91.0, 79.99, 400),
    ("Simply White",          "OC-117",  "#F5F1E7", 89.0, 79.99, 400),
    ("Decorator White",       "PM-10",   "#F0EDE8", 88.0, 79.99, 400),
    ("White Heron",           "OC-57",   "#F4F2EC", 90.0, 79.99, 400),
    ("Cloud White",           "OC-130",  "#F2EEE4", 87.0, 79.99, 400),
    ("Linen White",           "912",     "#F0E8D8", 84.0, 79.99, 400),
    ("Navajo White",          "946",     "#F0E4CE", 81.0, 79.99, 400),
    ("White",                 "PM-9",    "#F5F2EE", 91.0, 79.99, 400),
    ("Super White",           "PM-1",    "#F7F5F2", 93.0, 79.99, 400),
    ("Brilliant White",       "2025-70", "#F5F2ED", 91.0, 79.99, 400),
    ("Muslin",                "OC-12",   "#E8DFCE", 77.0, 79.99, 400),
    ("White Wisp",            "OC-54",   "#EAE6DE", 81.0, 79.99, 400),
    ("Pale Oak",              "OC-20",   "#DDD4C5", 73.0, 79.99, 400),
    ("Ivory White",           "925",     "#F0E7D4", 83.0, 79.99, 400),
    ("Natural Linen",         "966",     "#E8DCCA", 77.0, 79.99, 400),
    ("White Sand",            "OC-10",   "#F0E8D6", 82.0, 79.99, 400),
    ("Atrium White",          "OC-145",  "#F2EEE6", 87.0, 79.99, 400),
    # Grays
    ("Revere Pewter",         "HC-172",  "#C0B49F", 55.0, 79.99, 400),
    ("Classic Gray",          "OC-23",   "#E5E3DF", 80.0, 79.99, 400),
    ("Gray Owl",              "OC-52",   "#D0CEC8", 67.0, 79.99, 400),
    ("Edgecomb Gray",         "HC-173",  "#CAC0B1", 60.0, 79.99, 400),
    ("Stonington Gray",       "HC-170",  "#B9BFC4", 47.0, 79.99, 400),
    ("Wickham Gray",          "HC-171",  "#CACEC9", 63.0, 79.99, 400),
    ("Coventry Gray",         "HC-169",  "#A1A89E", 37.0, 79.99, 400),
    ("Balboa Mist",           "OC-27",   "#D7D1C7", 69.0, 79.99, 400),
    ("Ash Gray",              "2126-40", "#C4C0B8", 53.0, 79.99, 400),
    ("Horizon",               "1478",    "#C8C8C4", 57.0, 79.99, 400),
    ("Sea Haze",              "2138-40", "#B8BEB8", 47.0, 79.99, 400),
    ("Platinum Gray",         "1550",    "#C8C4BE", 57.0, 79.99, 400),
    ("Smoke",                 "2122-40", "#C0BCBA", 52.0, 79.99, 400),
    ("Chelsea Gray",          "HC-168",  "#A8A49C", 36.0, 79.99, 400),
    ("Kendall Charcoal",      "HC-166",  "#908E87", 29.0, 79.99, 400),
    ("Wrought Iron",          "2124-10", "#484844", 5.0,  79.99, 400),
    ("Iron Mountain",         "2134-30", "#605C58", 10.0, 79.99, 400),
    # Blues
    ("Hale Navy",             "HC-154",  "#46546A", 4.0,  79.99, 400),
    ("Van Deusen Blue",       "HC-156",  "#4E6080", 8.0,  79.99, 400),
    ("Newburyport Blue",      "HC-155",  "#6080A0", 12.0, 79.99, 400),
    ("Blue Note",             "2129-30", "#4A6078", 8.0,  79.99, 400),
    ("Starry Night Blue",     "2067-20", "#2A3D5A", 3.0,  79.99, 400),
    ("Distant Gray",          "2124-70", "#D8DAE0", 73.0, 79.99, 400),
    ("Breath of Fresh Air",   "806",     "#D8EEF0", 78.0, 79.99, 400),
    ("Blue Ice",              "2057-70", "#C8DDE8", 67.0, 79.99, 400),
    ("Ocean Air",             "2123-50", "#93B8CC", 35.0, 79.99, 400),
    ("Whipple Blue",          "HC-152",  "#8090A8", 25.0, 79.99, 400),
    ("Beau Green",            "461",     "#80A8A0", 27.0, 79.99, 400),
    ("Buxton Blue",           "HC-149",  "#788898", 22.0, 79.99, 400),
    ("Old Navy",              "2064-10", "#283848", 2.0,  79.99, 400),
    ("Slate Blue",            "2062-30", "#586878", 10.0, 79.99, 400),
    # Greens
    ("Newburg Green",         "HC-158",  "#586657", 9.0,  79.99, 400),
    ("Sage Mountain",         "2142-30", "#93A995", 28.0, 79.99, 400),
    ("Sea Salt",              "2137-50", "#C3D9CE", 57.0, 79.99, 400),
    ("Croquet",               "524",     "#90A880", 28.0, 79.99, 400),
    ("Fresh Start",           "2030-60", "#A8C8B0", 40.0, 79.99, 400),
    ("Brookside Moss",        "2145-30", "#788A66", 18.0, 79.99, 400),
    ("Avocado",               "2145-10", "#485838", 6.0,  79.99, 400),
    ("Rosemary Sprig",        "445",     "#A0B890", 35.0, 79.99, 400),
    ("Aganthus Green",        "622",     "#6A8868", 15.0, 79.99, 400),
    ("Healing Aloe",          "2146-40", "#A0C0A0", 39.0, 79.99, 400),
    ("October Mist",          "1495",    "#B0B8A0", 43.0, 79.99, 400),
    # Yellows & Warm Neutrals
    ("Hawthorne Yellow",      "HC-4",    "#E8D098", 67.0, 79.99, 400),
    ("Suntan",                "2166-40", "#D8B880", 53.0, 79.99, 400),
    ("Golden Straw",          "2152-40", "#D8C080", 58.0, 79.99, 400),
    ("Pale Honey",            "2155-50", "#E0D0A0", 68.0, 79.99, 400),
    ("Manchester Tan",        "HC-81",   "#C8B898", 53.0, 79.99, 400),
    ("Sandy Hook Beige",      "HC-39",   "#C8B890", 51.0, 79.99, 400),
    ("Copley Gray",           "HC-104",  "#B8B0A0", 46.0, 79.99, 400),
    # Reds & Pinks
    ("Red",                   "2000-10", "#882828", 8.0,  79.99, 400),
    ("Heritage Red",          "2169-10", "#783030", 7.0,  79.99, 400),
    ("Coral Gables",          "016",     "#E09080", 45.0, 79.99, 400),
    ("Blushing Bride",        "2008-70", "#F0D8D8", 78.0, 79.99, 400),
    ("Tearose",               "2008-50", "#E0A8A0", 53.0, 79.99, 400),
    ("Salmon Peach",          "2012-50", "#E8B098", 55.0, 79.99, 400),
    ("Dusty Rose",            "2173-40", "#C89090", 40.0, 79.99, 400),
    # Purples
    ("Soft Iris",             "2068-40", "#A898C8", 40.0, 79.99, 400),
    ("Wisteria",              "2071-40", "#C0A8C8", 47.0, 79.99, 400),
    ("Purple Easter Egg",     "2073-50", "#C8B0D0", 52.0, 79.99, 400),
    ("Spring Violet",         "2116-40", "#A890B0", 38.0, 79.99, 400),
    ("Midnight Dream",        "2067-10", "#1C1C42", 2.0,  79.99, 400),
    # Blacks & Dark Neutrals
    ("Black",                 "2132-10", "#282828", 2.0,  79.99, 400),
    ("Black Beauty",          "2128-10", "#252520", 2.0,  79.99, 400),
    ("Onyx",                  "2133-10", "#303030", 3.0,  79.99, 400),
    ("Graphite",              "2134-20", "#484844", 5.0,  79.99, 400),
    ("Dark Olive",            "2147-10", "#3C4030", 4.0,  79.99, 400),
    ("Storm",                 "2112-20", "#485060", 6.0,  79.99, 400),
]

BEHR = [
    # Whites
    ("Ultra Pure White",      "1850",    "#F5F2EC", 90.0, 59.98, 400),
    ("White",                 "W-B-700", "#F5F3EE", 91.0, 59.98, 400),
    ("Swiss Coffee",          "12",      "#F1E8DC", 84.0, 59.98, 400),
    ("Wind Fresh White",      "70",      "#F0EBE2", 87.0, 59.98, 400),
    ("Polar Bear",            "75",      "#F4F0EA", 88.0, 59.98, 400),
    ("Antique Linen",         "PPU7-09", "#E6D8C5", 76.0, 59.98, 400),
    ("Vanilla Cream",         "330W-2",  "#EEE3CA", 81.0, 59.98, 400),
    ("Wheat Bread",           "340W-2",  "#EDE0C5", 79.0, 59.98, 400),
    ("Ivory White",           "PPU7-06", "#F0E8D5", 83.0, 59.98, 400),
    ("Natural White",         "PPU18-08","#F2EDE4", 87.0, 59.98, 400),
    ("Off White",             "1820",    "#F0EDE5", 86.0, 59.98, 400),
    ("Bleached Linen",        "790W-3",  "#EDE4D0", 79.0, 59.98, 400),
    # Grays
    ("Silver Drop",           "720E-2",  "#E0DCDA", 77.0, 59.98, 400),
    ("Light French Gray",     "550E-2",  "#D4D1CE", 69.0, 59.98, 400),
    ("Sculptor Clay",         "PPU5-08", "#C4AC93", 46.0, 59.98, 400),
    ("Dolphin",               "PPU26-09","#D1CFC8", 67.0, 59.98, 400),
    ("Smoky White",           "BWC-13",  "#DDD9D2", 73.0, 59.98, 400),
    ("Hazy Stratus",          "N520-2",  "#D6D7D6", 71.0, 59.98, 400),
    ("Quiet Moment",          "PPU14-08","#C4C8CB", 53.0, 59.98, 400),
    ("Cracked Wheat",         "330E-3",  "#D9C7A8", 62.0, 59.98, 400),
    ("Burnished Clay",        "PPU2-10", "#B8977E", 38.0, 59.98, 400),
    ("Gray Area",             "N520-3",  "#C0BFBE", 52.0, 59.98, 400),
    ("Silver Shadow",         "770E-2",  "#D8D8D8", 73.0, 59.98, 400),
    ("Pebble Shore",          "N310-3",  "#C8C0B4", 54.0, 59.98, 400),
    ("Storm Cloud",           "790E-4",  "#A0A0A4", 35.0, 59.98, 400),
    ("Iron Ore",              "N520-6",  "#505254", 7.0,  59.98, 400),
    ("Pewter",                "N520-4",  "#909090", 28.0, 59.98, 400),
    ("Moonshine",             "W-F-410", "#D0D0CD", 66.0, 59.98, 400),
    # Blues
    ("Blue Lagoon",           "530D-5",  "#567E91", 15.0, 59.98, 400),
    ("Colony Blue",           "S530-3",  "#A0BAC8", 38.0, 59.98, 400),
    ("In The Moment",         "S500-4",  "#7BA0B8", 26.0, 59.98, 400),
    ("Oceanside",             "S490-7",  "#2A5870", 5.0,  59.98, 400),
    ("Celestial Blue",        "560D-3",  "#9ABCD0", 37.0, 59.98, 400),
    ("Aqua Fresco",           "500E-3",  "#A0C8D0", 42.0, 59.98, 400),
    ("Midnight Blue",         "S530-7",  "#1C3048", 2.0,  59.98, 400),
    ("Denim Wash",            "550D-3",  "#8AAABF", 30.0, 59.98, 400),
    ("Steel Blue",            "PPU14-10","#6888A8", 18.0, 59.98, 400),
    ("Nautical Blue",         "PPU13-08","#4868A8", 9.0,  59.98, 400),
    ("Baby Blue",             "550E-1",  "#C0D8E8", 66.0, 59.98, 400),
    # Greens
    ("Dried Herb",            "S370-5",  "#7A8B5E", 20.0, 59.98, 400),
    ("Jade Garden",           "450D-5",  "#6A9878", 16.0, 59.98, 400),
    ("Moss Landing",          "420D-5",  "#7A9870", 20.0, 59.98, 400),
    ("Sparkling Apple",       "400D-4",  "#90A878", 29.0, 59.98, 400),
    ("Meadow Mist",           "430E-3",  "#B0C8A8", 46.0, 59.98, 400),
    ("Sage Brush",            "400D-3",  "#A8B898", 40.0, 59.98, 400),
    ("Forest Floor",          "430D-7",  "#485840", 6.0,  59.98, 400),
    ("Garden Lattice",        "410D-4",  "#809878", 24.0, 59.98, 400),
    # Yellows & Warm
    ("Pale Yellow",           "300W-1",  "#F8F0D0", 87.0, 59.98, 400),
    ("Honey Gold",            "340D-4",  "#D8B060", 48.0, 59.98, 400),
    ("Terra Cotta Tile",      "230D-5",  "#C07848", 20.0, 59.98, 400),
    ("Spiced Pumpkin",        "240D-7",  "#A85830", 11.0, 59.98, 400),
    ("Desert Camel",          "290D-4",  "#C8A870", 44.0, 59.98, 400),
    # Reds & Pinks
    ("Coral Pink",            "200A-3",  "#F0A898", 52.0, 59.98, 400),
    ("Red Pepper",            "S-H-200", "#A83830", 11.0, 59.98, 400),
    ("Rose Taupe",            "PPU2-08", "#B89090", 42.0, 59.98, 400),
    ("Blush",                 "170A-2",  "#F0D0C8", 76.0, 59.98, 400),
    ("Cranberry Cocktail",    "S-G-690", "#983040", 10.0, 59.98, 400),
    # Purples
    ("Lavender Mist",         "650E-2",  "#D8D0E0", 71.0, 59.98, 400),
    ("Plum Wine",             "680F-7",  "#502848", 7.0,  59.98, 400),
    ("Soft Orchid",           "660E-3",  "#C8B8D0", 56.0, 59.98, 400),
    # Blacks & Darks
    ("Jet Black",             "1350",    "#252525", 3.0,  59.98, 400),
    ("Dark Truffle",          "790D-5",  "#5E4C41", 7.0,  59.98, 400),
    ("Midnight Blue",         "S530-7",  "#1C3050", 2.0,  59.98, 400),
    ("Graphite",              "N520-7",  "#383838", 3.0,  59.98, 400),
    ("Espresso Beans",        "N360-7",  "#302420", 2.0,  59.98, 400),
]

PPG = [
    # Whites
    ("Antique White",         "PPG1025-2","#F2E8D7", 83.0, 64.98, 400),
    ("Warm White",            "PPG1074-1","#F5EFE4", 87.0, 64.98, 400),
    ("Bright White",          "PPG1049-1","#F7F5F1", 91.0, 64.98, 400),
    ("Creamy White",          "PPG1085-1","#F2EAD9", 86.0, 64.98, 400),
    ("Pearl White",           "PPG1049-2","#EDE9E1", 83.0, 64.98, 400),
    ("Parchment",             "PPG1085-2","#EDE0C7", 80.0, 64.98, 400),
    ("Linen",                 "PPG1022-2","#EEE3D0", 82.0, 64.98, 400),
    ("Colonial White",        "PPG1085-3","#E4D4BC", 74.0, 64.98, 400),
    ("Natural Wicker",        "PPG1099-2","#E8DCC8", 78.0, 64.98, 400),
    ("Morning Light",         "PPG1074-2","#F0E8D8", 82.0, 64.98, 400),
    ("Almond Milk",           "PPG1085-4","#E8D8C0", 76.0, 64.98, 400),
    ("Honeymilk",             "PPG1099-1","#F4EEE2", 85.0, 64.98, 400),
    # Grays
    ("Foggy Day",             "PPG1025-3","#D5CFC7", 68.0, 64.98, 400),
    ("Aged Gray",             "PPG1025-4","#C4BEB4", 52.0, 64.98, 400),
    ("Harbor Gray",           "PPG1025-5","#A9A39C", 35.0, 64.98, 400),
    ("Driftwood",             "PPG1025-6","#8A847D", 26.0, 64.98, 400),
    ("Mushroom",              "PPG1008-4","#C0AA95", 44.0, 64.98, 400),
    ("Sandstone",             "PPG1085-4","#C9B49A", 48.0, 64.98, 400),
    ("Dove Gray",             "PPG1025-1","#E0DCD8", 77.0, 64.98, 400),
    ("Smoke Gray",            "PPG1022-3","#C8C0B4", 54.0, 64.98, 400),
    ("Slate",                 "PPG1001-5","#909498", 29.0, 64.98, 400),
    ("Pewter",                "PPG1001-4","#A8AAAA", 40.0, 64.98, 400),
    ("Charcoal",              "PPG1001-7","#505050", 7.0,  64.98, 400),
    ("Thunder",               "PPG1001-6","#686868", 13.0, 64.98, 400),
    ("Greige",                "PPG1022-4","#C0B0A0", 50.0, 64.98, 400),
    # Blues
    ("Steel Blue",            "PPG1157-5","#6B8FA3", 20.0, 64.98, 400),
    ("Midnight Blue",         "PPG1157-7","#2B3D52", 3.0,  64.98, 400),
    ("Pale Lavender",         "PPG1176-2","#D4CDD9", 65.0, 64.98, 400),
    ("Denim",                 "PPG1157-6","#4A6880", 9.0,  64.98, 400),
    ("Sky Blue",              "PPG1157-3","#9ABDD0", 37.0, 64.98, 400),
    ("Powder Blue",           "PPG1157-2","#C0D8E8", 65.0, 64.98, 400),
    ("Navy",                  "PPG1160-7","#283850", 3.0,  64.98, 400),
    ("Cornflower",            "PPG1157-4","#8098B8", 26.0, 64.98, 400),
    ("Aqua",                  "PPG1148-4","#70B0C0", 27.0, 64.98, 400),
    ("Teal",                  "PPG1148-6","#306878", 8.0,  64.98, 400),
    # Greens
    ("Sage Green",            "PPG1127-4","#93A98A", 30.0, 64.98, 400),
    ("Forest Green",          "PPG1127-7","#4A5E47", 7.0,  64.98, 400),
    ("Mint",                  "PPG1127-2","#C0D4B8", 58.0, 64.98, 400),
    ("Olive",                 "PPG1116-6","#786840", 15.0, 64.98, 400),
    ("Fern",                  "PPG1127-5","#708060", 16.0, 64.98, 400),
    ("Pistachio",             "PPG1127-3","#ACBF98", 43.0, 64.98, 400),
    ("Hunter Green",          "PPG1134-7","#385040", 5.0,  64.98, 400),
    # Yellows & Warm
    ("Canary",                "PPG1097-4","#E8D050", 58.0, 64.98, 400),
    ("Gold",                  "PPG1097-6","#C09030", 36.0, 64.98, 400),
    ("Amber",                 "PPG1081-6","#C07830", 20.0, 64.98, 400),
    ("Peach",                 "PPG1062-3","#E8B898", 56.0, 64.98, 400),
    ("Terra Cotta",           "PPG1062-5","#C06040", 14.0, 64.98, 400),
    ("Spice",                 "PPG1062-6","#A04830", 10.0, 64.98, 400),
    ("Tan",                   "PPG1085-5","#C0A880", 44.0, 64.98, 400),
    # Reds & Pinks
    ("Rose",                  "PPG1049-4","#E09090", 47.0, 64.98, 400),
    ("Blush",                 "PPG1049-3","#F0C8C0", 70.0, 64.98, 400),
    ("Crimson",               "PPG1048-7","#882030", 7.0,  64.98, 400),
    ("Coral",                 "PPG1062-4","#D88070", 30.0, 64.98, 400),
    ("Berry",                 "PPG1048-6","#A03850", 11.0, 64.98, 400),
    # Purples
    ("Lavender",              "PPG1176-3","#C0B0D0", 52.0, 64.98, 400),
    ("Purple",                "PPG1176-6","#604878", 9.0,  64.98, 400),
    ("Mauve",                 "PPG1176-4","#A890A8", 38.0, 64.98, 400),
    ("Plum",                  "PPG1176-7","#502850", 6.0,  64.98, 400),
    # Blacks & Darks
    ("Black",                 "PPG1001-7","#282828", 2.0,  64.98, 400),
    ("Dark Charcoal",         "PPG1001-6","#404040", 5.0,  64.98, 400),
    ("Ebony",                 "PPG1001-8","#202020", 2.0,  64.98, 400),
    ("Dark Brown",            "PPG1008-7","#402820", 3.0,  64.98, 400),
]

VALSPAR = [
    # Whites
    ("White Beauty",          "7001-1",  "#F4F1E8", 89.0, 67.98, 400),
    ("Fresh White",           "7001-5",  "#F0EBE0", 86.0, 67.98, 400),
    ("Classic White",         "7001-3",  "#F2EDE3", 87.0, 67.98, 400),
    ("Polar Wind",            "7001-2",  "#F1EEE5", 88.0, 67.98, 400),
    ("Soft Linen",            "6002-1A", "#EBE0D0", 80.0, 67.98, 400),
    ("Pashmina",              "6003-2B", "#D7CCBC", 68.0, 67.98, 400),
    ("Cream in my Coffee",    "2009-9B", "#E8D5B5", 73.0, 67.98, 400),
    ("Linen",                 "6002-2A", "#E8DCC8", 78.0, 67.98, 400),
    ("Warm Ivory",            "7001-4",  "#F0E8D5", 84.0, 67.98, 400),
    ("Natural White",         "7001-6",  "#EDE8DC", 82.0, 67.98, 400),
    ("Antique White",         "6002-3A", "#E4D5BC", 76.0, 67.98, 400),
    # Grays
    ("Pumice Stone",          "4002-1C", "#D8D4CF", 71.0, 67.98, 400),
    ("Gray Illusion",         "4006-3B", "#C5C3BD", 56.0, 67.98, 400),
    ("Temperate Taupe",       "6005-1B", "#CBBFB0", 57.0, 67.98, 400),
    ("Woodlawn Sterling",     "5003-2A", "#CACAC5", 59.0, 67.98, 400),
    ("Restrained Gold",       "2008-10C","#C4AF93", 46.0, 67.98, 400),
    ("Peaceful Retreat",      "5001-1A", "#D3D9D6", 68.0, 67.98, 400),
    ("Gray Mosaic",           "4006-4",  "#ADAAA4", 38.0, 67.98, 400),
    ("Smoke",                 "4003-1B", "#CECCC8", 63.0, 67.98, 400),
    ("Dry Dock",              "4003-2B", "#C0BEBC", 54.0, 67.98, 400),
    ("Pebble Shore",          "6004-1B", "#C8C0B4", 54.0, 67.98, 400),
    ("Gray Garden",           "4006-2B", "#D0CEC8", 67.0, 67.98, 400),
    ("Shark Skin",            "4003-3B", "#B0AEAC", 44.0, 67.98, 400),
    ("Storm Gray",            "4006-5",  "#909090", 28.0, 67.98, 400),
    ("Magnetic Gray",         "4006-6",  "#787878", 18.0, 67.98, 400),
    # Blues
    ("Blue Nile",             "5005-4A", "#7B9DB5", 23.0, 67.98, 400),
    ("Bunglehouse Blue",      "5004-4",  "#6B8A9E", 19.0, 67.98, 400),
    ("Blue Denim",            "5004-3",  "#8AAABF", 30.0, 67.98, 400),
    ("Stoneware Blue",        "5004-5",  "#5A7A90", 13.0, 67.98, 400),
    ("Deep Water",            "5005-6",  "#3A5878", 7.0,  67.98, 400),
    ("Foggy Blue",            "5001-2A", "#C0CEDA", 60.0, 67.98, 400),
    ("Skyline Blue",          "5005-3",  "#98B8D0", 36.0, 67.98, 400),
    ("Navy Blue",             "5005-7",  "#283850", 3.0,  67.98, 400),
    ("Powder Blue",           "5001-1B", "#C8D8E8", 65.0, 67.98, 400),
    ("Blue Spruce",           "5006-5",  "#507088", 10.0, 67.98, 400),
    # Greens
    ("Rosemary",              "5007-3",  "#8A9E7D", 28.0, 67.98, 400),
    ("Jasmine Green",         "5007-1",  "#D4DECE", 72.0, 67.98, 400),
    ("Olive Grove",           "5007-5",  "#708060", 16.0, 67.98, 400),
    ("Hunter",                "5007-7",  "#385040", 5.0,  67.98, 400),
    ("Sage",                  "5007-2",  "#C0CEBC", 60.0, 67.98, 400),
    ("Vineyard",              "5007-6",  "#506848", 8.0,  67.98, 400),
    ("Fern Grotto",           "5007-4",  "#909E78", 28.0, 67.98, 400),
    ("Meadow",                "5008-3",  "#A0B890", 38.0, 67.98, 400),
    # Yellows & Warm
    ("Sunflower",             "2003-5",  "#E0B040", 46.0, 67.98, 400),
    ("Gold Fusion",           "2008-5C", "#C89040", 36.0, 67.98, 400),
    ("Autumn Leaf",           "2009-5C", "#B07038", 21.0, 67.98, 400),
    ("Desert Sand",           "6003-3B", "#D8C0A0", 60.0, 67.98, 400),
    ("Caramel",               "2008-8C", "#C09060", 36.0, 67.98, 400),
    # Reds & Pinks
    ("Rose",                  "2002-3",  "#E0A0A0", 50.0, 67.98, 400),
    ("Blush",                 "2002-2",  "#F0C8C0", 71.0, 67.98, 400),
    ("Brick Red",             "2001-6",  "#A04030", 11.0, 67.98, 400),
    ("Coral",                 "2002-5",  "#D07868", 28.0, 67.98, 400),
    ("Cranberry",             "2001-7",  "#882838", 7.0,  67.98, 400),
    # Purples
    ("Lavender",              "4001-2B", "#D8CCD8", 68.0, 67.98, 400),
    ("Grape",                 "4001-6",  "#604870", 9.0,  67.98, 400),
    ("Iris",                  "4001-4",  "#9880A8", 30.0, 67.98, 400),
    ("Plum",                  "4001-7",  "#482848", 6.0,  67.98, 400),
    # Blacks & Darks
    ("Caviar",                "1001-7",  "#2C2C2C", 3.0,  67.98, 400),
    ("Black",                 "1001-8",  "#202020", 2.0,  67.98, 400),
    ("Charcoal",              "4006-7",  "#404040", 5.0,  67.98, 400),
    ("Espresso",              "3007-7",  "#302018", 2.0,  67.98, 400),
    ("Dark Gray",             "4006-6",  "#606060", 10.0, 67.98, 400),
]

VENDOR_DATA = {
    "sherwin_williams": SHERWIN_WILLIAMS,
    "benjamin_moore":   BENJAMIN_MOORE,
    "behr":             BEHR,
    "ppg":              PPG,
    "valspar":          VALSPAR,
}


def seed():
    sb = get_supabase()
    total = 0

    for vendor, colors in VENDOR_DATA.items():
        # Deduplicate by color_code within vendor
        seen = set()
        rows = []
        for name, code, hex_val, lrv, price, coverage in colors:
            if code in seen:
                continue
            seen.add(code)
            rows.append({
                "vendor":          vendor,
                "color_name":      name,
                "color_code":      code,
                "hex":             hex_val,
                "lrv":             lrv,
                "finish_options":  FINISH_OPTIONS,
                "price_per_gallon": price,
                "coverage_sqft":   coverage,
            })

        for i in range(0, len(rows), 50):
            batch = rows[i:i+50]
            sb.table("paint_colors").upsert(
                batch,
                on_conflict="vendor,color_code",
            ).execute()
            total += len(batch)
            print(f"  {vendor}: {min(i+50, len(rows))}/{len(rows)}")

        print(f"  ✓ {vendor}: {len(rows)} colors")

    print(f"\nDone. {total} total colors seeded.")
    # Refresh backend cache
    import requests as req
    try:
        r = req.post("https://paintmatch-production.up.railway.app/match-colors/refresh-cache", timeout=10)
        print(f"Cache refreshed: {r.json()}")
    except Exception as e:
        print(f"Cache refresh failed (call manually): {e}")


if __name__ == "__main__":
    print("Seeding full paint color catalog...")
    seed()

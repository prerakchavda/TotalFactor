#!/usr/bin/env python3
"""
Downloads and compiles USDA FoodData Central Foundation + SR Legacy JSON releases (~8,100 foods)
into TotalFactor/Resources/BundledUSDAFoods.json for 100% instant offline search (§4).

Usage:
    python3 Scripts/build_full_usda_bundle.py --foundation /tmp/usda_bulk/FoodData_Central_foundation_food_json_2026-04-30.json --sr-legacy /tmp/usda_bulk/FoodData_Central_sr_legacy_food_json_2018-04.json
    python3 Scripts/build_full_usda_bundle.py --download
"""
import argparse
import json
import tempfile
import urllib.request
import zipfile
from pathlib import Path

FOUNDATION_ZIP_URL = "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2026-04-30.zip"
SR_LEGACY_ZIP_URL = "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip"

# Maps both FDC 4-digit nutrient.id AND 3-digit nutrient.number strings
NUTRIENT_ID_OR_NUMBER_MAP = {
    # Calories / Energy
    "1008": "calories_primary",
    "208": "calories_primary",
    "2047": "calories_atwater_gen",
    "957": "calories_atwater_gen",
    "2048": "calories_atwater_spec",
    "958": "calories_atwater_spec",
    "1062": "energy_kj",
    "268": "energy_kj",
    # Protein
    "1003": "protein",
    "203": "protein",
    # Carbohydrates
    "1005": "carbs",
    "205": "carbs",
    "1050": "carbs_sum",
    "205.2": "carbs_sum",
    # Fat
    "1004": "fat",
    "204": "fat",
    "1085": "fat_nlea",
    "298": "fat_nlea",
    # Fiber
    "1079": "fiber",
    "291": "fiber",
    "2033": "fiber_aoac",
    "293": "fiber_aoac",
    # Sugars
    "2000": "sugar",
    "269": "sugar",
    "1063": "sugar_alt",
    "269.3": "sugar_alt",
    # Sodium
    "1093": "sodiumMg",
    "307": "sodiumMg",
    # Micronutrients
    "1092": "potassium_mg",
    "306": "potassium_mg",
    "1087": "calcium_mg",
    "301": "calcium_mg",
    "1089": "iron_mg",
    "303": "iron_mg",
    "1114": "vitamin_d_mcg",
    "328": "vitamin_d_mcg",
    "1162": "vitamin_c_mg",
    "401": "vitamin_c_mg",
    "1090": "magnesium_mg",
    "304": "magnesium_mg",
    "1095": "zinc_mg",
    "309": "zinc_mg",
    "1253": "cholesterol_mg",
    "601": "cholesterol_mg",
    "1258": "saturated_fat_g",
    "606": "saturated_fat_g",
}

MICRO_KEYS = {
    "potassium_mg", "calcium_mg", "iron_mg", "vitamin_d_mcg",
    "vitamin_c_mg", "magnesium_mg", "zinc_mg", "cholesterol_mg", "saturated_fat_g",
}


def clean_portion_label(portion: dict, gram_weight: float) -> str:
    amt = portion.get("amount") or portion.get("value") or 1
    try:
        amt_val = float(amt)
    except (TypeError, ValueError):
        amt_val = 1.0

    unit_obj = portion.get("measureUnit") or {}
    unit_abbr = (unit_obj.get("abbreviation") or "").strip()
    unit_name = (unit_obj.get("name") or "").strip()
    modifier = (portion.get("modifier") or portion.get("portionDescription") or "").strip()

    ignore_units = {"undetermined", "racc", ""}
    chosen_unit = ""
    if unit_abbr.lower() not in ignore_units:
        chosen_unit = unit_abbr
    elif unit_name.lower() not in ignore_units:
        chosen_unit = unit_name

    parts = [f"{amt_val:g}"]
    if chosen_unit and modifier and modifier.lower() != chosen_unit.lower():
        parts.append(f"{chosen_unit} {modifier}")
    elif chosen_unit:
        parts.append(chosen_unit)
    elif modifier:
        parts.append(modifier)
    else:
        parts.append("serving")

    base = " ".join(parts).strip()
    return f"{base} ({round(gram_weight)}g)"


def parse_fdc_item(item: dict, dataset_brand: str) -> dict | None:
    if not item or not isinstance(item, dict):
        return None
    fdc_id = str(item.get("fdcId") or "").strip()
    desc = (item.get("description") or "").strip()
    if not fdc_id or not desc:
        return None

    raw_vals: dict[str, float] = {}
    micros: dict[str, float] = {}

    for fn in (item.get("foodNutrients") or []):
        if not fn or not isinstance(fn, dict):
            continue
        amount = fn.get("amount")
        if amount is None:
            amount = fn.get("value")
        if amount is None:
            continue
        try:
            f_amount = float(amount)
        except (TypeError, ValueError):
            continue

        nutrient = fn.get("nutrient") or {}
        nid = str(nutrient.get("id") or fn.get("nutrientId") or "")
        nnum = str(nutrient.get("number") or fn.get("nutrientNumber") or "")

        key = NUTRIENT_ID_OR_NUMBER_MAP.get(nid) or NUTRIENT_ID_OR_NUMBER_MAP.get(nnum)
        if not key:
            continue

        if key in MICRO_KEYS:
            if f_amount > 0:
                micros[key] = round(f_amount, 2)
        else:
            raw_vals[key] = f_amount

    protein = max(0.0, raw_vals.get("protein", 0.0))
    carbs = max(0.0, raw_vals.get("carbs", raw_vals.get("carbs_sum", 0.0)))
    fat = max(0.0, raw_vals.get("fat", raw_vals.get("fat_nlea", 0.0)))
    fiber = max(0.0, raw_vals.get("fiber", raw_vals.get("fiber_aoac", 0.0)))
    sugar = max(0.0, raw_vals.get("sugar", raw_vals.get("sugar_alt", 0.0)))
    sodium_mg = max(0.0, raw_vals.get("sodiumMg", 0.0))

    calories = raw_vals.get("calories_primary", 0.0)
    if calories <= 0:
        calories = raw_vals.get("calories_atwater_gen", 0.0)
    if calories <= 0:
        calories = raw_vals.get("calories_atwater_spec", 0.0)
    if calories <= 0 and raw_vals.get("energy_kj", 0.0) > 0:
        calories = raw_vals["energy_kj"] / 4.184
    if calories <= 0 and (protein > 0 or carbs > 0 or fat > 0):
        calories = protein * 4.0 + carbs * 4.0 + fat * 9.0

    servings = []
    seen_labels = set()
    for p in (item.get("foodPortions") or []):
        if not p or not isinstance(p, dict):
            continue
        gw = p.get("gramWeight")
        if gw is None:
            continue
        try:
            gram_weight = float(gw)
        except (TypeError, ValueError):
            continue
        if gram_weight <= 0 or abs(gram_weight - 100.0) < 0.05:
            continue
        lbl = clean_portion_label(p, gram_weight)
        if lbl.lower() not in seen_labels:
            seen_labels.add(lbl.lower())
            servings.append({"label": lbl, "grams": round(gram_weight, 1)})
        if len(servings) >= 5:
            break

    servings.append({"label": "100 g", "grams": 100.0})

    entry = {
        "sourceID": fdc_id,
        "name": desc,
        "brand": dataset_brand,
        "calories": round(max(0.0, calories), 1),
        "protein": round(protein, 2),
        "carbs": round(carbs, 2),
        "fat": round(fat, 2),
        "fiber": round(fiber, 2),
        "sugar": round(sugar, 2),
        "sodiumMg": round(sodium_mg, 1),
        "servingSizes": servings,
        "micronutrients": micros,
    }
    return entry


def download_and_extract_json(url: str, dest_dir: Path) -> Path:
    zip_path = dest_dir / Path(url).name
    print(f"Downloading {url} ...")
    urllib.request.urlretrieve(url, zip_path)
    with zipfile.ZipFile(zip_path, "r") as zf:
        json_names = [n for n in zf.namelist() if n.endswith(".json")]
        if not json_names:
            raise RuntimeError(f"No .json found inside {zip_path}")
        zf.extract(json_names[0], dest_dir)
        return dest_dir / json_names[0]


def main() -> None:
    parser = argparse.ArgumentParser(description="Compile USDA Foundation + SR Legacy JSON into BundledUSDAFoods.json")
    parser.add_argument("--foundation", type=Path, help="Path to FoodData_Central_foundation_food_json file")
    parser.add_argument("--sr-legacy", type=Path, help="Path to FoodData_Central_sr_legacy_food_json file")
    parser.add_argument("--download", action="store_true", help="Download latest Foundation & SR Legacy JSONs from fdc.nal.usda.gov")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "TotalFactor" / "Resources" / "BundledUSDAFoods.json",
    )
    args = parser.parse_args()

    temp_dir_obj = None
    foundation_path = args.foundation
    sr_legacy_path = args.sr_legacy

    if args.download:
        temp_dir_obj = tempfile.TemporaryDirectory()
        tmp = Path(temp_dir_obj.name)
        if not foundation_path:
            foundation_path = download_and_extract_json(FOUNDATION_ZIP_URL, tmp)
        if not sr_legacy_path:
            sr_legacy_path = download_and_extract_json(SR_LEGACY_ZIP_URL, tmp)

    compiled: list[dict] = []
    seen_ids: set[str] = set()

    # Preserve curated friendly-named staple whole foods (<200 items) at the front if already present
    if args.output.exists():
        try:
            existing = json.loads(args.output.read_text(encoding="utf-8"))
            if isinstance(existing, list) and len(existing) <= 200:
                for item in existing:
                    sid = str(item.get("sourceID") or "")
                    if sid and sid not in seen_ids:
                        if "brand" not in item:
                            item["brand"] = "USDA Verified"
                        seen_ids.add(sid)
                        compiled.append(item)
        except Exception:
            pass

    sources = [
        (foundation_path, "FoundationFoods", "USDA Foundation"),
        (sr_legacy_path, "SRLegacyFoods", "USDA SR Legacy"),
    ]

    for src, root_key, brand_label in sources:
        if not src or not src.exists():
            continue
        data = json.loads(src.read_text(encoding="utf-8"))
        items = data.get(root_key) or []
        for raw in items:
            parsed = parse_fdc_item(raw, brand_label)
            if parsed and parsed["sourceID"] not in seen_ids:
                seen_ids.add(parsed["sourceID"])
                compiled.append(parsed)

    if temp_dir_obj is not None:
        temp_dir_obj.cleanup()

    if not compiled:
        print("No input files provided or parsed; keeping existing BundledUSDAFoods.json intact.")
        return

    args.output.write_text(json.dumps(compiled, separators=(",", ":")), encoding="utf-8")
    size_mb = args.output.stat().st_size / (1024 * 1024)
    print(f"Wrote {len(compiled)} offline USDA generic foods ({size_mb:.2f} MB) to {args.output}")


if __name__ == "__main__":
    main()

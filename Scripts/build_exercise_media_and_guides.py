#!/usr/bin/env python3
"""
Builds TotalFactor's enriched BundledExercises.json (92 exercises covering all core movements
plus Planet Fitness machines/cables from Strong exports) and downloads/optimizes public-domain
Start + Finish demonstration photos (Unlicense: yuhonas/free-exercise-db) into
TotalFactor/Resources/ExerciseMedia/.
"""

import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLED_JSON_PATH = ROOT / "TotalFactor" / "Resources" / "BundledExercises.json"
MEDIA_DIR = ROOT / "TotalFactor" / "Resources" / "ExerciseMedia"
STRONG_SRC = ROOT / "strong_workouts.csv"
STRONG_DEST = ROOT / "TotalFactor" / "Resources" / "BundledStrongWorkouts.csv"

EDB_JSON_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
EDB_IMG_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises"


def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


# Mapping of existing 68 exercise names -> free-exercise-db ID
EXISTING_MEDIA_MAP = {
    "Barbell Back Squat": "Barbell_Full_Squat",
    "Barbell Front Squat": "Front_Squat_Clean_Grip",
    "Hack Squat Machine": "Hack_Squat",
    "Leg Press": "Leg_Press",
    "Bulgarian Split Squat": "Split_Squat_with_Dumbbells",
    "Goblet Squat": "Goblet_Squat",
    "Smith Machine Squat": "Smith_Machine_Squat",
    "Conventional Barbell Deadlift": "Barbell_Deadlift",
    "Barbell Romanian Deadlift (RDL)": "Romanian_Deadlift",
    "Dumbbell Romanian Deadlift": "Stiff-Legged_Dumbbell_Deadlift",
    "Trap Bar Deadlift": "Leverage_Deadlift",
    "Barbell Hip Thrust": "Barbell_Hip_Thrust",
    "45° Back Extension": "Hyperextensions_Back_Extensions",
    "Kettlebell Swing": "One-Arm_Kettlebell_Swings",
    "Barbell Bench Press": "Barbell_Bench_Press_-_Medium_Grip",
    "Incline Barbell Bench Press": "Barbell_Incline_Bench_Press_-_Medium_Grip",
    "Flat Dumbbell Bench Press": "Dumbbell_Bench_Press",
    "Incline Dumbbell Press": "Incline_Dumbbell_Press",
    "Machine Chest Press": "Machine_Bench_Press",
    "Weighted Dip": "Dips_-_Chest_Version",
    "Push-Up": "Pushups",
    "Standing Barbell Overhead Press": "Standing_Military_Press",
    "Seated Dumbbell Shoulder Press": "Seated_Dumbbell_Press",
    "Machine Shoulder Press": "Machine_Shoulder_Military_Press",
    "Smith Machine Incline/Overhead Press": "Smith_Machine_Overhead_Shoulder_Press",
    "Arnold Press": "Arnold_Dumbbell_Press",
    "Barbell Bent-Over Row": "Bent_Over_Barbell_Row",
    "Chest-Supported T-Bar / Machine Row": "Leverage_High_Row",
    "Seated Cable Row": "Seated_Cable_Rows",
    "One-Arm Dumbbell Row": "One-Arm_Dumbbell_Row",
    "Pendlay Row": "Bent_Over_Barbell_Row",
    "Pull-Up / Weighted Pull-Up": "Pullups",
    "Chin-Up (Underhand)": "Chin-Up",
    "Wide-Grip Lat Pulldown": "Wide-Grip_Lat_Pulldown",
    "Neutral-Grip Lat Pulldown": "Close-Grip_Front_Lat_Pulldown",
    "Assisted Pull-Up Machine": "Band_Assisted_Pull-Up",
    "Dumbbell Farmer's Walk": "Farmers_Walk",
    "Trap Bar Carry": "Farmers_Walk",
    "Cable Chest Fly": "Cable_Crossover",
    "Pec Deck / Machine Fly": "Butterfly",
    "Incline Dumbbell Fly": "Incline_Dumbbell_Flyes",
    "Dumbbell Lateral Raise": "Side_Lateral_Raise",
    "Cable Lateral Raise": "Standing_Low-Pulley_Deltoid_Raise",
    "Machine Lateral Raise": "Seated_Side_Lateral_Raise",
    "Cable Face Pull": "Face_Pull",
    "Reverse Pec Deck (Rear Delt Fly)": "Reverse_Machine_Flyes",
    "Dumbbell Shrug": "Dumbbell_Shrug",
    "EZ-Bar Curl": "EZ-Bar_Curl",
    "Barbell Curl": "Barbell_Curl",
    "Incline Dumbbell Curl": "Alternate_Incline_Dumbbell_Curl",
    "Dumbbell Hammer Curl": "Hammer_Curls",
    "Bayesian Cable Curl": "Standing_One-Arm_Cable_Curl",
    "Preacher Curl Machine": "Machine_Preacher_Curls",
    "Cable Triceps Pushdown (Rope/Bar)": "Triceps_Pushdown_-_Rope_Attachment",
    "Overhead Cable Triceps Extension": "Cable_Rope_Overhead_Triceps_Extension",
    "EZ-Bar Skullcrusher": "EZ-Bar_Skullcrusher",
    "Dumbbell Overhead Triceps Extension": "Standing_Dumbbell_Triceps_Extension",
    "Leg Extension": "Leg_Extensions",
    "Seated Leg Curl": "Seated_Leg_Curl",
    "Lying Leg Curl": "Lying_Leg_Curls",
    "Cable Pull-Through": "Pull_Through",
    "Hip Abduction Machine": "Thigh_Abductor",
    "Standing Calf Raise": "Standing_Calf_Raises",
    "Seated Calf Raise": "Seated_Calf_Raise",
    "Cable Crunch": "Cable_Crunch",
    "Hanging Leg Raise": "Hanging_Leg_Raise",
    "Ab Wheel Rollout": "Ab_Roller",
    "Straight-Arm Cable Pulldown": "Straight-Arm_Pulldown",
}

# 24 New Planet Fitness & Strong-Export Canonical Exercises
NEW_EXERCISES = [
    {
        "name": "Incline Machine Chest Press",
        "primaryMuscles": ["chest", "frontDelts"],
        "secondaryMuscles": ["triceps"],
        "equipment": "machine",
        "movementPattern": "horizontalPush",
        "loadIncrementKg": 2.27,
        "instructions": "Adjust seat so handles start near upper chest/clavicle; press upward on a converged arc without shrugging shoulders.",
        "edb": "Leverage_Incline_Chest_Press",
    },
    {
        "name": "Iso-Lateral Machine Chest Press",
        "primaryMuscles": ["chest"],
        "secondaryMuscles": ["frontDelts", "triceps"],
        "equipment": "machine",
        "movementPattern": "horizontalPush",
        "loadIncrementKg": 2.27,
        "instructions": "Drive both independent arms evenly with shoulder blades pinned into the back pad.",
        "edb": "Leverage_Chest_Press",
    },
    {
        "name": "Supine Machine Chest Press",
        "primaryMuscles": ["chest"],
        "secondaryMuscles": ["frontDelts", "triceps"],
        "equipment": "machine",
        "movementPattern": "horizontalPush",
        "loadIncrementKg": 2.27,
        "instructions": "Pin upper back firmly to bench pad, lower handles for a deep pec stretch, and press smoothly to lockout.",
        "edb": "Leverage_Chest_Press",
    },
    {
        "name": "Flat Dumbbell Chest Fly",
        "primaryMuscles": ["chest"],
        "secondaryMuscles": ["frontDelts"],
        "equipment": "dumbbell",
        "movementPattern": "isolation",
        "loadIncrementKg": 2.27,
        "instructions": "Keep a soft 15–20° bend in elbows, open wide into a controlled chest stretch, and hug dumbbells back over sternum.",
        "edb": "Dumbbell_Flyes",
    },
    {
        "name": "Machine Lat Pulldown",
        "primaryMuscles": ["lats"],
        "secondaryMuscles": ["biceps", "upperBack"],
        "equipment": "machine",
        "movementPattern": "verticalPull",
        "loadIncrementKg": 2.27,
        "instructions": "Lock thighs tight under lap pad, depress shoulders first, and drive elbows down toward hips.",
        "edb": "Full_Range-Of-Motion_Lat_Pulldown",
    },
    {
        "name": "Seated Machine Row",
        "primaryMuscles": ["upperBack", "lats"],
        "secondaryMuscles": ["biceps", "rearDelts"],
        "equipment": "machine",
        "movementPattern": "horizontalPull",
        "loadIncrementKg": 2.27,
        "instructions": "Set chest pad so arms just reach full stretch, brace sternum into pad, and squeeze shoulder blades back.",
        "edb": "Leverage_Iso_Row",
    },
    {
        "name": "Iso-Lateral Machine Row",
        "primaryMuscles": ["lats", "upperBack"],
        "secondaryMuscles": ["biceps", "rearDelts"],
        "equipment": "machine",
        "movementPattern": "horizontalPull",
        "loadIncrementKg": 2.27,
        "instructions": "Pull one or both independent arms in a low arc toward your hip crease while keeping chest glued to the pad.",
        "edb": "Leverage_Iso_Row",
    },
    {
        "name": "Machine Bicep Curl",
        "primaryMuscles": ["biceps"],
        "secondaryMuscles": ["forearms"],
        "equipment": "machine",
        "movementPattern": "isolation",
        "loadIncrementKg": 2.27,
        "instructions": "Align elbow joint directly with the machine's pivot dot, keep upper arms flat on the pad, and control the bottom stretch.",
        "edb": "Machine_Bicep_Curl",
    },
    {
        "name": "Dumbbell Bicep Curl",
        "primaryMuscles": ["biceps"],
        "secondaryMuscles": ["forearms"],
        "equipment": "dumbbell",
        "movementPattern": "isolation",
        "loadIncrementKg": 2.27,
        "instructions": "Pin elbows at your sides, supinate palms upward as you curl, and lower under a full 2-second eccentric.",
        "edb": "Dumbbell_Bicep_Curl",
    },
    {
        "name": "Dumbbell Preacher Curl",
        "primaryMuscles": ["biceps"],
        "secondaryMuscles": ["forearms"],
        "equipment": "dumbbell",
        "movementPattern": "isolation",
        "loadIncrementKg": 2.27,
        "instructions": "Tuck armpit snug over the preacher pad so triceps stay flat; lower smoothly to near full extension.",
        "edb": "Two-Arm_Dumbbell_Preacher_Curl",
    },
    {
        "name": "Cable Bicep Curl",
        "primaryMuscles": ["biceps"],
        "secondaryMuscles": ["forearms"],
        "equipment": "cable",
        "movementPattern": "isolation",
        "loadIncrementKg": 1.13,
        "instructions": "Stand a step back from the low pulley for constant tension from bottom to peak squeeze.",
        "edb": "Standing_Biceps_Cable_Curl",
    },
    {
        "name": "Seated Triceps Press Machine",
        "primaryMuscles": ["triceps"],
        "secondaryMuscles": ["chest", "frontDelts"],
        "equipment": "machine",
        "movementPattern": "isolation",
        "loadIncrementKg": 2.27,
        "instructions": "Keep back flat against pad, tuck elbows in, and press handles straight down to full elbow lockout.",
        "edb": "Dip_Machine",
    },
    {
        "name": "Machine Triceps Extension",
        "primaryMuscles": ["triceps"],
        "secondaryMuscles": [],
        "equipment": "machine",
        "movementPattern": "isolation",
        "loadIncrementKg": 2.27,
        "instructions": "Line elbows up with the cam pivot, keep triceps anchored on the pad, and extend smoothly to full lockout.",
        "edb": "Machine_Triceps_Extension",
    },
    {
        "name": "Cable Triceps Kickback",
        "primaryMuscles": ["triceps"],
        "secondaryMuscles": [],
        "equipment": "cable",
        "movementPattern": "isolation",
        "loadIncrementKg": 1.13,
        "instructions": "Hinge torso 45°, lock upper arm parallel to your ribs, and extend forearm back until straight.",
        "edb": "Standing_Low-Pulley_One-Arm_Triceps_Extension",
    },
    {
        "name": "Overhead Barbell / EZ-Bar Triceps Extension",
        "primaryMuscles": ["triceps"],
        "secondaryMuscles": [],
        "equipment": "ezBar",
        "movementPattern": "isolation",
        "loadIncrementKg": 2.27,
        "instructions": "Keep elbows pointed up and tucked slightly in, lower the fixed bar behind your head for a deep long-head stretch.",
        "edb": "Lying_Triceps_Press",
    },
    {
        "name": "Dumbbell Skullcrusher",
        "primaryMuscles": ["triceps"],
        "secondaryMuscles": [],
        "equipment": "dumbbell",
        "movementPattern": "isolation",
        "loadIncrementKg": 2.27,
        "instructions": "Hold dumbbells with neutral palms, angle upper arms 15° back toward forehead, and hinge strictly at the elbows.",
        "edb": "Decline_Dumbbell_Triceps_Extension",
    },
    {
        "name": "Triceps Dip",
        "primaryMuscles": ["triceps"],
        "secondaryMuscles": ["chest", "frontDelts"],
        "equipment": "bodyweight",
        "movementPattern": "verticalPush",
        "loadIncrementKg": 2.27,
        "instructions": "Keep torso upright and elbows tracking back rather than flaring out to bias triceps.",
        "edb": "Dips_-_Triceps_Version",
    },
    {
        "name": "Assisted Dip Machine",
        "primaryMuscles": ["triceps", "chest"],
        "secondaryMuscles": ["frontDelts"],
        "equipment": "machine",
        "movementPattern": "horizontalPush",
        "loadIncrementKg": 2.27,
        "instructions": "Kneel on the counterweight pad (remember: less pin weight = harder!), lower to 90° elbow bend, and press to lockout.",
        "edb": "Dip_Machine",
    },
    {
        "name": "Seated Leg Press Machine",
        "primaryMuscles": ["quads", "glutes"],
        "secondaryMuscles": ["hamstrings"],
        "equipment": "machine",
        "movementPattern": "squat",
        "loadIncrementKg": 4.54,
        "instructions": "Adjust seat carriage for ~90°+ knee flexion without your lower back rounding off the pad; drive through mid-foot.",
        "edb": "Narrow_Stance_Leg_Press",
    },
    {
        "name": "Hip Adduction Machine",
        "primaryMuscles": ["glutes", "quads"],
        "secondaryMuscles": ["hamstrings"],
        "equipment": "machine",
        "movementPattern": "isolation",
        "loadIncrementKg": 2.27,
        "instructions": "Set knee pads to a comfortable wide stretch, sit tall against backrest, and squeeze inner thighs smoothly together.",
        "edb": "Thigh_Adductor",
    },
    {
        "name": "Calf Extension Machine",
        "primaryMuscles": ["calves"],
        "secondaryMuscles": [],
        "equipment": "machine",
        "movementPattern": "isolation",
        "loadIncrementKg": 4.54,
        "instructions": "Place balls of feet on the bottom edge of the footplate, pause 2 seconds in full ankle dorsiflexion, then press onto tiptoes.",
        "edb": "Calf_Press",
    },
    {
        "name": "Calf Press on Leg Press",
        "primaryMuscles": ["calves"],
        "secondaryMuscles": [],
        "equipment": "machine",
        "movementPattern": "isolation",
        "loadIncrementKg": 4.54,
        "instructions": "Keep knees softly unlocked with safety catches engaged; let heels sink deep before pressing high onto the balls of your feet.",
        "edb": "Calf_Press_On_The_Leg_Press_Machine",
    },
    {
        "name": "Abdominal Crunch Machine",
        "primaryMuscles": ["abs"],
        "secondaryMuscles": [],
        "equipment": "machine",
        "movementPattern": "isolation",
        "loadIncrementKg": 2.27,
        "instructions": "Exhale hard while curling your ribcage down toward your pelvis rather than pulling with your arms or hip flexors.",
        "edb": "Ab_Crunch_Machine",
    },
    {
        "name": "Dumbbell Front Raise",
        "primaryMuscles": ["frontDelts"],
        "secondaryMuscles": ["sideDelts"],
        "equipment": "dumbbell",
        "movementPattern": "isolation",
        "loadIncrementKg": 2.27,
        "instructions": "Stand tall without torso sway, raise dumbbells smoothly to eye level, and control the descent.",
        "edb": "Front_Dumbbell_Raise",
    },
    {
        "name": "Dumbbell Upright Row",
        "primaryMuscles": ["sideDelts", "traps"],
        "secondaryMuscles": ["biceps", "frontDelts"],
        "equipment": "dumbbell",
        "movementPattern": "verticalPull",
        "loadIncrementKg": 2.27,
        "instructions": "Pull dumbbells up slightly wide along your torso leading with elbows stopping at chest/shoulder height.",
        "edb": "Standing_Dumbbell_Upright_Row",
    },
    {
        "name": "Rear Delt Cable Crossover",
        "primaryMuscles": ["rearDelts"],
        "secondaryMuscles": ["upperBack"],
        "equipment": "cable",
        "movementPattern": "isolation",
        "loadIncrementKg": 1.13,
        "instructions": "Grab left cable with right hand and right cable with left hand at shoulder height; sweep straight arms wide and back.",
        "edb": "Cable_Rear_Delt_Fly",
    },
    {
        "name": "Pike Push-Up",
        "primaryMuscles": ["frontDelts"],
        "secondaryMuscles": ["triceps", "chest"],
        "equipment": "bodyweight",
        "movementPattern": "verticalPush",
        "loadIncrementKg": 2.27,
        "instructions": "Hike hips into an inverted V, lower the crown of your head slightly in front of your hands, and press back up.",
        "edb": "Handstand_Push-Ups",
    },
    {
        "name": "Band Bent-Over Row",
        "primaryMuscles": ["upperBack", "lats"],
        "secondaryMuscles": ["biceps", "rearDelts"],
        "equipment": "bands",
        "movementPattern": "horizontalPull",
        "loadIncrementKg": 1.13,
        "instructions": "Stand on the center of the band, hinge 45° with a flat back, and row handles into your lower ribs.",
        "edb": "Back_Flyes_-_With_Bands",
    },
]

# Custom Planet Fitness / Equipment Setup Tips tailored by exercise / equipment
PF_SETUP_BY_NAME = {
    "Machine Chest Press": "Planet Fitness Tip: Set the yellow seat lever so the handles line up with mid-chest (nipple line). Flip down the 5 lb / 7.5 lb add-on weight for smooth micro-jumps.",
    "Incline Machine Chest Press": "Planet Fitness Tip: Set the seat so handles begin right at your upper chest / collarbone, and keep your shoulder blades tucked down into the pad.",
    "Pec Deck / Machine Fly": "Planet Fitness Tip: Set the arm cams 1–2 clicks behind your torso for a deep stretch without shoulder pinch, and set seat height so hands travel at mid-sternum.",
    "Machine Shoulder Press": "Planet Fitness Tip: Adjust seat so handles start right at chin/ear level. Use neutral (palms-in) grip if your shoulders prefer extra joint space.",
    "Cable Lateral Raise": "Planet Fitness Tip: Set the adjustable cable tower pulley to wrist/mid-shin height and use the 2.5 lb / 5 lb stack add-on plate so you never have to jump 10 lb at once.",
    "Overhead Cable Triceps Extension": "Planet Fitness Tip: Attach a rope to the pulley set around waist-to-chest height, face away, stagger your stance for balance, and let your elbows stretch overhead.",
    "Seated Triceps Press Machine": "Planet Fitness Tip: Flip the rotating handles inward for narrow triceps focus or outward for wider comfort, fasten the seatbelt if heavy, and keep shoulders down.",
    "Machine Triceps Extension": "Planet Fitness Tip: Adjust the seat so the backs of your upper arms sit flush on the angled pad with your elbows lined up directly beside the yellow pivot dot.",
    "Cable Triceps Kickback": "Planet Fitness Tip: Skip the handle attachment and grab the rubber cable ball directly at the low pulley for the cleanest wrist alignment.",
    "Wide-Grip Lat Pulldown": "Planet Fitness Tip: Snug the thigh rollers firmly over your quads so heavy stacks don't lift you off the seat; pull bar to your collarbone, not behind your neck.",
    "Machine Lat Pulldown": "Planet Fitness Tip: Lock the lap pad tight, sit tall, and take full advantage of the diverging arm path to stretch your lats at the top.",
    "Seated Machine Row": "Planet Fitness Tip: Adjust the chest pad distance so your fingertips barely reach the handles while seated—this guarantees full scapular stretch every rep.",
    "Seated Cable Row": "Planet Fitness Tip: Brace feet on the platform with soft knees; sit upright rather than swinging your lower back.",
    "Straight-Arm Cable Pulldown": "Planet Fitness Tip: Set pulley near the top notch with a straight bar or long rope, step back 2–3 feet, and hinge torso ~20–30°.",
    "Machine Bicep Curl": "Planet Fitness Tip: Match your elbow joint directly with the red/yellow axis marker on the machine arm and avoid lifting your elbows off the pad.",
    "Seated Leg Press Machine": "Planet Fitness Tip: Place feet hip-width in the middle of the platform (lower on the plate = more quads, higher = more glutes) and adjust carriage close enough for 90°+ knee bend.",
    "Leg Press": "Planet Fitness Tip: Always test safety catch release handles before your top set; keep your tailbone pressed firmly into the seat.",
    "Leg Extension": "Planet Fitness Tip: Adjust backrest so the back of your knees hug the seat edge aligned with the pivot axis, and set the shin pad just above your ankles.",
    "Seated Leg Curl": "Planet Fitness Tip: Set the ankle roller right above your Achilles heel and lock the thigh lap pad down SNUG—tight lap pads prevent hip lift and double hamstring recruitment.",
    "Standing Calf Raise": "Planet Fitness Tip: Adjust shoulder pads so you have room to hit a full tiptoe peak AND sink into a 2-second bottom stretch without bottoming out the weight stack.",
    "Calf Extension Machine": "Planet Fitness Tip: Place only the balls of your feet on the bottom lip of the footplate; keep knees very slightly soft and pause 2s in the stretch.",
    "Hip Abduction Machine": "Planet Fitness Tip: Set the starting lever to the narrowest notch, sit back into the pad (or lean slightly forward cleanly), and control the return.",
    "Hip Adduction Machine": "Planet Fitness Tip: Use the range lever to ease carefully into a comfortable inner-thigh stretch before releasing tension onto the stack.",
    "Abdominal Crunch Machine": "Planet Fitness Tip: Focus on curling your sternum toward your belt buckle—don't yank with your arms or push with your feet.",
    "Assisted Pull-Up Machine": "Planet Fitness Tip: Remember counterweight math—MORE weight on the pin = MORE help (easier). Track actual assistance consistently.",
    "Assisted Dip Machine": "Planet Fitness Tip: Fold down the knee platform on the Assisted Chin/Dip station; lower pin numbers mean less help and heavier triceps overload.",
}


def default_setup_tip(equipment: str, pattern: str) -> str:
    if equipment == "smithMachine":
        return "Planet Fitness Smith Machine: Starting bar carriage is ~20 lb (9 kg). Twist wrists to unhook, set safety stops just below bottom depth, and place feet slightly forward if angled."
    if equipment == "barbell":
        return "Setup: At Planet Fitness, use pre-loaded fixed barbells (20–60 lb) for curls/presses or auto-swap heavy compound barbell lifts to the Smith Machine or Leverage Machines."
    if equipment == "ezBar":
        return "Setup: Grab a pre-loaded fixed EZ-curl bar (20–60 lb rack) and take an angled semi-supinated grip that feels natural on your wrists."
    if equipment == "dumbbell":
        return "Planet Fitness Dumbbells (5–75 lb): Clear floor space around your bench, plant both feet flat, and kick weights into position on your thighs before lying back."
    if equipment == "cable":
        return "Planet Fitness Cable Tower: Check that both pulleys or add-on micro plates (2.5 / 5 lb) match your logged setup, and step far enough out that the weight plates never slam at the bottom."
    if equipment == "machine":
        return "Machine Setup: Adjust seat height first so your working joint lines up with the machine's pivot marker, and use the drop-down 5 lb micro-weight for smooth overload."
    if equipment == "bodyweight":
        return "Bodyweight Setup: Set a clean grip width, brace your abs and glutes into a rigid line, and own a controlled 2-second lowering phase on every rep."
    return "Setup: Establish a stable stance, brace your core 360°, and verify full, pain-free range of motion on your first warm-up rep."


def default_cues_and_mistakes(pattern: str, equipment: str):
    if pattern in ("horizontalPush", "verticalPush"):
        cues = [
            "Keep shoulder blades depressed and tucked back—never let shoulders shrug toward your ears.",
            "Control the lowering (eccentric) phase for ~2 seconds into a comfortable deep stretch.",
            "Drive smoothly to lockout while exhaling through the sticking point.",
        ]
        mistakes = [
            "Bouncing out of the bottom stretch or slamming the weight stack between reps.",
            "Flaring elbows straight out at 90° instead of tucking ~30–45° in the scapular plane.",
        ]
    elif pattern in ("horizontalPull", "verticalPull"):
        cues = [
            "Initiate every rep by depressing/gliding your shoulder blades before bending your elbows.",
            "Think of your hands as hooks and drive your elbows back or down toward your hips.",
            "Let your lats/upper back stretch forward under control at the start of each rep.",
        ]
        mistakes = [
            "Heaving with lower-back momentum to move a stack that's too heavy.",
            "Cutting reps short instead of pulling elbows all the way back and controlling the stretch.",
        ]
    elif pattern in ("squat", "hinge"):
        cues = [
            "Brace your core 360° before initiating each rep and keep spine/pelvis neutral.",
            "Control descent for 2 seconds to full comfortable depth where target muscles stretch.",
            "Drive evenly through your whole foot without letting knees cave inward.",
        ]
        mistakes = [
            "Lifting hips/tailbone off the seat pad at the bottom of leg presses or squats.",
            "Using half-reps with excessive weight instead of full controlled knee/hip range.",
        ]
    else:
        cues = [
            "Keep your upper arm or torso anchored still so 100% of tension stays on the target muscle.",
            "Pause 0.5–1 second in the peak contraction or stretched position—no momentum.",
            "Use a smooth 2-second eccentric on every single rep, especially the final hard reps.",
        ]
        mistakes = [
            "Swinging torso or elbows to cheat heavier weight at the expense of target muscle tension.",
            "Letting the cable/machine stack crash at the bottom and losing tension.",
        ]
    return cues, mistakes


def download_and_optimize(args):
    edb_id, media_key = args
    for idx in (0, 1):
        out_file = MEDIA_DIR / f"{media_key}_{idx}.jpg"
        if out_file.exists() and out_file.stat().st_size > 2000:
            continue
        url = f"{EDB_IMG_BASE}/{edb_id}/{idx}.jpg"
        tmp_file = MEDIA_DIR / f".tmp_{media_key}_{idx}.jpg"
        urllib.request.urlretrieve(url, tmp_file)
        subprocess.run(
            [
                "sips",
                "-Z",
                "560",
                "--setProperty",
                "format",
                "jpeg",
                "--setProperty",
                "formatOptions",
                "72",
                str(tmp_file),
                "--out",
                str(out_file),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        tmp_file.unlink(missing_ok=True)
    return media_key


def main():
    MEDIA_DIR.mkdir(parents=True, exist_ok=True)
    if STRONG_SRC.exists():
        shutil.copy2(STRONG_SRC, STRONG_DEST)
        print(f"Copied {STRONG_SRC.name} -> {STRONG_DEST}")

    print("Fetching free-exercise-db metadata...")
    with urllib.request.urlopen(EDB_JSON_URL) as resp:
        edb_list = json.loads(resp.read().decode("utf-8"))
    edb_by_id = {item["id"]: item for item in edb_list}

    with open(BUNDLED_JSON_PATH, "r", encoding="utf-8") as f:
        existing = json.load(f)

    # Strip any previously added new exercises if script is re-run
    existing_by_name = {item["name"]: item for item in existing}
    base_names_ordered = [item["name"] for item in existing if item["name"] in EXISTING_MEDIA_MAP]

    final_catalog = []
    download_jobs = {}

    # 1. Process original 68 exercises
    for name in base_names_ordered:
        item = dict(existing_by_name[name])
        edb_id = EXISTING_MEDIA_MAP[name]
        edb_entry = edb_by_id[edb_id]
        media_key = slugify(edb_id)
        download_jobs[media_key] = (edb_id, media_key)

        raw_steps = [s.strip() for s in edb_entry.get("instructions", []) if s.strip()]
        steps = raw_steps[:5] if raw_steps else [item["instructions"]]
        cues, mistakes = default_cues_and_mistakes(item["movementPattern"], item["equipment"])

        item["mediaKey"] = media_key
        item["setupTip"] = PF_SETUP_BY_NAME.get(name) or default_setup_tip(item["equipment"], item["movementPattern"])
        item["steps"] = steps
        item["formCues"] = cues
        item["commonMistakes"] = mistakes
        final_catalog.append(item)

    # 2. Process 28 Planet Fitness / Strong exercises
    for spec in NEW_EXERCISES:
        name = spec["name"]
        edb_id = spec["edb"]
        edb_entry = edb_by_id[edb_id]
        media_key = slugify(edb_id)
        download_jobs[media_key] = (edb_id, media_key)

        raw_steps = [s.strip() for s in edb_entry.get("instructions", []) if s.strip()]
        steps = raw_steps[:5] if raw_steps else [spec["instructions"]]
        cues, mistakes = default_cues_and_mistakes(spec["movementPattern"], spec["equipment"])

        item = {
            "name": name,
            "primaryMuscles": spec["primaryMuscles"],
            "secondaryMuscles": spec["secondaryMuscles"],
            "equipment": spec["equipment"],
            "movementPattern": spec["movementPattern"],
            "loadIncrementKg": spec["loadIncrementKg"],
            "instructions": spec["instructions"],
            "mediaKey": media_key,
            "setupTip": PF_SETUP_BY_NAME.get(name) or default_setup_tip(spec["equipment"], spec["movementPattern"]),
            "steps": steps,
            "formCues": cues,
            "commonMistakes": mistakes,
        }
        final_catalog.append(item)

    with open(BUNDLED_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(final_catalog, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Wrote {len(final_catalog)} enriched exercises to {BUNDLED_JSON_PATH}")
    print(f"Downloading & optimizing {len(download_jobs) * 2} exercise photos...")

    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        list(pool.map(download_and_optimize, download_jobs.values()))

    total_bytes = sum(p.stat().st_size for p in MEDIA_DIR.glob("*.jpg"))
    print(f"Done! {len(list(MEDIA_DIR.glob('*.jpg')))} photos saved ({total_bytes / (1024 * 1024):.2f} MB total).")


if __name__ == "__main__":
    main()

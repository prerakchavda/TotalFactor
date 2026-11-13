#!/usr/bin/env python3
"""Generates and signs ready-to-import Apple Shortcuts for Total Factor."""

import os
import plistlib
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "TotalFactor" / "Resources" / "Shortcuts"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def make_uuid() -> str:
    return str(uuid.uuid4()).upper()


def make_text_token_string(parts: list) -> dict:
    """Builds a WFTextTokenString from literal strings and (output_uuid, output_name, aggrandizements) tuples."""
    buf = []
    attachments = {}
    cursor = 0
    for part in parts:
        if isinstance(part, str):
            buf.append(part)
            cursor += len(part.encode("utf-16-le")) // 2
        else:
            out_uuid, out_name, aggs = part
            attachments[f"{{{cursor}, 1}}"] = {
                "Type": "ActionOutput",
                "OutputUUID": out_uuid,
                "OutputName": out_name,
                **({"Aggrandizements": aggs} if aggs else {}),
            }
            buf.append("\uFFFC")
            cursor += 1

    return {
        "Value": {
            "string": "".join(buf),
            "attachmentsByRange": attachments,
        },
        "WFSerializationType": "WFTextTokenString",
    }


def make_var_attachment(out_uuid: str, out_name: str, aggs=None) -> dict:
    val = {
        "Type": "ActionOutput",
        "OutputUUID": out_uuid,
        "OutputName": out_name,
    }
    if aggs:
        val["Aggrandizements"] = aggs
    return {
        "Value": val,
        "WFSerializationType": "WFTextTokenAttachment",
    }


def value_agg(prop_name: str = "Value") -> list:
    return [
        {
            "Type": "WFPropertyVariableAggrandizement",
            "PropertyName": prop_name,
        }
    ]


def find_health_sample_action(
    sample_type: str,
    date_operator: int = 1002,  # 1002 = is today, 1001 = is in the last
    days: int = 1,
    limit: int | None = None,
    sort_latest: bool = False,
    group_by: str | None = None,
    unit: str | None = None,
) -> tuple[dict, str]:
    action_uuid = make_uuid()
    # Operator 1002 ("is today") takes empty Values; attaching Unit/Number corrupts the predicate on iOS.
    date_values = {} if date_operator == 1002 else {"Unit": 16, "Number": days}  # 16 = NSCalendarUnitDay
    params = {
        "UUID": action_uuid,
        "WFContentItemFilter": {
            "Value": {
                "WFActionParameterFilterPrefix": 1,
                "WFContentPredicateBoundedDate": False,
                "WFActionParameterFilterTemplates": [
                    {
                        "Operator": 4,
                        "Property": "Type",
                        "Removable": False,
                        "Values": {
                            "Enumeration": {
                                "Value": sample_type,
                                "WFSerializationType": "WFStringSubstitutableState",
                            }
                        },
                    },
                    {
                        "Operator": date_operator,
                        "Property": "Start Date",
                        "Removable": True,
                        "Values": date_values,
                    },
                ],
            },
            "WFSerializationType": "WFContentPredicateTableTemplate",
        },
    }
    if group_by is not None:
        params["WFHKSampleFilteringGroupBy"] = group_by
        params["WFHKSampleFilteringFillMissing"] = False
    if unit is not None:
        params["WFHKSampleFilteringUnit"] = unit
    if sort_latest:
        params["WFContentItemSortProperty"] = "Start Date"
        params["WFContentItemSortOrder"] = "Latest First"
    if limit is not None:
        params["WFContentItemLimitEnabled"] = True
        params["WFContentItemLimitNumber"] = limit

    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.filter.health.quantity",
        "WFWorkflowActionParameters": params,
    }, action_uuid


def wrap_workflow(actions: list[dict], color: int = 4282601983, glyph: int = 59771) -> dict:
    return {
        "WFWorkflowClientVersion": "2605.0.5",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowHasShortcutInputVariables": False,
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": ["WFStringContentItem"],
        "WFWorkflowTypes": [],
        "WFWorkflowIcon": {
            "WFWorkflowIconStartColor": color,
            "WFWorkflowIconGlyphNumber": glyph,
        },
        "WFWorkflowActions": actions,
    }


def sign_and_write(doc: dict, output_path: Path):
    with tempfile.TemporaryDirectory(dir="/tmp") as tmp:
        unsigned = Path(tmp) / "unsigned.shortcut"
        signed = Path(tmp) / "signed.shortcut"
        with open(unsigned, "wb") as f:
            plistlib.dump(doc, f, fmt=plistlib.FMT_BINARY)
        subprocess.run(
            ["shortcuts", "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(signed)],
            check=True,
        )
        shutil.copyfile(signed, output_path)
        os.chmod(output_path, 0o644)
    print(f"Generated signed shortcut: {output_path} ({output_path.stat().st_size} bytes)")


def build_health_sync_shortcut():
    actions = []

    # Group cumulative metrics by Day so HealthKit aggregates them in-process instead of
    # loading thousands of raw samples into Shortcuts (which freezes iPhone Shortcuts).
    steps_act, steps_uuid = find_health_sample_action(
        "Steps", date_operator=1002, limit=1, sort_latest=True, group_by="Day", unit="count"
    )
    actions.append(steps_act)

    active_act, active_uuid = find_health_sample_action(
        "Active Energy", date_operator=1002, limit=1, sort_latest=True, group_by="Day", unit="kcal"
    )
    actions.append(active_act)

    basal_act, basal_uuid = find_health_sample_action(
        "Resting Energy", date_operator=1002, limit=1, sort_latest=True, group_by="Day", unit="kcal"
    )
    actions.append(basal_act)

    rhr_act, rhr_uuid = find_health_sample_action(
        "Resting Heart Rate", date_operator=1001, days=2, limit=1, sort_latest=True
    )
    actions.append(rhr_act)

    hrv_act, hrv_uuid = find_health_sample_action(
        "Heart Rate Variability", date_operator=1001, days=2, limit=1, sort_latest=True
    )
    actions.append(hrv_act)

    hr_act, hr_uuid = find_health_sample_action(
        "Heart Rate", date_operator=1002, limit=1, sort_latest=True
    )
    actions.append(hr_act)

    weight_act, weight_uuid = find_health_sample_action(
        "Weight", date_operator=1001, days=30, limit=1, sort_latest=True
    )
    actions.append(weight_act)

    text_uuid = make_uuid()
    url_parts = [
        "totalfactor://health-sync?steps=",
        (steps_uuid, "Health Samples", value_agg("Value")),
        "&active_kcal=",
        (active_uuid, "Health Samples", value_agg("Value")),
        "&basal_kcal=",
        (basal_uuid, "Health Samples", value_agg("Value")),
        "&rhr=",
        (rhr_uuid, "Health Samples", value_agg("Value")),
        "&hrv=",
        (hrv_uuid, "Health Samples", value_agg("Value")),
        "&hr=",
        (hr_uuid, "Health Samples", value_agg("Value")),
        "&weight=",
        (weight_uuid, "Health Samples", value_agg("Value")),
        "&weight_unit=",
        (weight_uuid, "Health Samples", value_agg("Unit")),
    ]
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.gettext",
            "WFWorkflowActionParameters": {
                "UUID": text_uuid,
                "WFTextActionText": make_text_token_string(url_parts),
            },
        }
    )

    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
            "WFWorkflowActionParameters": {
                "UUID": make_uuid(),
                "WFInput": make_text_token_string([(text_uuid, "Text", None)]),
            },
        }
    )

    sign_and_write(wrap_workflow(actions, color=4292093695, glyph=59771), OUT_DIR / "Total Factor Health Sync.shortcut")


def build_workout_shortcut():
    actions = []

    list_uuid = make_uuid()
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.list",
            "WFWorkflowActionParameters": {
                "UUID": list_uuid,
                "WFItems": [
                    "Run",
                    "Walk",
                    "Incline Walk",
                    "Cycling",
                    "Rowing",
                    "Swimming",
                    "Soccer",
                    "Basketball",
                    "HIIT",
                    "Other Cardio",
                ],
            },
        }
    )

    choose_uuid = make_uuid()
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.choosefromlist",
            "WFWorkflowActionParameters": {
                "UUID": choose_uuid,
                "WFInput": make_var_attachment(list_uuid, "List"),
                "WFChooseFromListActionPrompt": "Select Workout Type",
                "WFChooseFromListActionSelectMultiple": False,
            },
        }
    )

    enc_uuid = make_uuid()
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.urlencode",
            "WFWorkflowActionParameters": {
                "UUID": enc_uuid,
                "WFEncodeMode": "Encode",
                "WFInput": make_text_token_string([(choose_uuid, "Chosen Item", None)]),
            },
        }
    )

    dur_uuid = make_uuid()
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.ask",
            "WFWorkflowActionParameters": {
                "UUID": dur_uuid,
                "WFInputType": "Number",
                "WFAskActionPrompt": "Workout duration (minutes):",
                "WFAskActionDefaultAnswerNumber": 30,
                "WFAskActionAllowsDecimalNumbers": False,
                "WFAskActionAllowsNegativeNumbers": False,
            },
        }
    )

    kcal_uuid = make_uuid()
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.ask",
            "WFWorkflowActionParameters": {
                "UUID": kcal_uuid,
                "WFInputType": "Number",
                "WFAskActionPrompt": "Active calories burned (kcal, or 0 to skip):",
                "WFAskActionDefaultAnswerNumber": 250,
                "WFAskActionAllowsDecimalNumbers": False,
                "WFAskActionAllowsNegativeNumbers": False,
            },
        }
    )

    mi_uuid = make_uuid()
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.ask",
            "WFWorkflowActionParameters": {
                "UUID": mi_uuid,
                "WFInputType": "Number",
                "WFAskActionPrompt": "Distance in miles (0 if none):",
                "WFAskActionDefaultAnswerNumber": 0,
                "WFAskActionAllowsDecimalNumbers": True,
                "WFAskActionAllowsNegativeNumbers": False,
            },
        }
    )

    text_uuid = make_uuid()
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.gettext",
            "WFWorkflowActionParameters": {
                "UUID": text_uuid,
                "WFTextActionText": make_text_token_string(
                    [
                        "totalfactor://workout-sync?workout_title=",
                        (enc_uuid, "URL Encoded Text", None),
                        "&workout_min=",
                        (dur_uuid, "Provided Input", None),
                        "&workout_kcal=",
                        (kcal_uuid, "Provided Input", None),
                        "&workout_mi=",
                        (mi_uuid, "Provided Input", None),
                        "&source=Apple%20Fitness",
                    ]
                ),
            },
        }
    )

    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
            "WFWorkflowActionParameters": {
                "UUID": make_uuid(),
                "WFInput": make_text_token_string([(text_uuid, "Text", None)]),
            },
        }
    )

    sign_and_write(wrap_workflow(actions, color=4288230143, glyph=59819), OUT_DIR / "Total Factor Log Cardio Workout.shortcut")


if __name__ == "__main__":
    build_health_sync_shortcut()
    build_workout_shortcut()

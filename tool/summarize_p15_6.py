"""Summarize saved P15.6 replay JSON; does not process or classify images."""
import hashlib
import json
from pathlib import Path
import statistics
import sys

before = Path(sys.argv[1] if len(sys.argv) > 1 else "build/p156-before")
after = Path(sys.argv[2] if len(sys.argv) > 2 else "build/p156-after-complete/baseline")
destination = Path(sys.argv[3] if len(sys.argv) > 3 else "build/p156-comparison.json")
fixtures = Path("test/fixtures/p15_6")
manifest = json.loads((fixtures / "published_manifest.json").read_text(encoding="utf-8"))
keys = json.loads((fixtures / "expected_answers.json").read_text(encoding="utf-8"))
questions = [q for s in manifest["artifact"]["template"]["sections"] for q in s["questions"]]
rows, comparisons, old_times, new_times = [], [], [], []
for path in sorted(before.glob("*/*.jpg.json")):
    report = json.loads(path.read_text(encoding="utf-8"))
    capture = report["input"]["file"]
    key = None if capture in keys["blankFiles"] else keys[
        "mixedStrokes" if "mix" in capture.lower() else "allMarked"]
    run = report["fourPoint"]
    answers = run.get("selectedAnswers", [])
    correct = 0
    for i, answer in enumerate(answers):
        index = (int(key[i]) - 1 if i < 3 else ord(key[i]) - ord("A")) if key else None
        expected = [questions[i]["options"][index]["id"]] if key else []
        correct += answer["state"] == ("marked" if key else "blank") and answer["options"] == expected
    rows.append({"config": path.parent.name, "capture": capture,
                 "completed": bool(answers), "correct": correct, "evaluated": len(answers),
                 "applicationAcceptance": run.get("acceptance"), "error": run.get("error"),
                 "captureTimestamp": report["input"].get("captureTimestamp"),
                 "sha256": report["input"]["sha256"]})
    if path.parent.name != "baseline" or not answers:
        continue
    changed = json.loads((after / path.name).read_text(encoding="utf-8"))
    assert report["input"]["sha256"] == changed["input"]["sha256"]
    new = changed["fourPoint"]
    old_ms = run["snapshot"]["timingsMs"]["preprocessing"]
    new_ms = new["snapshot"]["timingsMs"]["preprocessing"]
    old_times.append(old_ms)
    new_times.append(new_ms)
    hashes = {}
    for stage in ("canonical", "normalized", "binary"):
        name = f"{capture}_fourPoint_{stage}.png"
        old_hash = hashlib.sha256((path.parent / name).read_bytes()).hexdigest()
        new_hash = hashlib.sha256((after / name).read_bytes()).hexdigest()
        hashes[stage] = {"beforeSha256": old_hash, "afterSha256": new_hash, "equal": old_hash == new_hash}
    comparisons.append({"capture": capture, "beforePreprocessingMs": old_ms,
                        "afterPreprocessingMs": new_ms, "byteIdenticalPngs": hashes,
                        "answersIdentical": answers == new["selectedAnswers"],
                        "bubbleMeasurementsIdentical": run["snapshot"]["bubbles"] == new["snapshot"]["bubbles"]})
summary = {"answerKeyProvenance": keys["provenance"], "results": rows,
           "beforeAfter": comparisons, "beforeMedianPreprocessingMs": statistics.median(old_times),
           "afterMedianPreprocessingMs": statistics.median(new_times),
           "timingLimit": "One paired replay per image on one device; not a statistical device benchmark."}
destination.write_text(json.dumps(summary, indent=2), encoding="utf-8")
for row in rows:
    print(row["config"], row["capture"], f'{row["correct"]}/{row["evaluated"]}', row["error"] or "")
print("Preprocessing medians:", summary["beforeMedianPreprocessingMs"], "->", summary["afterMedianPreprocessingMs"])

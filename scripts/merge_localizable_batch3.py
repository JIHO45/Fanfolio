#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "Fanfolio" / "Localizable.xcstrings"

NEW: dict[str, tuple[str, str]] = {
    "ticket.share.navigationTitle": ("Share ticket image", "티켓 이미지 공유"),
    "culture.report.imageTitle": ("My visit report", "나의 관람 리포트"),
    "culture.report.visitsSuffix": ("visits", "회 관람"),
    "culture.report.mostVisited": ("Most visits", "최다 관람"),
}


def entry(en: str, ko: str) -> dict:
    return {
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en}},
            "ko": {"stringUnit": {"state": "translated", "value": ko}},
        }
    }


def main() -> None:
    data = json.loads(ROOT.read_text(encoding="utf-8"))
    strings: dict = data["strings"]
    for key, (en, ko) in NEW.items():
        strings[key] = entry(en, ko)
    ROOT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Merged {len(NEW)} keys")


if __name__ == "__main__":
    main()

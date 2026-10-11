#!/usr/bin/env python3
"""Собирает Otzvuk/Models/TextLibraryData.swift из Tools/affirmation_texts.txt.

Каждый номер попадает ровно в одну категорию (первое совпадение по порядку списка).
Запуск: python3 Tools/generate_text_library.py
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))

def r(*parts):
    out = []
    for p in parts:
        out += list(range(p[0], p[1] + 1)) if isinstance(p, tuple) else [p]
    return out

CATEGORIES = [
    ("health", "Здоровье и энергия", r(1, (15, 18), (50, 53), 131)),
    ("body", "Тело, спорт и питание", r(2, 10, 13, 14, 128, (141, 157))),
    ("money", "Деньги и доход", r((3, 7), 49, 57, 79, (171, 178))),
    ("happiness", "Счастье и радость", r((19, 24), 56, (65, 78), (90, 97), 103, 133)),
    ("selflove", "Любовь к себе", r((84, 89), (98, 100))),
    ("confidence", "Уверенность и сила", r(29, 42, 44, 47, 48, 101, 102, (104, 116), 127, 130)),
    ("calm", "Спокойствие", r(8, 43, 45, 125, 126)),
    ("goals", "Цели и действия", r((25, 28), 54, 55, 105, 109, 110, 111, 113, 117, (134, 140))),
    ("creativity", "Творчество и интуиция", r((30, 41), 58)),
    ("people", "Общение и влияние", r(9, 11, 12, 46, (80, 83), (118, 124), 129, 132, (158, 170))),
    ("recording", "Настройка на запись", r((59, 64))),
]

texts = {}
for line in open(os.path.join(HERE, "affirmation_texts.txt"), encoding="utf-8"):
    m = re.match(r"^(\d+)\.\s+(.*\S)\s*$", line)
    if m:
        texts[int(m.group(1))] = m.group(2)

assigned = {}
for cid, _, nums in CATEGORIES:
    for n in nums:
        assigned.setdefault(n, cid)
missing = sorted(set(texts) - set(assigned))
unknown = sorted(set(assigned) - set(texts))
print(f"текстов: {len(texts)}; без категории: {missing}; нет текста: {unknown}")
if missing or unknown:
    sys.exit(1)

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')

lines = ["// Сгенерировано Tools/generate_text_library.py из Tools/affirmation_texts.txt. Не править вручную.",
         "", "extension TextLibrary {", "    static let categories: [TextCategory] = ["]
for cid, title, _ in CATEGORIES:
    nums = sorted(n for n, c in assigned.items() if c == cid)
    lines.append(f'        TextCategory(id: "{cid}", title: "{title}", items: [')
    for n in nums:
        lines.append(f'            TextItem(id: {n}, text: "{esc(texts[n])}"),')
    lines.append("        ]),")
lines += ["    ]", "}", ""]
out = os.path.join(HERE, "..", "Otzvuk", "Models", "TextLibraryData.swift")
open(out, "w", encoding="utf-8").write("\n".join(lines))
for cid, title, _ in CATEGORIES:
    print(f"  {title}: {sum(1 for c in assigned.values() if c == cid)}")

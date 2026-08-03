import re
import sys
from pathlib import Path


source_path = Path(sys.argv[1])
requested = {int(value) for value in sys.argv[2:]}
text = source_path.read_text(encoding="utf-8")
parts = re.split(r"(?=^=== PAGE \d+ ===$)", text, flags=re.MULTILINE)
for part in parts:
    match = re.match(r"=== PAGE (\d+) ===", part)
    if match and int(match.group(1)) in requested:
        print(part.rstrip())


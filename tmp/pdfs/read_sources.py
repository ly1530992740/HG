from pathlib import Path

from pypdf import PdfReader


SOURCE_DIR = Path(r"C:\Users\15309\Desktop")
OUTPUT_DIR = Path(r"D:\project\HG\tmp\pdfs\reading")
PATTERNS = (
    "Applying Goal-Oriented*.pdf",
    "GameAIPro2_Chapter32*.pdf",
    "GameAIPro_Chapter09*.pdf",
    "GameAIPro2_Chapter30*.pdf",
    "three-states*.pdf",
    "GameAIPro_Chapter12*.pdf",
    "GameAIPro2_Chapter28*.pdf",
    "GameAIPro2_Chapter31*.pdf",
    "GameAIPro2_Chapter27*.pdf",
)


OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
for pattern in PATTERNS:
    for source_path in SOURCE_DIR.glob(pattern):
        reader = PdfReader(source_path)
        page_text = []
        for page_number, page in enumerate(reader.pages, start=1):
            page_text.append(
                f"=== PAGE {page_number} ===\n{page.extract_text() or ''}"
            )
        text = "\n\n".join(page_text)
        output_path = OUTPUT_DIR / f"{source_path.stem}.txt"
        output_path.write_text(text, encoding="utf-8")
        title = reader.metadata.title if reader.metadata else ""
        print(f"{source_path.name}\tpages={len(reader.pages)}\tchars={len(text)}\t{title}")

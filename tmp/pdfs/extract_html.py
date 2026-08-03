from html.parser import HTMLParser
from pathlib import Path


class ArticleTextParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.depth = 0
        self.ignored_depth = 0
        self.text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "article":
            self.depth += 1
        elif self.depth and tag in {"script", "style", "nav", "footer"}:
            self.ignored_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag == "article" and self.depth:
            self.depth -= 1
        elif self.depth and tag in {"script", "style", "nav", "footer"} and self.ignored_depth:
            self.ignored_depth -= 1

    def handle_data(self, data: str) -> None:
        if self.depth and not self.ignored_depth and data.strip():
            self.text.append(data.strip())


source_path = Path(r"C:\Users\15309\Desktop\利用效用评分的人工智能决策（第一部分）——四十年的代码.html")
output_path = Path(r"D:\project\HG\tmp\pdfs\reading\utility_scores_part_1.txt")
parser = ArticleTextParser()
parser.feed(source_path.read_text(encoding="utf-8"))
fixed_text = []
for value in parser.text:
    try:
        value = value.encode("gbk").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass
    fixed_text.append(value)
output_path.write_text("\n".join(fixed_text), encoding="utf-8")
print(output_path, output_path.stat().st_size)

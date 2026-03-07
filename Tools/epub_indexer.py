#!/usr/bin/env python3
import argparse
import os
import re
import sqlite3
import sys
import textwrap
import zipfile
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from typing import Dict, Iterable, List, Optional, Tuple
from xml.etree import ElementTree as ET


DEFAULT_DOC_DIR = Path(__file__).resolve().parent.parent / "doc"
DEFAULT_DB_PATH = Path(__file__).resolve().parent / "epub_index.db"


SCHEMA_SQL = """
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS documents (
  id INTEGER PRIMARY KEY,
  epub_file TEXT NOT NULL,
  path TEXT NOT NULL,
  title TEXT,
  chapter_order INTEGER NOT NULL,
  UNIQUE(epub_file, path)
);

CREATE TABLE IF NOT EXISTS chunks (
  id INTEGER PRIMARY KEY,
  doc_id INTEGER NOT NULL,
  chunk_index INTEGER NOT NULL,
  heading TEXT,
  class_name TEXT,
  method_name TEXT,
  text TEXT NOT NULL,
  FOREIGN KEY(doc_id) REFERENCES documents(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS classes (
  id INTEGER PRIMARY KEY,
  epub_file TEXT NOT NULL,
  path TEXT NOT NULL,
  class_name TEXT NOT NULL,
  title TEXT,
  inherits TEXT,
  inherited_by TEXT,
  description TEXT,
  UNIQUE(epub_file, path, class_name)
);

CREATE TABLE IF NOT EXISTS methods (
  id INTEGER PRIMARY KEY,
  epub_file TEXT NOT NULL,
  path TEXT NOT NULL,
  class_name TEXT NOT NULL,
  method_name TEXT NOT NULL,
  signature TEXT,
  description TEXT,
  UNIQUE(epub_file, path, class_name, method_name, signature)
);

CREATE TABLE IF NOT EXISTS properties (
  id INTEGER PRIMARY KEY,
  epub_file TEXT NOT NULL,
  path TEXT NOT NULL,
  class_name TEXT NOT NULL,
  property_name TEXT NOT NULL,
  type_name TEXT,
  setter_name TEXT,
  getter_name TEXT,
  default_value TEXT,
  description TEXT,
  UNIQUE(epub_file, path, class_name, property_name)
);

CREATE TABLE IF NOT EXISTS examples (
  id INTEGER PRIMARY KEY,
  epub_file TEXT NOT NULL,
  path TEXT NOT NULL,
  heading TEXT,
  language TEXT,
  code TEXT NOT NULL,
  context_text TEXT,
  class_name TEXT,
  method_name TEXT
);

CREATE INDEX IF NOT EXISTS idx_classes_name ON classes(class_name);
CREATE INDEX IF NOT EXISTS idx_methods_name ON methods(class_name, method_name);
CREATE INDEX IF NOT EXISTS idx_properties_name ON properties(class_name, property_name);

CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
  text,
  heading,
  class_name,
  method_name,
  content='chunks',
  content_rowid='id'
);

CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
  INSERT INTO chunks_fts(rowid, text, heading, class_name, method_name)
  VALUES (new.id, new.text, new.heading, new.class_name, new.method_name);
END;

CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
  INSERT INTO chunks_fts(chunks_fts, rowid, text, heading, class_name, method_name)
  VALUES ('delete', old.id, old.text, old.heading, old.class_name, old.method_name);
END;

CREATE TRIGGER IF NOT EXISTS chunks_au AFTER UPDATE ON chunks BEGIN
  INSERT INTO chunks_fts(chunks_fts, rowid, text, heading, class_name, method_name)
  VALUES ('delete', old.id, old.text, old.heading, old.class_name, old.method_name);
  INSERT INTO chunks_fts(rowid, text, heading, class_name, method_name)
  VALUES (new.id, new.text, new.heading, new.class_name, new.method_name);
END;
"""


@dataclass
class Page:
    path: str
    title: str
    text: str
    html: str
    chapter_order: int


class HTMLTextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._parts: List[str] = []
        self._skip_depth = 0

    def handle_starttag(self, tag: str, attrs) -> None:
        low = tag.lower()
        if low in {"script", "style"}:
            self._skip_depth += 1
            return
        if self._skip_depth:
            return
        if low in {
            "br",
            "p",
            "div",
            "li",
            "h1",
            "h2",
            "h3",
            "h4",
            "h5",
            "h6",
            "tr",
            "section",
            "article",
            "pre",
        }:
            self._parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        low = tag.lower()
        if low in {"script", "style"} and self._skip_depth:
            self._skip_depth -= 1
            return
        if self._skip_depth:
            return
        if low in {
            "p",
            "div",
            "li",
            "h1",
            "h2",
            "h3",
            "h4",
            "h5",
            "h6",
            "tr",
            "section",
            "article",
            "pre",
        }:
            self._parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self._skip_depth:
            return
        if data.strip():
            self._parts.append(data)

    def text(self) -> str:
        raw = "".join(self._parts).replace("\r", "")
        lines = [re.sub(r"\s+", " ", line).strip() for line in raw.split("\n")]
        lines = [line for line in lines if line]
        return "\n".join(lines)


def strip_html_fragment(fragment: str) -> str:
    parser = HTMLTextExtractor()
    parser.feed(fragment)
    return parser.text()


def normalize_whitespace(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def _extract_section_html(html: str, heading: str) -> str:
    pattern = re.compile(
        rf"<h2[^>]*>\s*{re.escape(heading)}\s*</h2>(.*?)(?=<h2[^>]*>|</body>)",
        re.DOTALL | re.IGNORECASE,
    )
    match = pattern.search(html)
    return match.group(1) if match else ""


def _extract_description_html(html: str) -> str:
    return _extract_section_html(html, "Description")


def _extract_class_name_from_h1(html: str) -> Optional[str]:
    match = re.search(r"<h1[^>]*>\s*([^<]+?)\s*</h1>", html, re.IGNORECASE)
    if not match:
        return None
    name = normalize_whitespace(match.group(1).replace("(DEV)", ""))
    return name or None


def _extract_labeled_paragraph_text(html: str, label: str) -> str:
    pattern = re.compile(
        rf"<p[^>]*>\s*<strong>\s*{re.escape(label)}\s*</strong>\s*(.*?)</p>",
        re.DOTALL | re.IGNORECASE,
    )
    match = pattern.search(html)
    if not match:
        return ""
    return normalize_whitespace(strip_html_fragment(match.group(1)))


def extract_class_record(path: str, html: str) -> Optional[Dict[str, str]]:
    if not path.startswith("classes/class_"):
        return None
    class_name = _extract_class_name_from_h1(html) or to_class_name(Path(path).stem)
    if not class_name:
        return None
    description = normalize_whitespace(
        strip_html_fragment(_extract_description_html(html))
    )
    return {
        "class_name": class_name,
        "title": class_name,
        "inherits": _extract_labeled_paragraph_text(html, "Inherits:"),
        "inherited_by": _extract_labeled_paragraph_text(html, "Inherited By:"),
        "description": description,
    }


def extract_method_records(
    path: str, class_name: str, html: str
) -> List[Dict[str, str]]:
    section = _extract_section_html(html, "Method Descriptions")
    if not section:
        return []

    pattern = re.compile(
        r"<p[^>]*class=\"classref-method\"[^>]*>(.*?)</p>(.*?)(?=<hr[^>]*>|$)",
        re.DOTALL | re.IGNORECASE,
    )
    records: List[Dict[str, str]] = []
    for sig_html, desc_html in pattern.findall(section):
        sig_text = normalize_whitespace(strip_html_fragment(sig_html))
        name_match = re.search(
            r"<strong>\s*([A-Za-z_][A-Za-z0-9_]*)\s*</strong>", sig_html
        )
        if not name_match:
            continue
        method_name = name_match.group(1)
        description = normalize_whitespace(strip_html_fragment(desc_html))
        records.append(
            {
                "class_name": class_name,
                "method_name": method_name,
                "signature": sig_text,
                "description": description,
            }
        )
    return records


def extract_property_records(
    path: str, class_name: str, html: str
) -> List[Dict[str, str]]:
    section = _extract_section_html(html, "Property Descriptions")
    if not section:
        return []

    pattern = re.compile(
        r"<p[^>]*class=\"classref-property\"[^>]*>(.*?)</p>(.*?)(?=<hr[^>]*>|$)",
        re.DOTALL | re.IGNORECASE,
    )
    out: List[Dict[str, str]] = []
    for prop_html, tail_html in pattern.findall(section):
        prop_text = normalize_whitespace(strip_html_fragment(prop_html))
        name_match = re.search(
            r"<strong>\s*([A-Za-z_][A-Za-z0-9_]*)\s*</strong>", prop_html
        )
        if not name_match:
            continue
        property_name = name_match.group(1)
        default_value = ""
        if "=" in prop_text:
            default_value = prop_text.split("=", 1)[1].strip()
        type_name = prop_text.split(property_name, 1)[0].strip()

        setter = ""
        getter = ""
        setter_match = re.search(
            r"<strong>\s*(set_[A-Za-z0-9_]+)\s*</strong>", tail_html
        )
        getter_match = re.search(
            r"<strong>\s*(get_[A-Za-z0-9_]+|is_[A-Za-z0-9_]+)\s*</strong>", tail_html
        )
        if setter_match:
            setter = setter_match.group(1)
        if getter_match:
            getter = getter_match.group(1)

        description = normalize_whitespace(
            strip_html_fragment(
                re.sub(
                    r"<ul[^>]*class=\"classref-property-setget\".*?</ul>",
                    "",
                    tail_html,
                    flags=re.DOTALL | re.IGNORECASE,
                )
            )
        )
        out.append(
            {
                "class_name": class_name,
                "property_name": property_name,
                "type_name": type_name,
                "setter_name": setter,
                "getter_name": getter,
                "default_value": default_value,
                "description": description,
            }
        )
    return out


def extract_example_records(
    path: str, class_name: Optional[str], html: str
) -> List[Dict[str, str]]:
    examples: List[Dict[str, str]] = []
    heading = ""
    for block_match in re.finditer(
        r"(<h[1-4][^>]*>.*?</h[1-4]>)|(<div[^>]*class=\"highlight-([a-zA-Z0-9_+-]+).*?\"[^>]*>.*?<pre>.*?</pre>.*?</div>)",
        html,
        re.DOTALL | re.IGNORECASE,
    ):
        h = block_match.group(1)
        code_block = block_match.group(2)
        language = block_match.group(3)
        if h:
            heading = normalize_whitespace(strip_html_fragment(h))
            continue
        if not code_block:
            continue
        pre_match = re.search(
            r"<pre>(.*?)</pre>", code_block, re.DOTALL | re.IGNORECASE
        )
        if not pre_match:
            continue
        code = pre_match.group(1)
        code = re.sub(r"<[^>]+>", "", code)
        code = code.replace("\r", "").strip()
        if not code:
            continue
        method_match = re.search(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\(", code)
        examples.append(
            {
                "heading": heading,
                "language": (language or "").lower(),
                "code": code,
                "context_text": normalize_whitespace(code[:200]),
                "class_name": class_name or "",
                "method_name": method_match.group(1) if method_match else "",
            }
        )
    return examples


def connect_db(index_path: Path) -> sqlite3.Connection:
    index_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(index_path)
    conn.execute("PRAGMA foreign_keys=ON")
    conn.executescript(SCHEMA_SQL)
    return conn


def to_class_name(filename_stem: str) -> Optional[str]:
    if not filename_stem.startswith("class_"):
        return None
    token = filename_stem[len("class_") :]
    parts = [part for part in token.split("_") if part]
    if not parts:
        return None
    return "".join(p[0].upper() + p[1:] for p in parts)


def normalize_class_name(
    fallback: Optional[str], title: str, text: str
) -> Optional[str]:
    if not fallback:
        return None

    title_token = re.search(r"[A-Z][A-Za-z0-9_]+", title)
    if title_token:
        candidate = title_token.group(0)
        if candidate.lower() == fallback.lower():
            return candidate

    text_token = re.search(r"\b([A-Z][A-Za-z0-9_]+)\b", text[:240])
    if text_token:
        candidate = text_token.group(1)
        if candidate.lower() == fallback.lower():
            return candidate

    return fallback


def split_chunks(text: str, max_chars: int = 1800) -> List[str]:
    paragraphs = [p.strip() for p in text.split("\n") if p.strip()]
    if not paragraphs:
        return []

    chunks: List[str] = []
    current: List[str] = []
    current_len = 0

    for p in paragraphs:
        if len(p) > max_chars:
            if current:
                chunks.append("\n".join(current).strip())
                current = []
                current_len = 0
            long_parts = textwrap.wrap(
                p, width=max_chars, break_long_words=False, break_on_hyphens=False
            )
            chunks.extend(part.strip() for part in long_parts if part.strip())
            continue

        projected = current_len + len(p) + (1 if current else 0)
        if projected > max_chars and current:
            chunks.append("\n".join(current).strip())
            current = [p]
            current_len = len(p)
        else:
            current.append(p)
            current_len = projected

    if current:
        chunks.append("\n".join(current).strip())

    return chunks


def read_container_rootfile(zf: zipfile.ZipFile) -> str:
    xml = zf.read("META-INF/container.xml")
    root = ET.fromstring(xml)
    ns = {"c": "urn:oasis:names:tc:opendocument:xmlns:container"}
    el = root.find("c:rootfiles/c:rootfile", ns)
    if el is None:
        raise RuntimeError("Failed to locate rootfile in META-INF/container.xml")
    path = el.attrib.get("full-path")
    if not path:
        raise RuntimeError("container.xml rootfile has no full-path")
    return path


def parse_ncx_titles(zf: zipfile.ZipFile, ncx_path: Optional[str]) -> Dict[str, str]:
    if not ncx_path:
        return {}
    try:
        xml = zf.read(ncx_path)
    except KeyError:
        return {}

    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return {}

    ns = {"n": "http://www.daisy.org/z3986/2005/ncx/"}
    out: Dict[str, str] = {}
    for point in root.findall(".//n:navPoint", ns):
        text_el = point.find("n:navLabel/n:text", ns)
        content_el = point.find("n:content", ns)
        if text_el is None or content_el is None:
            continue
        src = content_el.attrib.get("src", "")
        src = src.split("#", 1)[0]
        if src:
            out[src] = (text_el.text or "").strip()
    return out


def parse_opf_pages(zf: zipfile.ZipFile) -> List[Tuple[str, str, int]]:
    opf_path = read_container_rootfile(zf)
    opf_dir = str(PurePosixPath(opf_path).parent)
    xml = zf.read(opf_path)
    root = ET.fromstring(xml)
    ns = {"opf": "http://www.idpf.org/2007/opf"}

    manifest = root.find("opf:manifest", ns)
    spine = root.find("opf:spine", ns)
    if manifest is None or spine is None:
        raise RuntimeError("Invalid OPF: missing manifest or spine")

    item_by_id: Dict[str, Tuple[str, str]] = {}
    ncx_path: Optional[str] = None

    for item in manifest.findall("opf:item", ns):
        item_id = item.attrib.get("id", "")
        href = item.attrib.get("href", "")
        media_type = item.attrib.get("media-type", "")
        if not item_id or not href:
            continue
        full_href = (
            str(PurePosixPath(opf_dir) / href) if opf_dir not in {"", "."} else href
        )
        item_by_id[item_id] = (full_href, media_type)
        if media_type == "application/x-dtbncx+xml":
            ncx_path = full_href

    title_by_path = parse_ncx_titles(zf, ncx_path)
    out: List[Tuple[str, str, int]] = []

    order = 0
    for itemref in spine.findall("opf:itemref", ns):
        idref = itemref.attrib.get("idref", "")
        entry = item_by_id.get(idref)
        if not entry:
            continue
        href, media_type = entry
        if media_type not in {"application/xhtml+xml", "text/html"}:
            continue
        rel_for_title = (
            href[len(opf_dir) + 1 :]
            if opf_dir not in {"", "."} and href.startswith(opf_dir + "/")
            else href
        )
        title = title_by_path.get(rel_for_title) or Path(href).stem
        out.append((href, title, order))
        order += 1

    return out


def extract_text_from_html(html_text: str) -> str:
    parser = HTMLTextExtractor()
    parser.feed(html_text)
    return parser.text()


def guess_method_name(chunk: str) -> Optional[str]:
    match = re.search(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^\n()]{0,140}\)", chunk)
    if not match:
        return None
    name = match.group(1)
    if name.lower() in {"if", "for", "while", "switch", "return", "print", "func"}:
        return None
    return name


def iter_epub_pages(epub_path: Path) -> Iterable[Page]:
    with zipfile.ZipFile(epub_path) as zf:
        page_defs = parse_opf_pages(zf)
        for page_path, title, chapter_order in page_defs:
            try:
                page_bytes = zf.read(page_path)
            except KeyError:
                continue
            html = page_bytes.decode("utf-8", errors="ignore")
            text = extract_text_from_html(html)
            if not text or len(text) < 40:
                continue
            yield Page(
                path=page_path,
                title=title.strip() or Path(page_path).stem,
                text=text,
                html=html,
                chapter_order=chapter_order,
            )


def rebuild_index(
    doc_dir: Path, index_path: Path, force: bool = False
) -> Dict[str, int]:
    if not doc_dir.exists():
        raise FileNotFoundError(f"Document directory not found: {doc_dir}")

    epub_files = sorted(doc_dir.glob("*.epub"))
    if not epub_files:
        raise FileNotFoundError(f"No .epub files found in: {doc_dir}")

    conn = connect_db(index_path)
    processed_doc_keys = set()
    inserted_chunks = 0
    classes_upserted = 0
    methods_upserted = 0
    properties_upserted = 0
    examples_inserted = 0

    try:
        for epub_path in epub_files:
            epub_name = epub_path.name
            if force:
                conn.execute("DELETE FROM documents WHERE epub_file = ?", (epub_name,))
                conn.execute("DELETE FROM classes WHERE epub_file = ?", (epub_name,))
                conn.execute("DELETE FROM methods WHERE epub_file = ?", (epub_name,))
                conn.execute("DELETE FROM properties WHERE epub_file = ?", (epub_name,))
                conn.execute("DELETE FROM examples WHERE epub_file = ?", (epub_name,))

            for page in iter_epub_pages(epub_path):
                processed_doc_keys.add((epub_name, page.path))
                doc_cur = conn.execute(
                    """
          INSERT INTO documents(epub_file, path, title, chapter_order)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(epub_file, path) DO UPDATE SET
            title = excluded.title,
            chapter_order = excluded.chapter_order
          RETURNING id
          """,
                    (epub_name, page.path, page.title, page.chapter_order),
                )
                row = doc_cur.fetchone()
                if row is None:
                    continue
                doc_id = int(row[0])

                conn.execute("DELETE FROM chunks WHERE doc_id = ?", (doc_id,))

                class_name = normalize_class_name(
                    to_class_name(Path(page.path).stem), page.title, page.text
                )
                chunks = split_chunks(page.text)
                for i, chunk in enumerate(chunks):
                    method_name = guess_method_name(chunk)
                    conn.execute(
                        """
            INSERT INTO chunks(doc_id, chunk_index, heading, class_name, method_name, text)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
                        (doc_id, i, page.title, class_name, method_name, chunk),
                    )
                    inserted_chunks += 1

                class_record = extract_class_record(page.path, page.html)
                if class_record:
                    class_name = class_record["class_name"]
                    conn.execute(
                        """
                        INSERT INTO classes(epub_file, path, class_name, title, inherits, inherited_by, description)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(epub_file, path, class_name) DO UPDATE SET
                          title = excluded.title,
                          inherits = excluded.inherits,
                          inherited_by = excluded.inherited_by,
                          description = excluded.description
                        """,
                        (
                            epub_name,
                            page.path,
                            class_record["class_name"],
                            class_record["title"],
                            class_record["inherits"],
                            class_record["inherited_by"],
                            class_record["description"],
                        ),
                    )
                    classes_upserted += 1

                    conn.execute(
                        "DELETE FROM methods WHERE epub_file = ? AND path = ? AND class_name = ?",
                        (epub_name, page.path, class_name),
                    )
                    conn.execute(
                        "DELETE FROM properties WHERE epub_file = ? AND path = ? AND class_name = ?",
                        (epub_name, page.path, class_name),
                    )

                    for method in extract_method_records(
                        page.path, class_name, page.html
                    ):
                        conn.execute(
                            """
                            INSERT OR IGNORE INTO methods(epub_file, path, class_name, method_name, signature, description)
                            VALUES (?, ?, ?, ?, ?, ?)
                            """,
                            (
                                epub_name,
                                page.path,
                                method["class_name"],
                                method["method_name"],
                                method["signature"],
                                method["description"],
                            ),
                        )
                        methods_upserted += 1

                    for prop in extract_property_records(
                        page.path, class_name, page.html
                    ):
                        conn.execute(
                            """
                            INSERT OR REPLACE INTO properties(
                              epub_file, path, class_name, property_name, type_name,
                              setter_name, getter_name, default_value, description
                            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            (
                                epub_name,
                                page.path,
                                prop["class_name"],
                                prop["property_name"],
                                prop["type_name"],
                                prop["setter_name"],
                                prop["getter_name"],
                                prop["default_value"],
                                prop["description"],
                            ),
                        )
                        properties_upserted += 1

                if page.path.startswith("tutorials/"):
                    conn.execute(
                        "DELETE FROM examples WHERE epub_file = ? AND path = ?",
                        (epub_name, page.path),
                    )
                    for ex in extract_example_records(page.path, class_name, page.html):
                        conn.execute(
                            """
                            INSERT INTO examples(epub_file, path, heading, language, code, context_text, class_name, method_name)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            (
                                epub_name,
                                page.path,
                                ex["heading"],
                                ex["language"],
                                ex["code"],
                                ex["context_text"],
                                ex["class_name"],
                                ex["method_name"],
                            ),
                        )
                        examples_inserted += 1

        conn.commit()
        total_docs = conn.execute("SELECT COUNT(*) FROM documents").fetchone()[0]
        total_chunks = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
        total_classes = conn.execute("SELECT COUNT(*) FROM classes").fetchone()[0]
        total_methods = conn.execute("SELECT COUNT(*) FROM methods").fetchone()[0]
        total_properties = conn.execute("SELECT COUNT(*) FROM properties").fetchone()[0]
        total_examples = conn.execute("SELECT COUNT(*) FROM examples").fetchone()[0]
        return {
            "epub_files": len(epub_files),
            "pages_indexed": len(processed_doc_keys),
            "chunks_inserted": inserted_chunks,
            "classes_upserted": classes_upserted,
            "methods_upserted": methods_upserted,
            "properties_upserted": properties_upserted,
            "examples_inserted": examples_inserted,
            "total_pages": int(total_docs),
            "total_chunks": int(total_chunks),
            "total_classes": int(total_classes),
            "total_methods": int(total_methods),
            "total_properties": int(total_properties),
            "total_examples": int(total_examples),
        }
    finally:
        conn.close()


def to_fts_query(query: str) -> str:
    tokens = re.findall(r"[A-Za-z0-9_]+", query)
    if not tokens:
        return ""
    if len(tokens) == 1:
        return f"{tokens[0]}*"
    return " AND ".join(f"{token}*" for token in tokens[:12])


def search_index(
    index_path: Path,
    query: str,
    limit: int = 8,
    class_name: Optional[str] = None,
    method_name: Optional[str] = None,
) -> List[Dict[str, str]]:
    if not index_path.exists():
        return []
    conn = connect_db(index_path)
    try:
        fts = to_fts_query(query)
        if not fts:
            return []

        sql = """
      SELECT
        c.id,
        d.epub_file,
        d.path,
        c.heading,
        c.class_name,
        c.method_name,
        snippet(chunks_fts, 0, '[', ']', ' ... ', 18) AS snippet,
        bm25(chunks_fts) AS score
      FROM chunks_fts
      JOIN chunks c ON c.id = chunks_fts.rowid
      JOIN documents d ON d.id = c.doc_id
      WHERE chunks_fts MATCH ?
    """
        params: List[object] = [fts]

        if class_name:
            sql += " AND lower(coalesce(c.class_name, '')) = lower(?)"
            params.append(class_name)
        if method_name:
            sql += " AND lower(coalesce(c.method_name, '')) = lower(?)"
            params.append(method_name)

        sql += " ORDER BY score LIMIT ?"
        params.append(max(1, min(limit, 50)))

        rows = conn.execute(sql, params).fetchall()
        return [
            {
                "chunk_id": str(row[0]),
                "epub_file": row[1],
                "path": row[2],
                "heading": row[3] or "",
                "class_name": row[4] or "",
                "method_name": row[5] or "",
                "snippet": row[6] or "",
                "score": f"{float(row[7]):.4f}",
            }
            for row in rows
        ]
    finally:
        conn.close()


def get_chunk(index_path: Path, chunk_id: int) -> Optional[Dict[str, str]]:
    if not index_path.exists():
        return None
    conn = connect_db(index_path)
    try:
        row = conn.execute(
            """
      SELECT
        c.id,
        d.epub_file,
        d.path,
        d.title,
        c.heading,
        c.class_name,
        c.method_name,
        c.text
      FROM chunks c
      JOIN documents d ON d.id = c.doc_id
      WHERE c.id = ?
      """,
            (chunk_id,),
        ).fetchone()
        if row is None:
            return None
        return {
            "chunk_id": str(row[0]),
            "epub_file": row[1],
            "path": row[2],
            "title": row[3] or "",
            "heading": row[4] or "",
            "class_name": row[5] or "",
            "method_name": row[6] or "",
            "text": row[7] or "",
        }
    finally:
        conn.close()


def find_class(index_path: Path, class_name: str) -> Optional[Dict[str, str]]:
    if not index_path.exists():
        return None
    conn = connect_db(index_path)
    try:
        row = conn.execute(
            """
            SELECT class_name, path, title, inherits, inherited_by, description
            FROM classes
            WHERE lower(class_name) = lower(?)
            LIMIT 1
            """,
            (class_name,),
        ).fetchone()
        if row is None:
            return None
        return {
            "class_name": row[0] or "",
            "path": row[1] or "",
            "title": row[2] or "",
            "inherits": row[3] or "",
            "inherited_by": row[4] or "",
            "description": row[5] or "",
        }
    finally:
        conn.close()


def find_method(
    index_path: Path, class_name: str, method_name: str
) -> List[Dict[str, str]]:
    if not index_path.exists():
        return []
    conn = connect_db(index_path)
    try:
        rows = conn.execute(
            """
            SELECT class_name, method_name, signature, description, path
            FROM methods
            WHERE lower(class_name) = lower(?) AND lower(method_name) = lower(?)
            ORDER BY length(signature)
            LIMIT 5
            """,
            (class_name, method_name),
        ).fetchall()
        return [
            {
                "class_name": row[0] or "",
                "method_name": row[1] or "",
                "signature": row[2] or "",
                "description": row[3] or "",
                "path": row[4] or "",
            }
            for row in rows
        ]
    finally:
        conn.close()


def find_property(
    index_path: Path, class_name: str, property_name: str
) -> Optional[Dict[str, str]]:
    if not index_path.exists():
        return None
    conn = connect_db(index_path)
    try:
        row = conn.execute(
            """
            SELECT class_name, property_name, type_name, setter_name, getter_name, default_value, description, path
            FROM properties
            WHERE lower(class_name) = lower(?) AND lower(property_name) = lower(?)
            LIMIT 1
            """,
            (class_name, property_name),
        ).fetchone()
        if row is None:
            return None
        return {
            "class_name": row[0] or "",
            "property_name": row[1] or "",
            "type_name": row[2] or "",
            "setter_name": row[3] or "",
            "getter_name": row[4] or "",
            "default_value": row[5] or "",
            "description": row[6] or "",
            "path": row[7] or "",
        }
    finally:
        conn.close()


def find_examples(
    index_path: Path,
    query: str,
    limit: int = 5,
    class_name: Optional[str] = None,
    method_name: Optional[str] = None,
) -> List[Dict[str, str]]:
    if not index_path.exists():
        return []
    conn = connect_db(index_path)
    try:
        terms = [t for t in re.findall(r"[A-Za-z0-9_]+", query) if t]
        sql = """
            SELECT id, path, heading, language, code, class_name, method_name
            FROM examples
            WHERE 1=1
        """
        params: List[object] = []
        if class_name:
            sql += " AND lower(coalesce(class_name, '')) = lower(?)"
            params.append(class_name)
        if method_name:
            sql += " AND lower(coalesce(method_name, '')) = lower(?)"
            params.append(method_name)
        for term in terms[:6]:
            sql += " AND lower(code) LIKE ?"
            params.append(f"%{term.lower()}%")
        sql += " ORDER BY id DESC LIMIT ?"
        params.append(max(1, min(limit, 20)))

        rows = conn.execute(sql, params).fetchall()
        return [
            {
                "example_id": str(row[0]),
                "path": row[1] or "",
                "heading": row[2] or "",
                "language": row[3] or "",
                "code": row[4] or "",
                "class_name": row[5] or "",
                "method_name": row[6] or "",
            }
            for row in rows
        ]
    finally:
        conn.close()


def suggest_api_for_task(
    index_path: Path, task: str, limit: int = 6
) -> List[Dict[str, str]]:
    hits = search_index(index_path=index_path, query=task, limit=max(limit * 3, 10))
    suggestions: List[Dict[str, str]] = []
    seen = set()
    for hit in hits:
        key = (
            hit.get("class_name", ""),
            hit.get("method_name", ""),
            hit.get("path", ""),
        )
        if key in seen:
            continue
        seen.add(key)
        suggestions.append(
            {
                "class_name": hit.get("class_name", ""),
                "method_name": hit.get("method_name", ""),
                "path": hit.get("path", ""),
                "reason": hit.get("snippet", ""),
            }
        )
        if len(suggestions) >= limit:
            break
    return suggestions


def print_hits(hits: List[Dict[str, str]]) -> None:
    if not hits:
        print("No results.")
        return
    for i, hit in enumerate(hits, start=1):
        print(
            f"[{i}] chunk_id={hit['chunk_id']} score={hit['score']} file={hit['path']}"
        )
        meta = []
        if hit["class_name"]:
            meta.append(f"class={hit['class_name']}")
        if hit["method_name"]:
            meta.append(f"method={hit['method_name']}")
        if hit["heading"]:
            meta.append(f"heading={hit['heading']}")
        if meta:
            print("    " + " | ".join(meta))
        print("    " + hit["snippet"].replace("\n", " "))


def main() -> None:
    stdout_reconfigure = getattr(sys.stdout, "reconfigure", None)
    if callable(stdout_reconfigure):
        stdout_reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(
        description="Build and query a local EPUB documentation index."
    )
    parser.add_argument(
        "--doc-dir",
        default=str(DEFAULT_DOC_DIR),
        help="Directory containing .epub files",
    )
    parser.add_argument(
        "--index", default=str(DEFAULT_DB_PATH), help="SQLite index path"
    )

    sub = parser.add_subparsers(dest="command", required=True)

    build_p = sub.add_parser("build", help="Build/rebuild the SQLite index")
    build_p.add_argument(
        "--force",
        action="store_true",
        help="Delete and re-import content for known EPUB files",
    )

    search_p = sub.add_parser("search", help="Search indexed content")
    search_p.add_argument("query", help="Search query")
    search_p.add_argument("--limit", type=int, default=8)
    search_p.add_argument("--class", dest="class_name", default=None)
    search_p.add_argument("--method", dest="method_name", default=None)

    show_p = sub.add_parser("show", help="Show a specific chunk by ID")
    show_p.add_argument("chunk_id", type=int)

    class_p = sub.add_parser("class", help="Find a class reference")
    class_p.add_argument("class_name")

    method_p = sub.add_parser("method", help="Find method reference")
    method_p.add_argument("class_name")
    method_p.add_argument("method_name")

    prop_p = sub.add_parser("property", help="Find property reference")
    prop_p.add_argument("class_name")
    prop_p.add_argument("property_name")

    examples_p = sub.add_parser("examples", help="Find code examples")
    examples_p.add_argument("query")
    examples_p.add_argument("--class", dest="class_name", default=None)
    examples_p.add_argument("--method", dest="method_name", default=None)
    examples_p.add_argument("--limit", type=int, default=3)

    suggest_p = sub.add_parser("suggest", help="Suggest APIs for a task")
    suggest_p.add_argument("task")
    suggest_p.add_argument("--limit", type=int, default=6)

    args = parser.parse_args()
    doc_dir = Path(args.doc_dir).resolve()
    index_path = Path(args.index).resolve()

    if args.command == "build":
        stats = rebuild_index(doc_dir=doc_dir, index_path=index_path, force=args.force)
        print("Index built successfully.")
        for k, v in stats.items():
            print(f"- {k}: {v}")
        return

    if args.command == "search":
        hits = search_index(
            index_path=index_path,
            query=args.query,
            limit=args.limit,
            class_name=args.class_name,
            method_name=args.method_name,
        )
        print_hits(hits)
        return

    if args.command == "show":
        item = get_chunk(index_path=index_path, chunk_id=args.chunk_id)
        if not item:
            print("Chunk not found.")
            return
        print(f"chunk_id={item['chunk_id']} file={item['path']} title={item['title']}")
        if item["class_name"] or item["method_name"]:
            print(f"class={item['class_name']} method={item['method_name']}")
        print("-" * 80)
        print(item["text"])
        return

    if args.command == "class":
        item = find_class(index_path=index_path, class_name=args.class_name)
        if not item:
            print("Class not found.")
            return
        print(f"class={item['class_name']} path={item['path']}")
        if item["inherits"]:
            print(f"inherits={item['inherits']}")
        if item["inherited_by"]:
            print(f"inherited_by={item['inherited_by']}")
        if item["description"]:
            print(item["description"])
        return

    if args.command == "method":
        items = find_method(
            index_path=index_path,
            class_name=args.class_name,
            method_name=args.method_name,
        )
        if not items:
            print("Method not found.")
            return
        for item in items:
            print(f"{item['class_name']}.{item['method_name']} - {item['path']}")
            print(f"  {item['signature']}")
            if item["description"]:
                print(f"  {item['description'][:400]}")
        return

    if args.command == "property":
        item = find_property(
            index_path=index_path,
            class_name=args.class_name,
            property_name=args.property_name,
        )
        if not item:
            print("Property not found.")
            return
        print(
            f"{item['class_name']}.{item['property_name']} ({item['type_name']}) - {item['path']}"
        )
        print(
            f"setter={item['setter_name']} getter={item['getter_name']} default={item['default_value']}"
        )
        if item["description"]:
            print(item["description"])
        return

    if args.command == "examples":
        items = find_examples(
            index_path=index_path,
            query=args.query,
            class_name=args.class_name,
            method_name=args.method_name,
            limit=args.limit,
        )
        if not items:
            print("No examples found.")
            return
        for item in items:
            print(
                f"example_id={item['example_id']} {item['path']} heading={item['heading']} lang={item['language']}"
            )
            print(item["code"][:500])
            print("-" * 40)
        return

    if args.command == "suggest":
        items = suggest_api_for_task(
            index_path=index_path, task=args.task, limit=args.limit
        )
        if not items:
            print("No suggestions found.")
            return
        for i, item in enumerate(items, start=1):
            print(
                f"[{i}] class={item['class_name']} method={item['method_name']} path={item['path']}"
            )
            print(f"    {item['reason']}")


if __name__ == "__main__":
    main()

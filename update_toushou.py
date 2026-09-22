import sys, os, zipfile, xml.etree.ElementTree as ET, unicodedata

def update_toushou_tsv(cache_dir):
    xlsx_path = os.path.join(cache_dir, "data_j.xlsx")
    tsv_path = os.path.join(cache_dir, "toushou_stocks.tsv")
    
    if not os.path.exists(xlsx_path):
        print(f"XLSX not found: {xlsx_path}")
        return False
        
    z = zipfile.ZipFile(xlsx_path)
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        tree = ET.fromstring(z.read("xl/sharedStrings.xml"))
        for si in tree.findall("{http://schemas.openxmlformats.org/spreadsheetml/2006/main}si"):
            texts = [t.text for t in si.iter("{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t") if t.text]
            shared.append("".join(texts))

    sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
    out_lines = []
    for row in sheet.findall("{http://schemas.openxmlformats.org/spreadsheetml/2006/main}sheetData/{http://schemas.openxmlformats.org/spreadsheetml/2006/main}row")[1:]:
        cells = {}
        for c in row.findall("{http://schemas.openxmlformats.org/spreadsheetml/2006/main}c"):
            ref = c.get("r")
            col = "".join([ch for ch in ref if ch.isalpha()])
            t = c.get("t")
            v = c.find("{http://schemas.openxmlformats.org/spreadsheetml/2006/main}v")
            val = v.text if v is not None else ""
            if t == "s" and val.isdigit():
                val = shared[int(val)]
            cells[col] = val.strip()
        
        code = cells.get("B", "")
        name = unicodedata.normalize("NFKC", cells.get("C", ""))
        market = cells.get("D", "").replace("（内国株式）", "").replace("（外国株式）", "(外)")
        industry = cells.get("F", "")
        if code and name:
            out_lines.append(f"{code}\t{name}\t{market}\t{industry}")

    with open(tsv_path, "w", encoding="utf-8") as f:
        f.write("\n".join(out_lines))
    print(f"Updated {len(out_lines)} stocks to {tsv_path}")
    return True

if __name__ == "__main__":
    cdir = sys.argv[1] if len(sys.argv) > 1 else "."
    update_toushou_tsv(cdir)

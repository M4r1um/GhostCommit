"""
Runs a SQL file against the issue data and saves the result to data/.

Usage: python3 src/run_sql.py sql/<file>.sql
       add --data data/issues.csv to use the old dataset
"""

import argparse
from pathlib import Path

import duckdb
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]


def sql_path_literal(p: Path) -> str:
    return "'" + str(p).replace("'", "''") + "'"


def statements(text: str) -> list[str]:
    # split into statements (ignores ; inside quotes and comments)
    out, buf, i, in_str = [], [], 0, False
    while i < len(text):
        ch = text[i]
        if in_str:
            buf.append(ch)
            if ch == "'":
                if text[i + 1:i + 2] == "'":
                    buf.append("'")
                    i += 1
                else:
                    in_str = False
        elif ch == "'":
            in_str = True
            buf.append(ch)
        elif text.startswith("--", i):
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        elif ch == ";":
            out.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
        i += 1
    out.append("".join(buf))
    return [s.strip() for s in out if s.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sql_file")
    ap.add_argument("--data", default="data/issues_v2.csv")
    ap.add_argument("--out", default=None)
    ap.add_argument("--rows", type=int, default=40, help="rows to print")
    args = ap.parse_args()

    data = (ROOT / args.data).resolve()
    sql_file = (ROOT / args.sql_file).resolve()
    out = (ROOT / args.out) if args.out else ROOT / "data" / f"{sql_file.stem}.csv"

    con = duckdb.connect()
    con.execute("SET TimeZone = 'UTC'")
    con.execute(f"CREATE VIEW issues AS SELECT * FROM read_csv_auto({sql_path_literal(data)}, header=true)")

    optional = {
        "coverage": ROOT / "data" / "sample_coverage_v2.csv",
        "manual_audit": ROOT / "data" / "category_audit_labeled.csv",
    }
    for view, path in optional.items():
        if path.exists():
            con.execute(f"CREATE VIEW {view} AS SELECT * FROM read_csv_auto({sql_path_literal(path)}, header=true, all_varchar=true)")

    for view_file in sorted((ROOT / "sql" / "_views").glob("*.sql")):
        for stmt in statements(view_file.read_text()):
            try:
                con.execute(stmt)
            except duckdb.Error as e:
                # happens with the old csv (missing columns)
                print(f"(skipped shared view {view_file.name}: {str(e).splitlines()[0]})")

    result = None
    for stmt in statements(sql_file.read_text()):
        result = con.execute(stmt)
    df: pd.DataFrame = result.df()

    pd.set_option("display.width", 200)
    pd.set_option("display.max_columns", 30)
    pd.set_option("display.max_colwidth", 60)
    print(df.head(args.rows).to_string(index=False))
    if len(df) > args.rows:
        print(f"... {len(df) - args.rows} more rows")

    out.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out, index=False)
    print(f"\nSaved {len(df)} rows to {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

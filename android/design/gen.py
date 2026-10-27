#!/usr/bin/env python3
"""Єдине джерело правил дизайну: з tokens.json генерує Kotlin (Design.kt) і CSS для макетів."""
import json, pathlib
here = pathlib.Path(__file__).parent
t = json.loads((here / "tokens.json").read_text())
kt = ["package com.bandface.app", "", "import androidx.compose.ui.unit.dp", "import androidx.compose.ui.unit.sp", "",
      "// Згенеровано з android/design/tokens.json (design/gen.py). Не редагувати вручну.", "object Dim {"]
kt += [f"    val {k} = {v}.dp" for k, v in t["dim"].items()]
kt += ["}", "", "object Type {"]
kt += [f"    val {k} = {v}.sp" for k, v in t["type"].items()]
kt += ["}", ""]
(here.parent / "app/src/main/kotlin/com/bandface/app/Design.kt").write_text("\n".join(kt))
css = ":root{" + "".join(f"--{k}:{v}px;" for g in t.values() for k, v in g.items()) + "}\n"
(here / "tokens.css").write_text(css)

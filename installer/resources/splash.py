#!/usr/bin/env python3
"""Fast splash window using logo.png. Stdlib only so it appears before Qt loads."""
from __future__ import annotations

import sys
import tkinter as tk
from pathlib import Path

DURATION_MS = 4000
MAX_WIDTH = 560


def main() -> int:
    resources = Path(__file__).resolve().parent
    logo = resources / "logo.png"
    if not logo.is_file():
        return 0
    try:
        root = tk.Tk()
    except tk.TclError:
        return 0

    root.overrideredirect(True)
    try:
        root.attributes("-topmost", True)
    except tk.TclError:
        pass
    root.configure(bg="#000000")

    img = tk.PhotoImage(file=str(logo))
    width, height = img.width(), img.height()
    if width > MAX_WIDTH:
        factor = max(1, round(width / MAX_WIDTH))
        img = img.subsample(factor, factor)
        width, height = img.width(), img.height()

    root.update_idletasks()
    screen_w = root.winfo_screenwidth()
    screen_h = root.winfo_screenheight()
    x = max(0, (screen_w - width) // 2)
    y = max(0, (screen_h - height) // 2)
    root.geometry(f"{width}x{height}+{x}+{y}")

    label = tk.Label(root, image=img, borderwidth=0, highlightthickness=0, bg="#000000")
    label.image = img
    label.pack()
    root.after(DURATION_MS, root.destroy)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

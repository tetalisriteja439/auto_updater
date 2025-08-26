import os
import tkinter as tk
from tkinter import ttk, messagebox
from __init__ import __version__ as APP_VERSION
import backend

def current_build_label():
    sha = os.getenv("APP_GIT_SHA", "").strip()  # set by PowerShell runner
    ver = APP_VERSION or "dev"
    return f"v{ver} ({sha})" if sha else f"v{ver}"

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(f"MyApp-second – {current_build_label()}")
        self.geometry("500x260")
        self._build()

    def _build(self):
        pad = 12
        frm = ttk.Frame(self, padding=pad)
        frm.pack(fill="both", expand=True)

        self.status = tk.StringVar(value="Ready.")
        ttk.Label(frm, text="Build:").grid(row=0, column=0, sticky="e", padx=(0,6))
        ttk.Label(frm, text=current_build_label()).grid(row=0, column=1, sticky="w")

        ttk.Label(frm, text="Status:").grid(row=1, column=0, sticky="e", padx=(0,6))
        ttk.Label(frm, textvariable=self.status).grid(row=1, column=1, sticky="w")

        ttk.Separator(frm, orient="horizontal").grid(row=2, column=0, columnspan=3, sticky="ew", pady=(pad, pad))

        ttk.Button(frm, text="Check for updates", command=self.on_check_update).grid(row=3, column=0, sticky="e")
        ttk.Button(frm, text="Close", command=self.destroy).grid(row=3, column=1, sticky="w")

        for c in range(3): frm.columnconfigure(c, weight=1)

    def on_check_update(self):
        try:
            self.status.set("Checking GitHub releases...")
            self.update_idletasks()
            latest_tag = backend.get_latest_release_tag()
            # We treat the *checked-out tag* (ref) as current if available; fallback to __version__
            current_tag = os.getenv("APP_CHECKED_OUT_TAG", "").strip() or f"v{APP_VERSION}"
            cmp = backend.compare_versions(current_tag, latest_tag)

            if cmp < 0:
                messagebox.showinfo(
                    "Update available",
                    f"A newer release is available:\nCurrent: {current_tag}\nLatest:  {latest_tag}\n\nPull latest release to update."
                )
                self.status.set(f"Update available: {latest_tag}")
            elif cmp == 0:
                messagebox.showinfo("Up to date", f"You are on the latest release: {latest_tag}")
                self.status.set("You are on the latest release.")
            else:
                messagebox.showinfo("Ahead", f"You are ahead of the latest release:\nCurrent: {current_tag}\nLatest:  {latest_tag}")
                self.status.set("You are ahead of the latest release.")
        except Exception as e:
            messagebox.showerror("Update check failed", str(e))
            self.status.set("Update check failed.")

if __name__ == "__main__":
    App().mainloop()

const { Plugin } = require("obsidian");

module.exports = class BrainUnfogHelperPlugin extends Plugin {
  async onload() {
    this.app.workspace.onLayoutReady(() => {
      this.registerEvent(
        this.app.vault.on("modify", (file) => {
          if (!file || typeof file.path !== "string") {
            return;
          }
          if (!file.path.startsWith("raw/projects/") || !file.path.endsWith(".md")) {
            return;
          }

          this.dispatchInvalidationHint(file.path);
        })
      );
    });
  }

  dispatchInvalidationHint(path) {
    const detail = { path, source: "obsidian-helper" };
    window.dispatchEvent(new CustomEvent("brain-unfog-project-note-modified", { detail }));
  }
};

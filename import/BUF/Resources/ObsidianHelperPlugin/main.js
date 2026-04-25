const { Modal, Notice, Plugin } = require("obsidian");

let codeMirrorView = null;

try {
  codeMirrorView = require("@codemirror/view");
} catch (error) {
  codeMirrorView = null;
}

const TASK_LINE_PATTERN = /^(\s*)- \[[ xX]\] /;
const METADATA_PATTERN = /^(\s*)%%\s*brain-unfog:\s*(\{.*\})\s*%%\s*$/;
const HIDDEN_FRONTMATTER_KEYS = new Set([
  "brain_unfog_project_id",
  "brain_unfog_task_id",
  "calendar_event_external_id",
  "reminder_external_id",
  "reminder_list_external_id",
]);
const COMPLETED_SUBTREE_BODY_CLASS = "brain-unfog-hide-completed-subtrees";

module.exports = class BrainUnfogHelperPlugin extends Plugin {
  async onload() {
    const data = await this.loadData();
    this.hideCompletedSubtrees = data?.hideCompletedSubtrees === true;
    this.registerProjectNoteInvalidationHints();
    this.registerEditorDecorations();
    this.registerMetadataPostProcessor();
    this.registerScheduleContextMenu();
    this.registerCompletedSubtreeToggle();
    this.applyCompletedSubtreeToggleState();
  }

  registerProjectNoteInvalidationHints() {
    this.app.workspace.onLayoutReady(() => {
      this.registerEvent(
        this.app.vault.on("modify", (file) => {
          if (!file || typeof file.path !== "string") {
            return;
          }
          if (!isProjectNotePath(file.path)) {
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

  onunload() {
    document.body.classList.remove(COMPLETED_SUBTREE_BODY_CLASS);
  }

  registerEditorDecorations() {
    if (!codeMirrorView || !codeMirrorView.ViewPlugin || !codeMirrorView.Decoration) {
      return;
    }

    const extension = buildEditorDecorationExtension(codeMirrorView);
    this.registerEditorExtension(extension);
  }

  registerMetadataPostProcessor() {
    this.registerMarkdownPostProcessor((element) => {
      for (const node of element.querySelectorAll("p, div, li")) {
        const text = (node.textContent || "").trim();
        if (isHiddenMetadataLine(text)) {
          node.addClass("brain-unfog-hidden-rendered-metadata");
        }
      }
    });
  }

  registerScheduleContextMenu() {
    this.registerEvent(
      this.app.workspace.on("editor-menu", (menu, editor, view) => {
        if (!view || !view.file || !isProjectNotePath(view.file.path)) {
          return;
        }

        menu.addItem((item) => {
          item
            .setTitle(this.hideCompletedSubtrees ? "완료 subtree 보이기" : "완료 subtree 숨기기")
            .setIcon(this.hideCompletedSubtrees ? "eye" : "eye-off")
            .onClick(() => {
              this.toggleCompletedSubtrees();
            });
        });

        const taskLine = findNearestTaskLine(editor, editor.getCursor().line);
        if (taskLine == null) {
          return;
        }

        menu.addItem((item) => {
          item
            .setTitle("Brain Unfog 날짜 설정")
            .setIcon("calendar-clock")
            .onClick(() => {
              new BrainUnfogScheduleModal(this.app, editor, taskLine).open();
            });
        });
      })
    );
  }

  registerCompletedSubtreeToggle() {
    this.addCommand({
      id: "toggle-completed-task-subtrees",
      name: "완료된 할일 subtree 숨김/표시",
      callback: () => this.toggleCompletedSubtrees(),
    });

    this.addRibbonIcon("list-checks", "완료된 할일 subtree 숨김/표시", () => {
      this.toggleCompletedSubtrees();
    });

    this.completedToggleStatusItem = this.addStatusBarItem();
    this.completedToggleStatusItem.addClass("brain-unfog-completed-toggle-status");
    this.completedToggleStatusItem.addEventListener("click", () => {
      this.toggleCompletedSubtrees();
    });
    this.updateCompletedToggleStatus();
  }

  async toggleCompletedSubtrees() {
    this.hideCompletedSubtrees = !this.hideCompletedSubtrees;
    await this.saveData({ hideCompletedSubtrees: this.hideCompletedSubtrees });
    this.applyCompletedSubtreeToggleState();
    new Notice(this.hideCompletedSubtrees ? "완료된 할일 subtree를 숨깁니다." : "완료된 할일 subtree를 표시합니다.");
  }

  applyCompletedSubtreeToggleState() {
    document.body.classList.toggle(COMPLETED_SUBTREE_BODY_CLASS, this.hideCompletedSubtrees);
    this.updateCompletedToggleStatus();
  }

  updateCompletedToggleStatus() {
    if (!this.completedToggleStatusItem) {
      return;
    }
    this.completedToggleStatusItem.setText(this.hideCompletedSubtrees ? "완료 숨김: 켬" : "완료 숨김: 끔");
  }
};

function buildEditorDecorationExtension(cmView) {
  const hiddenLine = cmView.Decoration.line({ class: "brain-unfog-hidden-line" });
  const completedSubtreeLine = cmView.Decoration.line({
    class: "brain-unfog-completed-subtree-line",
  });

  return cmView.ViewPlugin.fromClass(
    class BrainUnfogEditorDecorationPlugin {
      constructor(view) {
        this.decorations = this.buildDecorations(view);
      }

      update(update) {
        if (update.docChanged || update.viewportChanged) {
          this.decorations = this.buildDecorations(update.view);
        }
      }

      buildDecorations(view) {
        const ranges = [];
        let completedIndent = null;
        for (let lineNumber = 1; lineNumber <= view.state.doc.lines; lineNumber += 1) {
          const line = view.state.doc.line(lineNumber);
          const text = line.text;
          const isBlank = text.trim().length === 0;
          const indentation = leadingWhitespaceWidth(text);

          if (completedIndent != null && !isBlank && indentation <= completedIndent) {
            completedIndent = null;
          }

          if (isHiddenMetadataLine(text)) {
            ranges.push(hiddenLine.range(line.from));
          }
          if (completedIndent != null || isCompletedTaskLine(text)) {
            ranges.push(completedSubtreeLine.range(line.from));
          }
          if (isCompletedTaskLine(text)) {
            completedIndent = indentation;
          }
        }
        return cmView.Decoration.set(ranges, true);
      }
    },
    {
      decorations: (plugin) => plugin.decorations,
    }
  );
}

class BrainUnfogScheduleModal extends Modal {
  constructor(app, editor, taskLine) {
    super(app);
    this.editor = editor;
    this.taskLine = taskLine;
    this.cancelled = false;
    this.state = readScheduleState(editor, taskLine);
    this.visibleMonth = monthStart(parseDate(this.state.date) || new Date());
  }

  onOpen() {
    this.modalEl.addClass("brain-unfog-schedule-modal");
    this.scope.register([], "Escape", () => {
      this.cancelled = true;
      this.close();
      return false;
    });
    this.render();
  }

  onClose() {
    if (!this.cancelled) {
      writeScheduleState(this.editor, this.taskLine, this.state);
    }
    this.contentEl.empty();
  }

  render() {
    this.contentEl.empty();

    const shell = this.contentEl.createDiv({ cls: "brain-unfog-date-popover" });
    const header = shell.createDiv({ cls: "brain-unfog-date-header" });
    const previous = header.createEl("button", { text: "<", cls: "brain-unfog-month-button" });
    const title = header.createDiv({
      text: monthTitle(this.visibleMonth),
      cls: "brain-unfog-month-title",
    });
    const next = header.createEl("button", { text: ">", cls: "brain-unfog-month-button" });

    previous.addEventListener("click", () => {
      this.visibleMonth = addMonths(this.visibleMonth, -1);
      this.render();
    });
    next.addEventListener("click", () => {
      this.visibleMonth = addMonths(this.visibleMonth, 1);
      this.render();
    });

    const weekdays = shell.createDiv({ cls: "brain-unfog-weekdays" });
    for (const label of ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]) {
      weekdays.createDiv({ text: label, cls: "brain-unfog-weekday" });
    }

    const grid = shell.createDiv({ cls: "brain-unfog-day-grid" });
    for (const day of monthGridDays(this.visibleMonth)) {
      const dateString = formatDate(day);
      const button = grid.createEl("button", {
        text: String(day.getDate()),
        cls: "brain-unfog-day",
      });
      if (day.getMonth() !== this.visibleMonth.getMonth()) {
        button.addClass("is-outside-month");
      }
      if (dateString === formatDate(new Date())) {
        button.addClass("is-today");
      }
      if (dateString === this.state.date) {
        button.addClass("is-selected");
      }
      button.addEventListener("click", () => {
        this.state.date = dateString;
        this.render();
      });
    }

    const scheduleRow = shell.createDiv({ cls: "brain-unfog-schedule-row" });
    const timeInput = scheduleRow.createEl("input", { type: "time" });
    timeInput.value = this.state.time || "";
    timeInput.addEventListener("change", () => {
      this.state.time = timeInput.value.trim();
      if (this.state.time && !this.state.duration) {
        this.state.duration = "15";
        this.render();
      }
    });

    scheduleRow.createDiv({ text: ":", cls: "brain-unfog-time-separator" });

    const durationInput = scheduleRow.createEl("input", { type: "number" });
    durationInput.min = "1";
    durationInput.step = "5";
    durationInput.placeholder = this.state.time ? "15" : "";
    durationInput.value = this.state.duration || "";
    durationInput.addEventListener("change", () => {
      this.state.duration = durationInput.value.trim();
    });

    title.addEventListener("dblclick", () => {
      this.visibleMonth = monthStart(new Date());
      this.state.date = formatDate(new Date());
      this.render();
    });
  }
}

function isProjectNotePath(path) {
  return path.startsWith("raw/projects/") && path.endsWith(".md");
}

function isHiddenMetadataLine(line) {
  const trimmed = line.trim();
  if (trimmed.startsWith("%% brain-unfog:")) {
    return true;
  }
  const key = trimmed.split(":", 1)[0];
  return HIDDEN_FRONTMATTER_KEYS.has(key);
}

function isCompletedTaskLine(line) {
  const markerStart = line.trimStart();
  return markerStart.startsWith("- [x] ") || markerStart.startsWith("- [X] ");
}

function findNearestTaskLine(editor, startLine) {
  const maxLookBehind = 12;
  for (let line = startLine; line >= 0 && line >= startLine - maxLookBehind; line -= 1) {
    if (TASK_LINE_PATTERN.test(editor.getLine(line))) {
      return line;
    }
  }
  return null;
}

function readScheduleState(editor, taskLine) {
  const metadata = readTaskMetadata(editor, taskLine).metadata || {};
  return {
    date: typeof metadata.date === "string" && metadata.date ? metadata.date : formatDate(new Date()),
    time: typeof metadata.time === "string" ? metadata.time : "",
    duration: metadata.duration == null ? "" : String(metadata.duration),
  };
}

function writeScheduleState(editor, taskLine, state) {
  const metadataResult = readTaskMetadata(editor, taskLine);
  if (metadataResult.damaged) {
    new Notice("Brain Unfog metadata가 손상되어 날짜를 쓸 수 없습니다.");
    return;
  }

  const metadata = metadataResult.metadata || {};
  metadata.date = state.date;
  if (state.time) {
    metadata.time = state.time;
    metadata.duration = Number.parseInt(state.duration || "15", 10);
  } else {
    delete metadata.time;
    if (state.duration) {
      metadata.duration = Number.parseInt(state.duration, 10);
    } else {
      delete metadata.duration;
    }
  }

  const taskText = editor.getLine(taskLine);
  const indent = (taskText.match(TASK_LINE_PATTERN) || ["", ""])[1] + "  ";
  const line = `${indent}%% brain-unfog: ${orderedMetadataJSON(metadata)} %%`;

  if (metadataResult.line != null) {
    editor.replaceRange(
      line,
      { line: metadataResult.line, ch: 0 },
      { line: metadataResult.line, ch: editor.getLine(metadataResult.line).length }
    );
  } else {
    editor.replaceRange(`\n${line}`, {
      line: taskLine,
      ch: editor.getLine(taskLine).length,
    });
  }
}

function readTaskMetadata(editor, taskLine) {
  const taskText = editor.getLine(taskLine);
  const taskIndent = leadingWhitespaceWidth(taskText);
  const line = taskLine + 1;
  if (line >= editor.lineCount()) {
    return { line: null, metadata: null, damaged: false };
  }

  const text = editor.getLine(line);
  if (leadingWhitespaceWidth(text) <= taskIndent) {
    return { line: null, metadata: null, damaged: false };
  }

  const match = text.match(METADATA_PATTERN);
  if (!match) {
    return { line: null, metadata: null, damaged: false };
  }

  try {
    return { line, metadata: JSON.parse(match[2]), damaged: false };
  } catch (error) {
    return { line, metadata: null, damaged: true };
  }
}

function orderedMetadataJSON(metadata) {
  const ordered = {};
  for (const key of ["reminder_external_id", "date", "time", "duration", "repeat"]) {
    if (metadata[key] != null && metadata[key] !== "") {
      ordered[key] = metadata[key];
    }
  }
  for (const key of Object.keys(metadata).sort()) {
    if (!(key in ordered) && metadata[key] != null && metadata[key] !== "") {
      ordered[key] = metadata[key];
    }
  }
  return JSON.stringify(ordered);
}

function leadingWhitespaceWidth(text) {
  let width = 0;
  for (const character of text) {
    if (character === " ") {
      width += 1;
    } else if (character === "\t") {
      width += 2;
    } else {
      break;
    }
  }
  return width;
}

function parseDate(value) {
  if (typeof value !== "string") {
    return null;
  }
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) {
    return null;
  }
  return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
}

function formatDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function monthStart(date) {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function addMonths(date, count) {
  return new Date(date.getFullYear(), date.getMonth() + count, 1);
}

function monthTitle(date) {
  return date.toLocaleDateString(undefined, { month: "long", year: "numeric" });
}

function monthGridDays(month) {
  const first = monthStart(month);
  const start = new Date(first);
  start.setDate(first.getDate() - first.getDay());
  const days = [];
  for (let index = 0; index < 42; index += 1) {
    const day = new Date(start);
    day.setDate(start.getDate() + index);
    days.push(day);
  }
  return days;
}

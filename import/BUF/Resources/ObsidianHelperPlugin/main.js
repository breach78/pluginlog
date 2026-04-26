const { Modal, Notice, Plugin } = require("obsidian");

let codeMirrorView = null;

try {
  codeMirrorView = require("@codemirror/view");
} catch (error) {
  codeMirrorView = null;
}

const TASK_LINE_PATTERN = /^(\s*)- \[[ xX]\] /;
const METADATA_PATTERN = /^(\s*)%%\s*brain-unfog:\s*(\{.*\})\s*%%\s*$/;
const REMINDER_LIST_PROPERTY_KEY = "reminder_list_external_id";
const HIDE_COMPLETED_PROPERTY_KEY = "완료 가리기";
let activeSchedulePopover = null;

const HIDDEN_FRONTMATTER_KEYS = new Set([
  "brain_unfog_project_id",
  "brain_unfog_task_id",
  "brain_unfog_color_hex",
  "calendar_event_external_id",
  "reminder_external_id",
  "reminder_list_external_id",
]);

module.exports = class BrainUnfogHelperPlugin extends Plugin {
  async onload() {
    this.registerProjectNoteInvalidationHints();
    this.registerEditorDecorations();
    this.registerMetadataPostProcessor();
    this.registerScheduleContextMenu();
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
    closeActiveSchedulePopover(false);
  }

  registerEditorDecorations() {
    if (
      !codeMirrorView
      || !codeMirrorView.ViewPlugin
      || !codeMirrorView.Decoration
      || !codeMirrorView.WidgetType
    ) {
      return;
    }

    const extension = buildEditorDecorationExtension(codeMirrorView);
    this.registerEditorExtension(extension);
  }

  registerMetadataPostProcessor() {
    this.registerMarkdownPostProcessor((element, context) => {
      if (!isProjectNotePath(context?.sourcePath || "")) {
        return;
      }
      const frontmatter = frontmatterForSourcePath(this.app, context?.sourcePath);
      if (!isReminderSyncedFrontmatter(frontmatter)) {
        return;
      }
      for (const node of element.querySelectorAll("p, div, li")) {
        const text = (node.textContent || "").trim();
        if (isHiddenMetadataLine(text)) {
          node.addClass("brain-unfog-hidden-rendered-metadata");
        }
      }
      const shouldHide = hideCompletedFromFrontmatter(frontmatter);
      element.classList.toggle("brain-unfog-completed-subtree-scope", shouldHide);
    });
  }

  registerScheduleContextMenu() {
    this.registerEvent(
      this.app.workspace.on("editor-menu", (menu, editor, view) => {
        if (!view || !isReminderSyncedProjectFile(this.app, view.file)) {
          return;
        }

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
};

function buildEditorDecorationExtension(cmView) {
  const hiddenLine = cmView.Decoration.line({ class: "brain-unfog-hidden-line" });
  const completedSubtreeLine = cmView.Decoration.line({
    class: "brain-unfog-completed-subtree-line",
  });
  class BrainUnfogScheduleWidget extends cmView.WidgetType {
    constructor(taskLineIndex, state) {
      super();
      this.taskLineIndex = taskLineIndex;
      this.state = state;
    }

    eq(other) {
      return (
        other.taskLineIndex === this.taskLineIndex
        && other.state.date === this.state.date
        && other.state.time === this.state.time
        && other.state.duration === this.state.duration
        && other.state.repeat === this.state.repeat
      );
    }

    toDOM(view) {
      const wrapper = document.createElement("span");
      wrapper.className = "brain-unfog-task-schedule-widget";

      const trigger = document.createElement("button");
      trigger.type = "button";
      trigger.className = "brain-unfog-task-schedule-trigger";
      trigger.setAttribute("aria-label", "Brain Unfog 날짜 설정");
      trigger.addEventListener("mousedown", (event) => event.preventDefault());
      trigger.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        openSchedulePopover(view, this.taskLineIndex, trigger);
      });

      const chips = scheduleChips(this.state);
      for (const chip of chips) {
        const element = document.createElement("span");
        element.className = `brain-unfog-schedule-chip ${chip.className}`;
        element.textContent = chip.label;
        trigger.appendChild(element);
      }
      wrapper.appendChild(trigger);
      return wrapper;
    }
  }

  const scheduleWidget = (taskLineIndex, metadata) => {
    const state = scheduleStateFromMetadata(metadata);
    if (!hasScheduleDisplay(state)) {
      return null;
    }
    return cmView.Decoration.widget({
      widget: new BrainUnfogScheduleWidget(taskLineIndex, state),
      side: 1,
    });
  };

  const completedSubtreeExtension = cmView.ViewPlugin.fromClass(
    class BrainUnfogCompletedSubtreeDecorationPlugin {
      constructor(view) {
        this.projectState = projectFrontmatterStateFromDoc(view.state.doc);
        this.frontmatterSignature = this.projectState.signature;
        this.decorations = buildCompletedSubtreeDecorations(
          cmView,
          completedSubtreeLine,
          view.state.doc,
          this.projectState
        );
      }

      update(update) {
        if (!update.docChanged) {
          return;
        }

        const projectState = projectFrontmatterStateFromDoc(update.view.state.doc);
        if (projectState.signature === this.frontmatterSignature) {
          this.decorations = this.decorations.map(update.changes);
          return;
        }

        this.projectState = projectState;
        this.frontmatterSignature = projectState.signature;
        this.decorations = buildCompletedSubtreeDecorations(
          cmView,
          completedSubtreeLine,
          update.view.state.doc,
          projectState
        );
      }
    },
    {
      decorations: (plugin) => plugin.decorations,
    }
  );

  const visibleLineExtension = cmView.ViewPlugin.fromClass(
    class BrainUnfogVisibleLineDecorationPlugin {
      constructor(view) {
        this.projectState = projectFrontmatterStateFromDoc(view.state.doc);
        this.frontmatterSignature = this.projectState.signature;
        this.decorations = this.buildDecorations(view);
      }

      update(update) {
        if (update.docChanged) {
          const projectState = projectFrontmatterStateFromDoc(update.view.state.doc);
          if (projectState.signature !== this.frontmatterSignature) {
            this.projectState = projectState;
            this.frontmatterSignature = projectState.signature;
          }
        }
        if (update.docChanged || update.viewportChanged) {
          this.decorations = this.buildDecorations(update.view);
        }
      }

      buildDecorations(view) {
        if (!this.projectState.isReminderSyncedProject) {
          return cmView.Decoration.set([], true);
        }
        const ranges = [];
        const seenLines = new Set();
        const visibleRanges = visibleLineRanges(view);

        for (const range of visibleRanges) {
          for (let lineNumber = range.from; lineNumber <= range.to; lineNumber += 1) {
            if (seenLines.has(lineNumber)) {
              continue;
            }
            seenLines.add(lineNumber);

            const line = view.state.doc.line(lineNumber);
            const text = line.text;
            if (isHiddenMetadataLine(text)) {
              ranges.push(hiddenLine.range(line.from));
            }
            if (TASK_LINE_PATTERN.test(text)) {
              const metadata = readTaskMetadataFromDoc(view.state.doc, lineNumber - 1).metadata || {};
              const widget = scheduleWidget(lineNumber - 1, metadata);
              if (widget) {
                ranges.push(widget.range(line.to));
              }
            }
          }
        }
        return cmView.Decoration.set(ranges, true);
      }
    },
    {
      decorations: (plugin) => plugin.decorations,
    }
  );

  return [completedSubtreeExtension, visibleLineExtension];
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
    renderDatePicker(shell, {
      selectedDate: this.state.date,
      visibleMonth: this.visibleMonth,
      onMonthChange: (month) => {
        this.visibleMonth = month;
        this.render();
      },
      onDateSelect: (date) => {
        this.state.date = date;
        this.render();
      },
      onTitleDoubleClick: () => {
        this.visibleMonth = monthStart(new Date());
        this.state.date = formatDate(new Date());
        this.render();
      },
    });

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

  }
}

class BrainUnfogInlineSchedulePopover {
  constructor(view, taskLine, anchor, state) {
    this.view = view;
    this.taskLine = taskLine;
    this.anchor = anchor;
    this.state = { ...state };
    this.visibleMonth = monthStart(parseDate(this.state.date) || new Date());
    this.root = null;
    this.outsideHandler = null;
    this.keyHandler = null;
  }

  open() {
    this.root = document.createElement("div");
    this.root.className = "brain-unfog-inline-schedule-popover";
    document.body.appendChild(this.root);
    this.render();
    this.position();
    this.outsideHandler = (event) => {
      if (this.root?.contains(event.target) || this.anchor.contains(event.target)) {
        return;
      }
      this.close(false);
    };
    this.keyHandler = (event) => {
      if (event.key === "Escape") {
        event.preventDefault();
        this.close(false);
      }
    };
    setTimeout(() => document.addEventListener("pointerdown", this.outsideHandler, true), 0);
    document.addEventListener("keydown", this.keyHandler, true);
  }

  close(commit) {
    if (commit) {
      writeScheduleStateToView(this.view, this.taskLine, this.state);
    }
    if (this.outsideHandler) {
      document.removeEventListener("pointerdown", this.outsideHandler, true);
    }
    if (this.keyHandler) {
      document.removeEventListener("keydown", this.keyHandler, true);
    }
    this.root?.remove();
    if (activeSchedulePopover === this) {
      activeSchedulePopover = null;
    }
    this.view.focus();
  }

  position() {
    if (!this.root) {
      return;
    }
    const rect = this.anchor.getBoundingClientRect();
    const width = this.root.offsetWidth || 236;
    const height = this.root.offsetHeight || 318;
    const left = Math.max(8, Math.min(rect.left, window.innerWidth - width - 8));
    const below = rect.bottom + 8;
    const top = below + height > window.innerHeight - 8
      ? Math.max(8, rect.top - height - 8)
      : below;
    this.root.style.left = `${left}px`;
    this.root.style.top = `${top}px`;
  }

  render() {
    this.root.replaceChildren();
    const shell = document.createElement("div");
    shell.className = "brain-unfog-date-popover";
    this.root.appendChild(shell);
    renderDatePicker(shell, {
      selectedDate: this.state.date,
      visibleMonth: this.visibleMonth,
      onMonthChange: (month) => {
        this.visibleMonth = month;
        this.render();
        this.position();
      },
      onDateSelect: (date) => {
        this.state.date = date;
        this.render();
        this.position();
      },
    });

    const fields = document.createElement("div");
    fields.className = "brain-unfog-inline-schedule-fields";
    shell.appendChild(fields);
    const timeInput = labeledInput(fields, "시간", "time");
    timeInput.value = this.state.time || "";
    timeInput.addEventListener("change", () => {
      this.state.time = timeInput.value.trim();
      if (this.state.time && !this.state.duration) {
        this.state.duration = "15";
        this.render();
        this.position();
      }
    });

    const durationInput = labeledInput(fields, "듀레이션", "number");
    durationInput.min = "1";
    durationInput.step = "5";
    durationInput.placeholder = this.state.time ? "15" : "";
    durationInput.value = this.state.duration || "";
    durationInput.addEventListener("change", () => {
      this.state.duration = durationInput.value.trim();
    });

    const actions = document.createElement("div");
    actions.className = "brain-unfog-inline-schedule-actions";
    shell.appendChild(actions);
    const clear = scheduleButton("지우기", "brain-unfog-inline-secondary-button");
    const save = scheduleButton("저장", "brain-unfog-inline-primary-button");
    actions.append(clear, save);
    clear.addEventListener("click", () => {
      this.state.date = "";
      this.state.time = "";
      this.state.duration = "";
      this.close(true);
    });
    save.addEventListener("click", () => this.close(true));
  }
}

function scheduleButton(text, className) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = className;
  button.textContent = text;
  return button;
}

function labeledInput(container, labelText, type) {
  const label = document.createElement("label");
  label.className = "brain-unfog-inline-schedule-field";
  const caption = document.createElement("span");
  caption.textContent = labelText;
  const input = document.createElement("input");
  input.type = type;
  label.append(caption, input);
  container.appendChild(label);
  return input;
}

function openSchedulePopover(view, taskLine, anchor) {
  closeActiveSchedulePopover(false);
  const state = scheduleStateFromMetadata(
    readTaskMetadataFromDoc(view.state.doc, taskLine).metadata || {},
    { defaultDate: false }
  );
  activeSchedulePopover = new BrainUnfogInlineSchedulePopover(view, taskLine, anchor, state);
  activeSchedulePopover.open();
}

function closeActiveSchedulePopover(commit) {
  activeSchedulePopover?.close(commit);
}

function renderDatePicker(container, options) {
  const header = document.createElement("div");
  header.className = "brain-unfog-date-header";
  const previous = scheduleButton("<", "brain-unfog-month-button");
  const title = document.createElement("div");
  title.className = "brain-unfog-month-title";
  title.textContent = monthTitle(options.visibleMonth);
  const next = scheduleButton(">", "brain-unfog-month-button");
  header.append(previous, title, next);
  container.appendChild(header);

  previous.addEventListener("click", () => {
    options.onMonthChange(addMonths(options.visibleMonth, -1));
  });
  next.addEventListener("click", () => {
    options.onMonthChange(addMonths(options.visibleMonth, 1));
  });
  if (options.onTitleDoubleClick) {
    title.addEventListener("dblclick", options.onTitleDoubleClick);
  }

  const weekdays = document.createElement("div");
  weekdays.className = "brain-unfog-weekdays";
  for (const label of ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]) {
    const weekday = document.createElement("div");
    weekday.className = "brain-unfog-weekday";
    weekday.textContent = label;
    weekdays.appendChild(weekday);
  }
  container.appendChild(weekdays);

  const grid = document.createElement("div");
  grid.className = "brain-unfog-day-grid";
  for (const day of monthGridDays(options.visibleMonth)) {
    const dateString = formatDate(day);
    const button = scheduleButton(String(day.getDate()), "brain-unfog-day");
    button.classList.toggle("is-outside-month", day.getMonth() !== options.visibleMonth.getMonth());
    button.classList.toggle("is-today", dateString === formatDate(new Date()));
    button.classList.toggle("is-selected", dateString === options.selectedDate);
    button.addEventListener("click", () => options.onDateSelect(dateString));
    grid.appendChild(button);
  }
  container.appendChild(grid);
}

function isProjectNotePath(path) {
  return path.startsWith("raw/projects/") && path.endsWith(".md");
}

function isReminderSyncedProjectFile(app, file) {
  if (!file || !isProjectNotePath(file.path || "")) {
    return false;
  }
  return isReminderSyncedFrontmatter(frontmatterForFile(app, file));
}

function frontmatterForFile(app, file) {
  if (!app?.metadataCache || !file) {
    return null;
  }
  return app.metadataCache.getFileCache?.(file)?.frontmatter
    || frontmatterForSourcePath(app, file.path);
}

function frontmatterForSourcePath(app, path) {
  if (!app?.metadataCache || !path) {
    return null;
  }
  return app.metadataCache.getCache?.(path)?.frontmatter || null;
}

function isReminderSyncedFrontmatter(frontmatter) {
  return Boolean(normalizedScalar(frontmatter?.[REMINDER_LIST_PROPERTY_KEY]));
}

function hideCompletedFromFrontmatter(frontmatter) {
  return hideCompletedValue(frontmatter?.[HIDE_COMPLETED_PROPERTY_KEY]);
}

function projectFrontmatterStateFromDoc(doc) {
  const lines = frontmatterLinesFromDoc(doc);
  const reminderListID = normalizedScalar(frontmatterScalar(lines, REMINDER_LIST_PROPERTY_KEY));
  const shouldHideCompleted = hideCompletedValue(frontmatterScalar(lines, HIDE_COMPLETED_PROPERTY_KEY));
  const isReminderSyncedProject = Boolean(reminderListID);
  return {
    isReminderSyncedProject,
    shouldHideCompletedLines: isReminderSyncedProject && shouldHideCompleted,
    signature: `${reminderListID || ""}|${shouldHideCompleted ? "hide" : "show"}`,
  };
}

function hideCompletedValue(value) {
  if (value == null) {
    return true;
  }
  return booleanValue(value) === true;
}

function frontmatterLinesFromDoc(doc) {
  if (doc.lines < 2 || doc.line(1).text.trim() !== "---") {
    return null;
  }
  const lines = [];
  for (let lineNumber = 2; lineNumber <= doc.lines; lineNumber += 1) {
    const text = doc.line(lineNumber).text;
    if (text.trim() === "---") {
      return lines;
    }
    lines.push(text);
  }
  return null;
}

function frontmatterScalar(lines, key) {
  if (!Array.isArray(lines)) {
    return null;
  }
  for (const line of lines) {
    if (/^\s/.test(line)) {
      continue;
    }
    const colonIndex = line.indexOf(":");
    if (colonIndex < 0) {
      continue;
    }
    const lineKey = line.slice(0, colonIndex).trim();
    if (lineKey === key) {
      return line.slice(colonIndex + 1).trim();
    }
  }
  return null;
}

function normalizedScalar(value) {
  if (value == null) {
    return null;
  }
  const scalar = String(value).trim().replace(/^["']|["']$/g, "");
  return scalar ? scalar : null;
}

function booleanValue(value) {
  if (value === true || value === false) {
    return value;
  }
  switch (normalizedScalar(value)?.toLowerCase()) {
    case "true":
    case "yes":
    case "on":
      return true;
    default:
      return false;
  }
}

function buildCompletedSubtreeDecorations(cmView, completedSubtreeLine, doc, projectState) {
  const ranges = [];
  for (const lineNumber of completedSubtreeLineNumbers(doc, projectState)) {
    ranges.push(completedSubtreeLine.range(doc.line(lineNumber).from));
  }
  return cmView.Decoration.set(ranges, true);
}

function completedSubtreeLineNumbers(doc, projectState) {
  const lineNumbers = new Set();
  if (!projectState.shouldHideCompletedLines) {
    return lineNumbers;
  }

  const completedIndents = [];
  for (let lineNumber = 1; lineNumber <= doc.lines; lineNumber += 1) {
    const text = doc.line(lineNumber).text;
    if (text.trim().length === 0) {
      if (completedIndents.length > 0) {
        lineNumbers.add(lineNumber);
      }
      continue;
    }

    const indentation = leadingWhitespaceWidth(text);
    while (
      completedIndents.length > 0
      && indentation <= completedIndents[completedIndents.length - 1]
    ) {
      completedIndents.pop();
    }

    if (isCompletedTaskLine(text)) {
      lineNumbers.add(lineNumber);
      completedIndents.push(indentation);
    } else if (completedIndents.length > 0) {
      lineNumbers.add(lineNumber);
    }
  }
  return lineNumbers;
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
  return scheduleStateFromMetadata(metadata, { defaultDate: true });
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

function readTaskMetadataFromDoc(doc, taskLine) {
  const taskText = doc.line(taskLine + 1).text;
  const taskIndent = leadingWhitespaceWidth(taskText);
  const metadataLine = taskLine + 1;
  if (metadataLine >= doc.lines) {
    return { line: null, metadata: null, damaged: false };
  }

  const line = doc.line(metadataLine + 1);
  if (leadingWhitespaceWidth(line.text) <= taskIndent) {
    return { line: null, metadata: null, damaged: false };
  }

  const match = line.text.match(METADATA_PATTERN);
  if (!match) {
    return { line: null, metadata: null, damaged: false };
  }

  try {
    return { line: metadataLine, metadata: JSON.parse(match[2]), damaged: false };
  } catch (error) {
    return { line: metadataLine, metadata: null, damaged: true };
  }
}

function writeScheduleStateToView(view, taskLine, state) {
  const metadataResult = readTaskMetadataFromDoc(view.state.doc, taskLine);
  if (metadataResult.damaged) {
    new Notice("Brain Unfog metadata가 손상되어 날짜를 쓸 수 없습니다.");
    return;
  }

  const metadata = metadataResult.metadata || {};
  if (state.date) {
    metadata.date = state.date;
  } else {
    delete metadata.date;
  }
  if (state.time) {
    metadata.time = state.time;
  } else {
    delete metadata.time;
  }
  const duration = normalizedDuration(state.duration);
  if (duration) {
    metadata.duration = duration;
  } else {
    delete metadata.duration;
  }

  if (Object.keys(metadata).length === 0 && metadataResult.line == null) {
    return;
  }

  const taskLineInfo = view.state.doc.line(taskLine + 1);
  const indent = (taskLineInfo.text.match(TASK_LINE_PATTERN) || ["", ""])[1] + "  ";
  const metadataLineText = `${indent}%% brain-unfog: ${orderedMetadataJSON(metadata)} %%`;
  if (metadataResult.line != null) {
    const line = view.state.doc.line(metadataResult.line + 1);
    view.dispatch({ changes: { from: line.from, to: line.to, insert: metadataLineText } });
  } else {
    view.dispatch({ changes: { from: taskLineInfo.to, insert: `\n${metadataLineText}` } });
  }
}

function scheduleStateFromMetadata(metadata, options = {}) {
  const date = typeof metadata.date === "string" && metadata.date ? metadata.date : "";
  return {
    date: date || (options.defaultDate ? formatDate(new Date()) : ""),
    time: typeof metadata.time === "string" ? metadata.time : "",
    duration: metadata.duration == null ? "" : String(metadata.duration),
    repeat: typeof metadata.repeat === "string" && metadata.repeat ? metadata.repeat : "",
  };
}

function normalizedDuration(value) {
  if (value == null || value === "") {
    return null;
  }
  const duration = Number.parseInt(String(value), 10);
  return Number.isFinite(duration) && duration > 0 ? duration : null;
}

function hasScheduleDisplay(state) {
  return Boolean(state.date || state.time || state.duration || state.repeat);
}

function scheduleChips(state) {
  const chips = [];
  if (state.date) {
    chips.push({ label: displayDate(state.date), className: "is-date" });
  }
  if (state.time) {
    chips.push({ label: state.time, className: "is-time" });
  }
  if (state.duration) {
    chips.push({ label: `${state.duration}m`, className: "is-duration" });
  }
  if (state.repeat) {
    chips.push({ label: "반복", className: "is-repeat" });
  }
  return chips;
}

function displayDate(value) {
  const date = parseDate(value);
  if (!date) {
    return value;
  }
  const now = new Date();
  if (date.getFullYear() === now.getFullYear()) {
    return `${date.getMonth() + 1}.${date.getDate()}`;
  }
  return `${date.getFullYear()}.${date.getMonth() + 1}.${date.getDate()}`;
}

function visibleLineRanges(view) {
  const ranges = [];
  for (const range of view.visibleRanges || []) {
    const from = view.state.doc.lineAt(range.from).number;
    const to = view.state.doc.lineAt(range.to).number;
    ranges.push({ from, to });
  }
  if (ranges.length === 0 && view.viewport) {
    ranges.push({
      from: view.state.doc.lineAt(view.viewport.from).number,
      to: view.state.doc.lineAt(view.viewport.to).number,
    });
  }
  return ranges;
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

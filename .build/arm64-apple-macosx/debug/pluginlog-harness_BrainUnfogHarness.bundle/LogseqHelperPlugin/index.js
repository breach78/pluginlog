(function () {
  const contextMenuTitle = "날짜/시간 설정";
  const defaultDurationMinutes = "15";
  const monthNames = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];
  const weekdayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];

  const state = {
    visible: false,
    blockIdentity: null,
    selectedDate: startOfDay(new Date()),
    viewYear: new Date().getFullYear(),
    viewMonth: new Date().getMonth(),
    timeValue: "",
    durationValue: "",
  };

  function main() {
    mount();
    logseq.setMainUIInlineStyle({
      position: "fixed",
      inset: "0",
      zIndex: 999,
      background: "transparent",
    });

    logseq.Editor.registerBlockContextMenuItem(contextMenuTitle, async (event) => {
      const blockIdentity = event.uuid || event.blockUuid || event.blockId;
      if (!blockIdentity) {
        logseq.App.showMsg("선택한 블록을 찾지 못했습니다.", "warning");
        return;
      }
      await openPicker(blockIdentity);
    });
  }

  function mount() {
    const app = document.getElementById("app");
    app.innerHTML = "<div class=\"buf-overlay\" data-role=\"overlay\"></div>";

    const overlay = getOverlay();
    overlay.addEventListener("mousedown", (event) => {
      if (event.target === overlay) {
        event.preventDefault();
        saveAndClose();
      }
    });

    window.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && state.visible) {
        event.preventDefault();
        closeWithoutSaving();
      }
    });
  }

  async function openPicker(blockIdentity) {
    state.blockIdentity = blockIdentity;
    const existing = await readExistingSchedule(blockIdentity);
    state.selectedDate = existing.date || startOfDay(new Date());
    state.viewYear = state.selectedDate.getFullYear();
    state.viewMonth = state.selectedDate.getMonth();
    state.timeValue = existing.timeValue || "";
    state.durationValue = state.timeValue
      ? (existing.durationValue || defaultDurationMinutes)
      : "";
    state.visible = true;

    render();
    logseq.showMainUI({ autoFocus: true });
    focusFirstFieldSoon();
  }

  async function readExistingSchedule(blockIdentity) {
    try {
      const properties = await logseq.Editor.getBlockProperties(blockIdentity);
      const dateValue = propertyString(properties.date);
      const durationValue = normalizedDuration(propertyString(properties.duration)) || "";
      const parsed = parseDateValue(dateValue);
      return {
        date: parsed ? parsed.date : null,
        timeValue: parsed && parsed.timeValue ? parsed.timeValue : "",
        durationValue,
      };
    } catch (error) {
      console.error(error);
      return { date: null, timeValue: "", durationValue: "" };
    }
  }

  function render() {
    const overlay = getOverlay();
    overlay.innerHTML = `
      <section class="buf-picker" role="dialog" aria-label="날짜와 시간 설정">
        <div class="buf-month-row">
          <button class="buf-nav" type="button" data-action="prev" aria-label="이전 달">&lt;</button>
          <div class="buf-month">${monthNames[state.viewMonth]} ${state.viewYear}</div>
          <button class="buf-nav" type="button" data-action="next" aria-label="다음 달">&gt;</button>
        </div>
        <div class="buf-weekdays">
          ${weekdayNames.map((day) => `<div class="buf-weekday">${day}</div>`).join("")}
        </div>
        <div class="buf-days">
          ${calendarDays().map(renderDay).join("")}
        </div>
        <div class="buf-fields">
          <input class="buf-input buf-time" data-role="time" inputmode="numeric" placeholder="--:--" value="${escapeAttribute(state.timeValue)}" aria-label="시간">
          <span class="buf-separator">:</span>
          <input class="buf-input buf-duration" data-role="duration" inputmode="numeric" value="${escapeAttribute(state.durationValue)}" aria-label="기간">
        </div>
      </section>
    `;

    overlay.querySelector("[data-action=\"prev\"]").addEventListener("click", () => changeMonth(-1));
    overlay.querySelector("[data-action=\"next\"]").addEventListener("click", () => changeMonth(1));
    overlay.querySelectorAll("[data-date]").forEach((button) => {
      button.addEventListener("click", () => {
        const nextDate = parseDateValue(button.dataset.date);
        if (!nextDate) return;
        state.selectedDate = nextDate.date;
        state.viewYear = state.selectedDate.getFullYear();
        state.viewMonth = state.selectedDate.getMonth();
        render();
      });
    });

    wireInputs();
  }

  function renderDay(day) {
    const className = [
      "buf-day",
      day.isCurrentMonth ? "" : "is-outside",
      sameDay(day.date, state.selectedDate) ? "is-selected" : "",
    ].filter(Boolean).join(" ");
    return `
      <div class="buf-day-cell">
        <button class="${className}" type="button" data-date="${formatDate(day.date)}">${day.date.getDate()}</button>
      </div>
    `;
  }

  function wireInputs() {
    const timeInput = document.querySelector("[data-role=\"time\"]");
    const durationInput = document.querySelector("[data-role=\"duration\"]");

    const ensureTimedDefaults = () => {
      if (!state.timeValue.trim()) {
        state.timeValue = currentTimeValue();
        timeInput.value = state.timeValue;
      }
      if (!state.durationValue.trim()) {
        state.durationValue = defaultDurationMinutes;
        durationInput.value = state.durationValue;
      }
    };

    timeInput.addEventListener("focus", ensureTimedDefaults);
    timeInput.addEventListener("click", ensureTimedDefaults);
    timeInput.addEventListener("input", () => {
      state.timeValue = timeInput.value.trim();
      if (normalizedTime(state.timeValue) && !state.durationValue.trim()) {
        state.durationValue = defaultDurationMinutes;
        durationInput.value = state.durationValue;
      }
    });

    durationInput.addEventListener("input", () => {
      state.durationValue = durationInput.value.trim();
    });
  }

  function changeMonth(delta) {
    const next = new Date(state.viewYear, state.viewMonth + delta, 1);
    state.viewYear = next.getFullYear();
    state.viewMonth = next.getMonth();
    render();
  }

  async function saveAndClose() {
    if (!state.visible || !state.blockIdentity) return;

    const timeValue = state.timeValue.trim();
    const time = timeValue ? normalizedTime(timeValue) : "";
    if (timeValue && !time) {
      logseq.App.showMsg("시간은 HH:mm 형식으로 입력해 주세요.", "warning");
      return;
    }

    const duration = time ? (normalizedDuration(state.durationValue) || defaultDurationMinutes) : "";
    if (time && state.durationValue.trim() && !duration) {
      logseq.App.showMsg("duration은 분 단위 숫자로 입력해 주세요.", "warning");
      return;
    }

    const dateValue = time ? `${formatDate(state.selectedDate)} ${time}` : formatDate(state.selectedDate);

    try {
      await logseq.Editor.upsertBlockProperty(state.blockIdentity, "date", dateValue);
      if (time) {
        await logseq.Editor.upsertBlockProperty(state.blockIdentity, "duration", duration);
      } else {
        await logseq.Editor.removeBlockProperty(state.blockIdentity, "duration");
      }
      hidePicker();
    } catch (error) {
      console.error(error);
      logseq.App.showMsg("날짜 정보를 저장하지 못했습니다.", "error");
    }
  }

  function closeWithoutSaving() {
    hidePicker();
  }

  function hidePicker() {
    state.visible = false;
    state.blockIdentity = null;
    getOverlay().innerHTML = "";
    logseq.hideMainUI({ restoreEditingCursor: true });
  }

  function focusFirstFieldSoon() {
    setTimeout(() => {
      const picker = document.querySelector(".buf-picker");
      if (picker) picker.focus();
    }, 0);
  }

  function calendarDays() {
    const firstOfMonth = new Date(state.viewYear, state.viewMonth, 1);
    const start = new Date(state.viewYear, state.viewMonth, 1 - firstOfMonth.getDay());
    return Array.from({ length: 42 }, (_, index) => {
      const date = new Date(start.getFullYear(), start.getMonth(), start.getDate() + index);
      return {
        date,
        isCurrentMonth: date.getMonth() === state.viewMonth,
      };
    });
  }

  function parseDateValue(value) {
    if (!value) return null;
    const match = String(value).trim().match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2}))?$/);
    if (!match) return null;

    const year = Number(match[1]);
    const month = Number(match[2]) - 1;
    const day = Number(match[3]);
    const hour = match[4] == null ? 0 : Number(match[4]);
    const minute = match[5] == null ? 0 : Number(match[5]);
    const date = new Date(year, month, day, hour, minute);
    if (Number.isNaN(date.getTime())) return null;

    return {
      date: startOfDay(date),
      timeValue: match[4] == null ? "" : `${pad2(hour)}:${pad2(minute)}`,
    };
  }

  function normalizedTime(value) {
    const match = String(value).trim().match(/^(\d{1,2}):(\d{2})$/);
    if (!match) return "";
    const hour = Number(match[1]);
    const minute = Number(match[2]);
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return "";
    return `${pad2(hour)}:${pad2(minute)}`;
  }

  function normalizedDuration(value) {
    const trimmed = String(value || "").trim();
    if (!trimmed) return "";
    if (!/^\d+$/.test(trimmed)) return "";
    const minutes = Number(trimmed);
    if (!Number.isFinite(minutes) || minutes <= 0) return "";
    return String(minutes);
  }

  function currentTimeValue() {
    const now = new Date();
    return `${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
  }

  function formatDate(date) {
    return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
  }

  function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
  }

  function sameDay(lhs, rhs) {
    return formatDate(lhs) === formatDate(rhs);
  }

  function pad2(value) {
    return String(value).padStart(2, "0");
  }

  function propertyString(value) {
    if (value == null) return "";
    if (Array.isArray(value)) return value.join(" ").trim();
    return String(value).trim();
  }

  function escapeAttribute(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function getOverlay() {
    return document.querySelector("[data-role=\"overlay\"]");
  }

  logseq.ready(main).catch(console.error);
})();

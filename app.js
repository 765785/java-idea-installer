(() => {
  "use strict";

  const ICONS = {
    check: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6"></path></svg>',
    alert: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 9v4M12 17h.01"></path><path d="M10.3 3.7 2.5 17.2A2 2 0 0 0 4.2 20h15.6a2 2 0 0 0 1.7-2.8L13.7 3.7a2 2 0 0 0-3.4 0Z"></path></svg>',
    close: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="m9 9 6 6M15 9l-6 6"></path></svg>',
    coffee: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 8h12v5a6 6 0 0 1-6 6h0a6 6 0 0 1-6-6V8Z"></path><path d="M17 10h1a3 3 0 0 1 0 6h-2M8 3v2M12 3v2"></path></svg>',
    code: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m8 9-3 3 3 3M16 9l3 3-3 3M14 5l-4 14"></path></svg>',
    home: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m3 11 9-8 9 8"></path><path d="M5 10v10h14V10M9 20v-6h6v6"></path></svg>',
  };
  const FIX_ACTIONS = new Set([
    "java_home",
    "path",
    "multiple_jdks",
    "idea_repair",
    "gatekeeper",
    "vc_runtime",
    "port",
  ]);

  const state = {
    detectedOs: "unsupported",
    selectedOs: "unsupported",
    currentReport: null,
    currentAction: "install",
  };

  const elements = {
    html: document.documentElement,
    themeToggle: document.querySelector("#themeToggle"),
    systemDetection: document.querySelector("#systemDetection"),
    systemText: document.querySelector("#systemText"),
    startDetection: document.querySelector("#startDetection"),
    osChoices: document.querySelector("#osChoices"),
    osChoiceButtons: [...document.querySelectorAll(".os-choice")],
    downloadActions: document.querySelector("#downloadActions"),
    downloadPackage: document.querySelector("#downloadPackage"),
    downloadMeta: document.querySelector("#downloadMeta"),
    resultFileInput: document.querySelector("#resultFileInput"),
    dropZone: document.querySelector("#dropZone"),
    reportEmpty: document.querySelector("#reportEmpty"),
    reportContent: document.querySelector("#reportContent"),
    resetReport: document.querySelector("#resetReport"),
    reportSummaryTitle: document.querySelector("#reportSummaryTitle"),
    reportSummaryMeta: document.querySelector("#reportSummaryMeta"),
    summaryCounts: document.querySelector("#summaryCounts"),
    componentList: document.querySelector("#componentList"),
    healthSection: document.querySelector("#healthSection"),
    healthList: document.querySelector("#healthList"),
    nextActionTitle: document.querySelector("#nextActionTitle"),
    nextActionCopy: document.querySelector("#nextActionCopy"),
    nextActionButton: document.querySelector("#nextActionButton"),
    progressSection: document.querySelector("#progress"),
    progressPercent: document.querySelector("#progressPercent"),
    progressBar: document.querySelector("#progressBar"),
    progressMessage: document.querySelector("#progressMessage"),
    progressSteps: document.querySelector("#progressSteps"),
    guideDialog: document.querySelector("#guideDialog"),
    guideTitle: document.querySelector("#guideTitle"),
    guideSteps: document.querySelector("#guideSteps"),
    guideDownload: document.querySelector("#guideDownload"),
    commandDialog: document.querySelector("#commandDialog"),
    commandTitle: document.querySelector("#commandTitle"),
    commandDescription: document.querySelector("#commandDescription"),
    commandText: document.querySelector("#commandText"),
    copyCommand: document.querySelector("#copyCommand"),
    toast: document.querySelector("#toast"),
  };

  let toastTimer = null;

  function init() {
    initTheme();
    bindEvents();
    detectSystem();
    restoreResultFromHash();
  }

  function initTheme() {
    const stored = localStorage.getItem("java-setup-theme");
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    setTheme(stored || (prefersDark ? "dark" : "light"));
  }

  function setTheme(theme) {
    const nextTheme = theme === "dark" ? "dark" : "light";
    elements.html.dataset.theme = nextTheme;
    const dark = nextTheme === "dark";
    elements.themeToggle.setAttribute("aria-pressed", String(dark));
    elements.themeToggle.setAttribute("aria-label", dark ? "切换到浅色主题" : "切换到深色主题");
    localStorage.setItem("java-setup-theme", nextTheme);
  }

  function bindEvents() {
    elements.themeToggle.addEventListener("click", () => {
      setTheme(elements.html.dataset.theme === "dark" ? "light" : "dark");
    });

    elements.startDetection.addEventListener("click", () => {
      selectOs(state.detectedOs, true);
      document.querySelector("#report").scrollIntoView({ behavior: "smooth", block: "start" });
      if (state.detectedOs === "windows" || state.detectedOs === "macos") {
        window.setTimeout(() => openGuide(state.detectedOs), 420);
      } else {
        showToast("当前系统暂未自动支持，请看其他系统的手动安装建议。");
      }
    });

    elements.osChoiceButtons.forEach((button) => {
      button.addEventListener("click", () => {
        const os = button.dataset.os;
        selectOs(os, true);
        if (os === "windows" || os === "macos") {
          openGuide(os);
        } else {
          showToast("Windows 与 macOS 可以直接使用工具包，其他系统请参考手动安装说明。");
        }
      });
    });

    elements.downloadPackage.addEventListener("click", () => {
      markStep("install");
      showToast("工具包开始下载，解压后运行 install 脚本。");
    });

    elements.resultFileInput.addEventListener("change", (event) => {
      const [file] = event.target.files;
      if (file) {
        readResultFile(file);
      }
    });

    elements.dropZone.addEventListener("click", () => elements.resultFileInput.click());
    elements.dropZone.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        elements.resultFileInput.click();
      }
    });

    ["dragenter", "dragover"].forEach((eventName) => {
      elements.dropZone.addEventListener(eventName, (event) => {
        event.preventDefault();
        elements.dropZone.classList.add("is-dragging");
      });
    });

    ["dragleave", "drop"].forEach((eventName) => {
      elements.dropZone.addEventListener(eventName, (event) => {
        event.preventDefault();
        elements.dropZone.classList.remove("is-dragging");
      });
    });

    elements.dropZone.addEventListener("drop", (event) => {
      const [file] = event.dataTransfer.files;
      if (file) {
        readResultFile(file);
      }
    });

    elements.resetReport.addEventListener("click", resetReport);
    elements.nextActionButton.addEventListener("click", handleNextAction);
    elements.copyCommand.addEventListener("click", copyFixCommand);

    document.querySelectorAll("[data-close-dialog]").forEach((button) => {
      button.addEventListener("click", () => button.closest("dialog")?.close());
    });

    document.querySelectorAll("dialog").forEach((dialog) => {
      dialog.addEventListener("click", (event) => {
        if (event.target === dialog) {
          dialog.close();
        }
      });
    });

    window.addEventListener("hashchange", restoreResultFromHash);
  }

  async function detectSystem() {
    const fallback = detectSystemFromUserAgent();
    let result = fallback;

    if (navigator.userAgentData?.getHighEntropyValues) {
      try {
        const values = await navigator.userAgentData.getHighEntropyValues(["platform", "platformVersion", "architecture"]);
        if (values.platform === "Windows") {
          const major = Number.parseInt(values.platformVersion || "0", 10);
          result = {
            os: "windows",
            label: major >= 13 ? "Windows 11" : "Windows 10",
            architecture: values.architecture || fallback.architecture,
          };
        } else if (values.platform === "macOS") {
          result = {
            os: "macos",
            label: formatMacVersion(values.platformVersion || ""),
            architecture: values.architecture || fallback.architecture,
          };
        }
      } catch {
        result = fallback;
      }
    }

    state.detectedOs = result.os;
    elements.systemDetection.classList.toggle("is-ready", result.os !== "unsupported");
    elements.systemDetection.classList.toggle("is-unsupported", result.os === "unsupported");
    elements.systemText.textContent = result.os === "unsupported"
      ? "暂未支持自动安装，请查看手动建议"
      : `检测到您的系统：${result.label}`;
    selectOs(result.os, false);
  }

  function detectSystemFromUserAgent() {
    const ua = navigator.userAgent;
    if (/Windows NT 10\.0/i.test(ua)) {
      return { os: "windows", label: "Windows 10 / 11", architecture: "" };
    }
    if (/Macintosh|Mac OS X/i.test(ua)) {
      const match = ua.match(/Mac OS X[_\s](\d+)[_.](\d+)/i);
      const version = match ? `${match[1]}.${match[2]}` : "";
      return { os: "macos", label: formatMacVersion(version), architecture: "" };
    }
    return { os: "unsupported", label: "其他系统", architecture: "" };
  }

  function formatMacVersion(version) {
    const [major] = version.split(".").map(Number);
    const names = {
      11: "macOS Big Sur",
      12: "macOS Monterey",
      13: "macOS Ventura",
      14: "macOS Sonoma",
      15: "macOS Sequoia",
      16: "macOS Tahoe",
    };
    return names[major] || (version ? `macOS ${version}` : "macOS");
  }

  function selectOs(os, scrollToDownloads) {
    const supported = os === "windows" || os === "macos";
    state.selectedOs = os;
    elements.osChoiceButtons.forEach((button) => {
      button.classList.toggle("is-selected", button.dataset.os === os);
    });

    elements.downloadActions.hidden = !supported;
    if (!supported) {
      return;
    }

    const extension = os === "windows" ? "windows" : "macos";
    elements.downloadPackage.href = `./downloads/java-idea-toolkit-${extension}.zip`;
    elements.downloadPackage.setAttribute("download", `java-idea-toolkit-${extension}.zip`);

    elements.downloadMeta.textContent = os === "windows"
      ? "解压后双击 detect.bat；安装时双击 install.bat。"
      : "解压后双击 detect.command，或在终端运行 detect.sh。";

    if (scrollToDownloads) {
      elements.downloadActions.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }
  }

  function openGuide(os) {
    if (os !== "windows" && os !== "macos") {
      return;
    }

    state.selectedOs = os;
    selectOs(os, false);
    elements.guideTitle.textContent = os === "windows" ? "运行 Windows 检测工具包" : "运行 macOS 检测工具包";

    const steps = os === "windows"
      ? [
          "点击下载工具包，并解压到“下载”文件夹。",
          "双击 detect.bat。如系统询问权限，请先看清来源后允许。",
          "脚本会生成 detection_result.json，并自动尝试打开本页回传结果。",
          "如果页面没有自动更新，把 detection_result.json 拖到检测报告区域。",
        ]
      : [
          "点击下载工具包，并解压到“下载”文件夹。",
          "双击 detect.command；如果系统拦截，右键选择“打开”。",
          "终端会完成检测，并自动尝试打开本页回传结果。",
          "如果页面没有自动更新，把 detection_result.json 拖到检测报告区域。",
        ];

    elements.guideSteps.replaceChildren(...steps.map((step) => {
      const item = document.createElement("li");
      item.textContent = step;
      return item;
    }));
    elements.guideDownload.href = `./downloads/java-idea-toolkit-${os}.zip`;
    elements.guideDownload.setAttribute("download", `java-idea-toolkit-${os}.zip`);
    elements.guideDialog.showModal();
  }

  async function readResultFile(file) {
    if (file.size > 1024 * 1024) {
      showToast("结果文件过大，请确认它确实由本工具生成。");
      return;
    }

    try {
      const text = await file.text();
      const data = JSON.parse(text.replace(/^\uFEFF/, ""));
      acceptResult(data, "文件");
    } catch (error) {
      showToast(`无法读取结果：${error.message}`);
    } finally {
      elements.resultFileInput.value = "";
    }
  }

  function restoreResultFromHash() {
    const hash = window.location.hash.startsWith("#") ? window.location.hash.slice(1) : window.location.hash;
    const params = new URLSearchParams(hash);
    const encoded = params.get("result");
    if (!encoded) {
      return;
    }
    if (encoded.length > 90000) {
      showToast("URL 中的结果过长，请改用 JSON 文件上传。");
      return;
    }

    try {
      const json = decodeBase64Url(encoded);
      acceptResult(JSON.parse(json), "URL");
    } catch {
      showToast("#result 数据无法解析，请重新运行检测脚本或上传 JSON 文件。");
    }
  }

  function decodeBase64Url(value) {
    const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    const binary = atob(padded);
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    return new TextDecoder("utf-8").decode(bytes);
  }

  function acceptResult(data, source) {
    if (!data || typeof data !== "object") {
      throw new Error("结果不是有效的 JSON 对象");
    }

    state.currentReport = data;
    if (data.action && Array.isArray(data.steps)) {
      state.currentAction = data.action;
      renderProgress(data);
    } else {
      renderDetection(data, source);
    }

    elements.resetReport.hidden = false;
    const target = data.action ? "#progress" : "#report";
    window.setTimeout(() => document.querySelector(target)?.scrollIntoView({ behavior: "smooth", block: "start" }), 80);
  }

  function renderDetection(data, source) {
    const components = normalizeComponents(data);
    const health = Array.isArray(data.health)
      ? data.health.slice(0, 100).filter((item) => item && typeof item === "object")
      : [];
    const totals = normalizeSummary(data.summary) || calculateTotals(components, health);

    elements.reportEmpty.hidden = true;
    elements.reportContent.hidden = false;
    elements.progressSection.hidden = true;
    elements.reportSummaryTitle.textContent = totals.errors > 0 ? "还需要完成安装" : totals.warnings > 0 ? "环境基本可用" : "环境状态良好";
    const generated = data.generatedAt ? formatDate(data.generatedAt) : "刚刚";
    const origin = source === "URL" ? "脚本已自动回传" : `由 ${source} 导入`;
    elements.reportSummaryMeta.textContent = `${origin} · ${generated}`;

    elements.summaryCounts.replaceChildren(
      makeCount("正常", totals.ok, "is-ok"),
      makeCount("提醒", totals.warnings, "is-warning"),
      makeCount("缺失", totals.errors, "is-error"),
    );

    elements.componentList.replaceChildren(...components.map(renderComponent));
    elements.healthSection.hidden = health.length === 0;
    elements.healthList.replaceChildren(...health.map(renderHealthItem));

    const needsInstall = totals.errors > 0 || totals.warnings > 0;
    state.currentAction = needsInstall ? "install" : "verify";
    elements.nextActionTitle.textContent = needsInstall ? "下一步：安装或修复环境" : "下一步：打开 IDEA 验证";
    elements.nextActionCopy.textContent = needsInstall
      ? "下载当前系统的安装工具包；脚本会跳过已经正常的组件。"
      : "环境已通过检测，可以打开 IntelliJ IDEA 创建第一个 Java 项目。";
    elements.nextActionButton.textContent = needsInstall ? "下载安装工具包" : "查看验证步骤";
    markStep(needsInstall ? "install" : "verify");
  }

  function normalizeComponents(data) {
    const raw = data.components || {};
    const definitions = [
      { key: "jdk", title: "Java (JDK 25)", icon: ICONS.coffee, aliases: ["jdk", "java"] },
      { key: "idea", title: "IntelliJ IDEA Community", icon: ICONS.code, aliases: ["idea"] },
      { key: "javaHome", title: "JAVA_HOME", icon: ICONS.home, aliases: ["javaHome", "java_home", "JAVA_HOME"] },
    ];

    return definitions.map((definition) => {
      const source = definition.aliases.map((alias) => raw[alias]).find(Boolean) || {};
      return {
        ...definition,
        status: normalizeStatus(source.status),
        version: source.version || source.latestVersion || "",
        path: source.path || source.javaHome || "",
        message: source.message || "",
      };
    });
  }

  function normalizeStatus(status) {
    if (["ok", "installed", "latest", "valid"].includes(status)) {
      return "ok";
    }
    if (["outdated", "upgrade", "warning", "invalid", "unknown"].includes(status)) {
      return "warning";
    }
    if (["missing", "error", "failed"].includes(status)) {
      return "error";
    }
    return "neutral";
  }

  function calculateTotals(components, health) {
    return {
      ok: components.filter((item) => item.status === "ok").length,
      warnings: components.filter((item) => item.status === "warning").length + health.filter((item) => item.severity !== "error").length,
      errors: components.filter((item) => item.status === "error").length + health.filter((item) => item.severity === "error").length,
    };
  }

  function normalizeSummary(summary) {
    if (!summary || typeof summary !== "object") {
      return null;
    }
    const values = ["ok", "warnings", "errors"].map((key) => Number(summary[key]));
    if (!values.every(Number.isFinite)) {
      return null;
    }
    return {
      ok: values[0],
      warnings: values[1],
      errors: values[2],
    };
  }

  function makeCount(label, value, className) {
    const pill = document.createElement("div");
    pill.className = `count-pill ${className}`;
    const strong = document.createElement("strong");
    strong.textContent = String(value);
    const span = document.createElement("span");
    span.textContent = label;
    pill.append(strong, span);
    return pill;
  }

  function renderComponent(component) {
    const row = document.createElement("article");
    row.className = "component-row";

    const icon = document.createElement("div");
    icon.className = "component-icon";
    icon.innerHTML = component.icon;

    const copy = document.createElement("div");
    copy.className = "component-copy";
    const title = document.createElement("h4");
    title.textContent = component.title;
    const detail = document.createElement("p");
    detail.textContent = component.message || component.path || component.version || statusCopy(component.status);
    copy.append(title, detail);

    const status = document.createElement("span");
    status.className = `component-status status-${component.status}`;
    status.innerHTML = component.status === "ok" ? ICONS.check : component.status === "error" ? ICONS.close : component.status === "warning" ? ICONS.alert : "";
    const label = document.createElement("span");
    label.textContent = component.status === "ok"
      ? component.version ? `已安装 ${component.version}` : "状态正常"
      : component.status === "warning"
        ? component.version ? `需更新 ${component.version}` : "需要留意"
        : component.status === "error"
          ? "未安装"
          : "未确认";
    status.append(label);

    row.append(icon, copy, status);
    return row;
  }

  function statusCopy(status) {
    return {
      ok: "状态正常",
      warning: "需要检查",
      error: "未安装",
      neutral: "未确认",
    }[status];
  }

  function renderHealthItem(item) {
    const wrapper = document.createElement("div");
    wrapper.className = "health-item";

    const copy = document.createElement("div");
    copy.className = "health-copy";
    const title = document.createElement("strong");
    title.textContent = item.title || healthTitle(item.id);
    const detail = document.createElement("span");
    detail.textContent = item.message || "检测到需要处理的环境问题。";
    copy.append(title, detail);

    if (item.fixable === false || !FIX_ACTIONS.has(item.action)) {
      const status = document.createElement("span");
      status.className = "component-status status-neutral";
      status.textContent = item.fixable === false ? "仅提示" : "需手动处理";
      wrapper.append(copy, status);
      return wrapper;
    }

    const button = document.createElement("button");
    button.className = "button button-secondary small-button";
    button.type = "button";
    button.textContent = "一键修复";
    button.addEventListener("click", () => showFixCommand(item.action, title.textContent));
    wrapper.append(copy, button);
    return wrapper;
  }

  function healthTitle(id) {
    const titles = {
      java_home: "JAVA_HOME 配置异常",
      path: "PATH 缺少 JDK bin",
      multiple_jdks: "检测到多个 JDK",
      idea_repair: "IDEA 可能损坏",
      gatekeeper: "macOS Gatekeeper 拦截",
      vc_runtime: "缺少 VC++ 运行库",
      port: "开发端口被占用",
    };
    return titles[id] || "环境健康问题";
  }

  function showFixCommand(action, title) {
    const os = state.selectedOs;
    const command = os === "windows"
      ? `.\\install.bat --fix ${action}`
      : `./install.sh --fix ${action}`;
    elements.commandTitle.textContent = title;
    elements.commandDescription.textContent = "先解压安装工具包，在工具包目录中运行以下命令：";
    elements.commandText.textContent = command;
    elements.commandDialog.showModal();
  }

  async function copyFixCommand() {
    try {
      await navigator.clipboard.writeText(elements.commandText.textContent);
      showToast("命令已复制。");
    } catch {
      showToast("复制失败，请手动选择命令文本。");
    }
  }

  function renderProgress(data) {
    elements.reportContent.hidden = true;
    elements.reportEmpty.hidden = true;
    elements.progressSection.hidden = false;
    const percent = clampPercent(data.percent);
    elements.progressPercent.textContent = `${percent}%`;
    elements.progressBar.style.width = `${percent}%`;
    elements.progressMessage.textContent = data.message || progressStatusCopy(data.status);
    const steps = (Array.isArray(data.steps) ? data.steps : [])
      .slice(0, 100)
      .filter((step) => step && typeof step === "object");
    elements.progressSteps.replaceChildren(...steps.map((step) => {
      const item = document.createElement("li");
      item.className = `progress-step is-${normalizeProgressStatus(step.status)}`;
      const title = document.createElement("strong");
      title.textContent = step.label || step.id || "处理中";
      const status = document.createElement("span");
      status.textContent = progressStatusCopy(step.status);
      item.append(title, status);
      return item;
    }));
  }

  function normalizeProgressStatus(status) {
    if (["complete", "completed", "success"].includes(status)) {
      return "complete";
    }
    if (["failed", "error"].includes(status)) {
      return "failed";
    }
    if (["running", "active"].includes(status)) {
      return "active";
    }
    return "pending";
  }

  function progressStatusCopy(status) {
    return {
      running: "正在执行",
      active: "正在执行",
      complete: "已完成",
      completed: "已完成",
      success: "已完成",
      failed: "失败",
      error: "失败",
      success_result: "全部完成",
      partial: "部分完成，请查看提示",
    }[status] || "等待中";
  }

  function clampPercent(value) {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(0, Math.min(100, Math.round(number))) : 0;
  }

  function resetReport() {
    state.currentReport = null;
    elements.reportContent.hidden = true;
    elements.progressSection.hidden = true;
    elements.reportEmpty.hidden = false;
    elements.resetReport.hidden = true;
    elements.resultFileInput.value = "";
    history.replaceState(null, "", window.location.pathname + window.location.search);
    document.querySelector("#report").scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function handleNextAction() {
    if (state.currentAction === "verify") {
      markStep("verify");
      showToast("打开 IDEA，新建 Java 项目并运行 Hello World 即可。");
      return;
    }
    selectOs(state.selectedOs, true);
    if (state.selectedOs === "windows" || state.selectedOs === "macos") {
      openGuide(state.selectedOs);
    }
  }

  function markStep(step) {
    const order = ["detect", "install", "verify"];
    const currentIndex = order.indexOf(step);
    document.querySelectorAll(".step-item").forEach((item, index) => {
      item.classList.toggle("is-complete", index < currentIndex);
      item.classList.toggle("is-active", index === currentIndex);
    });
  }

  function formatDate(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return value;
    }
    return new Intl.DateTimeFormat("zh-CN", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    }).format(date);
  }

  function showToast(message) {
    window.clearTimeout(toastTimer);
    elements.toast.textContent = message;
    elements.toast.hidden = false;
    toastTimer = window.setTimeout(() => {
      elements.toast.hidden = true;
    }, 4200);
  }

  init();
})();

(() => {
  "use strict";

  const params = new URLSearchParams(window.location.search);
  const defaultReturnUrl = "https://765785.github.io/java-idea-installer/";
  const returnUrl = getSafeReturnUrl(params.get("return"));
  const progressToken = params.get("token") || "";
  const terminalStates = new Set(["success", "partial", "failed"]);
  const elements = {
    title: document.querySelector("#title"),
    percent: document.querySelector("#percent"),
    bar: document.querySelector("#bar"),
    message: document.querySelector("#message"),
    steps: document.querySelector("#steps"),
    notice: document.querySelector("#connectionNotice"),
    actions: document.querySelector("#actions"),
    returnLink: document.querySelector("#returnLink"),
    log: document.querySelector("#log"),
  };
  let failures = 0;
  let stopped = false;

  function getSafeReturnUrl(value) {
    if (!value) {
      return defaultReturnUrl;
    }
    try {
      const url = new URL(value);
      if (url.protocol === "https:" && url.hostname === "765785.github.io" && url.pathname.startsWith("/java-idea-installer/")) {
        return url.href;
      }
      if (url.protocol === "http:" && ["127.0.0.1", "localhost"].includes(url.hostname)) {
        return url.href;
      }
    } catch {
      return defaultReturnUrl;
    }
    return defaultReturnUrl;
  }

  function encodeBase64Url(value) {
    const bytes = new TextEncoder().encode(value);
    let binary = "";
    bytes.forEach((byte) => {
      binary += String.fromCharCode(byte);
    });
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  }

  function statusText(status) {
    return {
      pending: "等待中",
      running: "正在执行",
      complete: "已完成",
      failed: "失败",
      success: "全部完成",
      partial: "部分完成",
    }[status] || "处理中";
  }

  function render(data) {
    if (!data || typeof data !== "object") {
      throw new Error("进度 JSON 不是对象");
    }
    const percent = Math.max(0, Math.min(100, Math.round(Number(data.percent) || 0)));
    elements.percent.textContent = `${percent}%`;
    elements.bar.style.width = `${percent}%`;
    elements.message.textContent = data.message || statusText(data.status);
    elements.title.textContent = data.status === "failed"
      ? "安装遇到问题"
      : terminalStates.has(data.status)
        ? "处理已经结束"
        : "正在处理你的环境";
    elements.notice.hidden = true;
    failures = 0;

    const steps = Array.isArray(data.steps)
      ? data.steps.slice(0, 100).filter((step) => step && typeof step === "object")
      : [];
    elements.steps.replaceChildren(...steps.map((step) => {
      const item = document.createElement("li");
      item.className = `step ${step.status || "pending"}`;
      const title = document.createElement("strong");
      title.textContent = step.label || step.id || "处理中";
      const status = document.createElement("span");
      const seconds = Number(step.estimatedSeconds) || 0;
      status.textContent = `${statusText(step.status)}${seconds ? ` · 预计约 ${seconds} 秒` : ""}`;
      item.append(title, status);
      return item;
    }));

    if (data.log) {
      elements.log.hidden = false;
      elements.log.textContent = String(data.log).slice(0, 20000);
      elements.log.scrollTop = elements.log.scrollHeight;
    }

    if (terminalStates.has(data.status)) {
      stopped = true;
      elements.actions.hidden = false;
      if (data.result) {
        const encoded = encodeBase64Url(JSON.stringify(data.result));
        const separator = returnUrl.includes("#") ? "&" : "#";
        elements.returnLink.href = `${returnUrl}${separator}result=${encoded}`;
      } else {
        elements.returnLink.href = returnUrl;
      }
    }
  }

  async function poll() {
    if (stopped) {
      return;
    }

    try {
      const query = new URLSearchParams({ t: String(Date.now()) });
      if (progressToken) {
        query.set("token", progressToken);
      }
      const response = await fetch(`progress.json?${query.toString()}`, { cache: "no-store" });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      render(await response.json());
    } catch {
      failures += 1;
      if (failures >= 2) {
        elements.notice.hidden = false;
      }
    }

    window.setTimeout(poll, 2000);
  }

  poll();
})();

(() => {
  "use strict";

  const PUBLIC_ORIGIN = "https://765785.github.io";
  const params = new URLSearchParams(window.location.hash.slice(1));
  const elements = {
    panel: document.querySelector("#panel"),
    mark: document.querySelector("#mark"),
    title: document.querySelector("#title"),
    message: document.querySelector("#message"),
    state: document.querySelector("#state"),
    returnLink: document.querySelector("#returnLink"),
  };

  function setFailure(message) {
    elements.panel.className = "error";
    elements.mark.textContent = "!";
    elements.title.textContent = "无法启动修复";
    elements.message.textContent = message;
    elements.state.textContent = "请返回检测报告，重新运行新版检测脚本。";
    elements.returnLink.hidden = false;
  }

  function safePublicReturn(value) {
    try {
      const url = new URL(value || PUBLIC_ORIGIN);
      if (url.protocol === "https:" && url.origin === PUBLIC_ORIGIN && url.pathname.startsWith("/java-idea-installer/")) {
        return url.href;
      }
      if (url.protocol === "http:" && ["127.0.0.1", "localhost"].includes(url.hostname)) {
        return url.href;
      }
    } catch {
      return PUBLIC_ORIGIN + "/java-idea-installer/";
    }
    return PUBLIC_ORIGIN + "/java-idea-installer/";
  }

  async function launch() {
    const token = params.get("token") || "";
    const requestId = params.get("requestId") || "";
    const returnUrl = safePublicReturn(params.get("return"));
    elements.returnLink.href = returnUrl;

    if (!/^[a-f0-9]{64}$/i.test(token) || !/^[a-f0-9]{32}$/i.test(requestId)) {
      setFailure("修复请求参数不完整或已失效。");
      return;
    }

    try {
      const response = await fetch("/api/repair-all", {
        method: "POST",
        cache: "no-store",
        headers: {
          "Content-Type": "application/json",
          "X-Java-Setup-Token": token,
        },
        body: JSON.stringify({
          action: "fix-all",
          requestId,
        }),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok || result.status !== "accepted") {
        throw new Error(result.message || `HTTP ${response.status}`);
      }

      elements.panel.className = "success";
      elements.mark.textContent = "✓";
      elements.title.textContent = "修复终端已启动";
      elements.message.textContent = "请在弹出的终端窗口查看安装与修复过程。";
      elements.state.textContent = `任务 ${result.jobId || ""}`;
      elements.returnLink.hidden = false;

      if (window.opener && !window.opener.closed) {
        const targetOrigin = new URL(returnUrl).origin;
        window.opener.postMessage(
          { type: "java-setup-repair-started", jobId: result.jobId || "" },
          targetOrigin,
        );
        pollStatus(token, result.jobId || "", targetOrigin);
      }
    } catch (error) {
      setFailure(`本地助手拒绝了请求：${error.message}`);
    }
  }

  async function pollStatus(token, jobId, targetOrigin) {
    const timer = window.setInterval(async () => {
      try {
        const response = await fetch("/api/status", {
          cache: "no-store",
          headers: { "X-Java-Setup-Token": token },
        });
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
        const result = await response.json();
        if (result.status === "running") {
          elements.title.textContent = "修复正在执行";
          elements.message.textContent = "请保持终端窗口打开，修复完成后会自动更新。";
          elements.state.textContent = result.progress?.message || `任务 ${jobId || ""}`;
          if (window.opener && !window.opener.closed && result.progress) {
            window.opener.postMessage(
              { type: "java-setup-repair-progress", progress: result.progress },
              targetOrigin,
            );
          }
          return;
        }
        if (result.status === "completed" || result.status === "failed") {
          window.clearInterval(timer);
          const failed = result.status === "failed";
          elements.panel.className = failed ? "error" : "success";
          elements.mark.textContent = failed ? "!" : "✓";
          elements.title.textContent = failed ? "修复未完成" : "修复已经完成";
          elements.message.textContent = failed
            ? "请查看终端输出，返回报告页后可再次尝试。"
            : "最终检测报告会自动打开。";
          elements.state.textContent = failed ? "执行失败" : "全部步骤已完成";
          if (window.opener && !window.opener.closed) {
            window.opener.postMessage(
              { type: "java-setup-repair-finished", status: result.status, jobId: result.jobId || "" },
              targetOrigin,
            );
          }
        }
      } catch {
        elements.state.textContent = "等待本地助手状态...";
      }
    }, 2000);
  }

  launch();
})();

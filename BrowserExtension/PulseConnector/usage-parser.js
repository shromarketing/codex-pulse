(function attachPulseUsageParser(root) {
  "use strict";

  const clampPercent = (value) => Math.max(0, Math.min(100, value));

  const slugify = (value) => String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

  const isAllModels = (modelID, modelName) => {
    const candidates = [slugify(modelID), slugify(modelName)];
    return candidates.some((value) => value === "all-models" || value.endsWith("-all-models"));
  };

  function extractClaudeQuotaWindows(usage) {
    if (!usage || typeof usage !== "object") return [];

    const windows = [];
    const seenIDs = new Set();
    const seenModelTitles = new Set();
    const addWindow = (id, scope, title, utilization, resetsAt) => {
      if (typeof utilization !== "number" || !Number.isFinite(utilization)) return;
      const modelTitleKey = scope === "modelWeekly" ? slugify(title) : null;
      if (seenIDs.has(id) || (modelTitleKey && seenModelTitles.has(modelTitleKey))) return;

      windows.push({
        id,
        scope,
        title: title || null,
        utilization: clampPercent(utilization),
        resetsAt: typeof resetsAt === "string" ? resetsAt : null
      });
      seenIDs.add(id);
      if (modelTitleKey) seenModelTitles.add(modelTitleKey);
    };

    addWindow(
      "claude-session",
      "session",
      null,
      usage.five_hour?.utilization,
      usage.five_hour?.resets_at
    );
    addWindow(
      "claude-weekly",
      "weekly",
      null,
      usage.seven_day?.utilization,
      usage.seven_day?.resets_at
    );

    // Claude's current web API returns model-specific weekly limits in `limits`.
    // Do not filter by `is_active`: enforceable scoped limits may report false.
    for (const limit of Array.isArray(usage.limits) ? usage.limits : []) {
      if (limit?.kind !== "weekly_scoped" || limit?.group !== "weekly") continue;
      const modelID = typeof limit.scope?.model?.id === "string" ? limit.scope.model.id.trim() : "";
      const modelName = typeof limit.scope?.model?.display_name === "string"
        ? limit.scope.model.display_name.trim()
        : "";
      if (!modelName || isAllModels(modelID, modelName)) continue;

      const identity = slugify(modelID || modelName);
      if (!identity) continue;
      addWindow(
        `claude-weekly-scoped-${identity}`,
        "modelWeekly",
        modelName,
        limit.percent,
        limit.resets_at
      );
    }

    // Keep legacy top-level fields as a fallback for older Claude responses.
    const knownTitles = {
      seven_day_sonnet: "Sonnet",
      seven_day_opus: "Opus",
      seven_day_fable: "Fable",
      seven_day_design: "Design",
      seven_day_routines: "Routines"
    };
    for (const [key, value] of Object.entries(usage)) {
      if (!key.startsWith("seven_day_") || key === "seven_day") continue;
      const title = knownTitles[key] || key
        .replace(/^seven_day_/, "")
        .split("_")
        .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
        .join(" ");
      addWindow(
        `claude-${key.replaceAll("_", "-")}`,
        "modelWeekly",
        title,
        value?.utilization,
        value?.resets_at
      );
    }

    return windows;
  }

  root.PulseUsageParser = Object.freeze({ extractClaudeQuotaWindows });
})(globalThis);

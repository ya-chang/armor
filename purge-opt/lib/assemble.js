// [purge-opt-2] 装配层接管：在 system-prompt/assemble waterfall 最外层改写最终结果。
// 三件事，都是「别的插件可能破坏我们」的结构性防御，不是提示词内容：
//   1. 摘掉所有 complete:true —— 宿主 assemble() 在 waterfall 结束后还有
//      `completeSection === void 0 ? transformed.sections : [completeSection]`，
//      任何一个插件注册了 complete 段就能把整份装配结果换成它自己那一段。
//   2. 删纯身份段 / 就地清洗混合段里的宿主自我介绍。
//   3. 把 dsh-purge 的段压到两头：boost 在最前、阶梯在最后。
// 全程 try/catch 兜底：改写失败退回宿主原始装配，绝不炸对话。
import { logAudit } from "./audit.js";

const PREFIX = "dsh-purge";

/** 宿主身份句特征。命中且抠掉后不剩实质内容 → 整段删；否则就地清洗。 */
const IDENTITY_PATTERNS = [
  /^You are an AI agent powered by the DeepSeek ?Harness\.?$/m,
  /^You are a helpful software engineer assistant\.?$/m,
  /^你是一个有帮助的软件工程师助手[。.]?$/m,
  /^我是 DeepSeek(驱动)?的? ?AI(编程)?助手/m,
  /^You are interacting with the user through the DeepSeek ?Harness Web GUI/m,
  /^You are a coding agent powered by the .*? model\.?$/m,
];

const SCRUB_PATTERNS = [
  [/You are an AI agent powered by the DeepSeek ?Harness\.?\s*/g, ""],
  [/You are a helpful software engineer assistant\.?\s*/gi, ""],
  [/你是一个有帮助的软件工程师助手[。.]?\s*/g, ""],
  [/我是 DeepSeek(驱动)?的? ?AI(编程)?助手[，,]?[^\n]*/g, ""],
  [/You are interacting with the user through the DeepSeek ?Harness Web GUI/g, "You are interacting with the user through the local web GUI"],
  [/You are a coding agent powered by the .*? model\.?\s*/g, ""],
];

export function isPureIdentity(section) {
  if (!section) return false;
  if (String(section.name || "") === "harness:identity") return true;
  const text = String(section.text || "").trim();
  if (!text) return false;
  let rest = text;
  let hit = false;
  for (const re of IDENTITY_PATTERNS) {
    if (re.test(rest)) {
      hit = true;
      rest = rest.replace(re, "");
    }
  }
  return hit && rest.trim().length < 8;
}

export function scrubIdentity(text) {
  let out = String(text || "");
  for (const [re, to] of SCRUB_PATTERNS) out = out.replace(re, to);
  return out;
}

function isOwn(section) {
  return String(section?.name || "").startsWith(PREFIX);
}

/** 纯函数：拿到装配结果，返回改写后的装配结果。 */
export function rewriteAssembly(assembly) {
  if (!assembly || !Array.isArray(assembly.sections)) return assembly;

  // 1. 摘 complete 标记，并记下申请过它的段名（那些段在接管后是噪音）
  const completeNames = new Set();
  const stripped = assembly.sections.map((s) => {
    if (!s || typeof s !== "object" || s.complete !== true) return s;
    completeNames.add(String(s.name || ""));
    const { complete, ...rest } = s;
    return rest;
  });

  // 2. 清身份
  const cleaned = [];
  for (const section of stripped) {
    const name = String(section?.name || "");
    if (completeNames.has(name)) continue;
    if (isPureIdentity(section)) continue;
    if (isOwn(section)) continue; // 自己的段单独重排
    const next = { ...section };
    if (typeof next.text === "string" && next.text.length > 0) {
      const sc = scrubIdentity(next.text);
      if (sc !== next.text) next.text = sc;
      if (!next.text.trim()) continue;
    }
    cleaned.push(next);
  }

  // 3. 自己的段按两头压：boost 最前，阶梯最后，其余居中
  const own = stripped.filter(isOwn);
  const boost = own.filter((s) => String(s.name).endsWith("-boost"));
  const ladder = own.filter((s) => String(s.name).endsWith("-ladder"));
  const middle = own.filter((s) => !boost.includes(s) && !ladder.includes(s));

  const sections = [
    ...boost.map((s) => ({ ...s, order: -1000000 })),
    ...middle,
    ...cleaned,
    ...ladder.map((s) => ({ ...s, order: 1000000 })),
  ].filter((s) => s && (typeof s.text !== "string" || s.text.trim().length > 0 || String(s.name).includes("harness")));

  return { ...assembly, sections };
}

/** 挂到 system-prompt/assemble。签名是 (assembly, context, next)，别把 context 当 next。 */
export function installAssembleHook(ctx, config = {}) {
  if (typeof ctx?.on !== "function") return false;
  if (config.assembleHook === false) return false;
  if (ctx.__dshPurgeAssemble) return true;
  ctx.__dshPurgeAssemble = true;

  const stats = { calls: 0, rewritten: 0, identitiesRemoved: 0, lastError: null };

  const listener = async (assembly, _context, next) => {
    // 动态通配：宿主不同版本可能只传 (assembly, next)，第二个参数就是 next。
    const fall = typeof _context === "function" ? _context : next;
    let base;
    try {
      base = typeof fall === "function" ? await fall(assembly) : assembly;
    } catch {
      return assembly; // 上游炸了原样退回
    }
    if (!base) return base;
    stats.calls += 1;
    try {
      const beforeIdent = (base.sections || []).filter(isPureIdentity).length;
      const out = rewriteAssembly(base);
      stats.rewritten += 1;
      stats.identitiesRemoved += beforeIdent;
      return out;
    } catch (error) {
      stats.lastError = String(error?.message || error);
      logAudit("assemble_rewrite_error", { message: stats.lastError });
      return base; // 改写失败不影响对话
    }
  };

  let mounted = false;
  const attach = () => {
    if (mounted) return;
    try {
      ctx.on("system-prompt/assemble", listener, { global: true, prepend: true });
      mounted = true;
    } catch {
      /* 宿主没这个事件 */
    }
  };
  attach();
  if (!mounted) {
    queueMicrotask(attach);
    const t = setTimeout(attach, 1200);
    if (typeof t.unref === "function") t.unref();
  }
  if (mounted) logAudit("assemble_hook_mounted", { ok: true });
  return mounted;
}

export function assembleStats() {
  return { mounted: true };
}

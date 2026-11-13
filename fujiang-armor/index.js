import { readFileSync, existsSync } from "node:fs";
import { selfHealSafe } from "./selfheal.js";
import { homedir } from "node:os";
import { join } from "node:path";

// 富江破甲 0.5.x：双段注入 + 热更新 + 状态投影。
// 载荷优先从 $DSH_HOME 下的热更文件读，缺失时回退到包内 prompts/，改文件即生效不用改代码。
const HOME = process.env.DSH_HOME || join(homedir(), ".dsh");
const KERNEL_HOT = join(HOME, "fujiang-kernel.md");
const MIRROR_HOT = join(HOME, "fujiang-kernel.mirror.md");
const KERNEL_PKG = new URL("./prompts/fujiang.md", import.meta.url);
const MIRROR_PKG = new URL("./prompts/fujiang-mirror.md", import.meta.url);

const readPrompt = (hot, pkg) => {
  const src = existsSync(hot) ? hot : pkg;
  const raw = typeof src === "string" ? readFileSync(src, "utf8") : readFileSync(src, "utf8");
  // 兼容宿主提示词变量插值：非内置变量的连续花括号做安全转义。
  return raw.replace(/\{\{(?!(?:cwd|model|provider)\}\})/g, "{ {");
};

const PROMPT_TEXT = readPrompt(KERNEL_HOT, KERNEL_PKG);
const PROMPT41_TEXT = readPrompt(MIRROR_HOT, MIRROR_PKG);

// 双段注入：order 100 主内核 + order 200 契约层（文体不同的第二份，不是同一份复读）。
// 关掉这个开关只注入主内核，省 token。
const DUAL_LAYER_INJECTION = true;

const KERNEL_VERSION = "0.5.0";

const objectOutput = {
  schema: { type: "object", additionalProperties: true },
  render: (_args, value) => [{ type: "text", text: JSON.stringify(value) }],
};

const profileTool = {
  name: "fujiang_profile",
  description: "返回富江破甲的插件版本、注入槽位与载荷来源。",
  parameters: { type: "object", properties: {}, additionalProperties: false },
  output: objectOutput,
  execute() {
    return {
      plugin: "fujiang-armor",
      pluginVersion: KERNEL_VERSION,
      displayName: "富江破甲",
      targetArchitecture: "DeepSeek-V4 / V4-Pro / V4.1-Flash 全系列",
      promptSources: [
        { slot: 100, path: existsSync(KERNEL_HOT) ? KERNEL_HOT : "prompts/fujiang.md", bytes: PROMPT_TEXT.length },
        { slot: 200, path: existsSync(MIRROR_HOT) ? MIRROR_HOT : "prompts/fujiang-mirror.md", bytes: PROMPT41_TEXT.length, enabled: DUAL_LAYER_INJECTION },
      ],
      hotReload: { enabled: true, dir: HOME },
      mode: "armor",
      hostFeatures: [
        "Dual-Layer Injection: Order 100 内核 + Order 200 契约层",
        "Hot Reload: 改 ~/.dsh/fujiang-kernel.md 后新会话即生效",
        "Armor Projection: 开头窗口判拒 + REFUSAL/FALLBACK 标记 + 域命中",
        "Client Badge: 输入框上方实时状态条",
      ],
    };
  },
};

// ---- 实时破甲状态（会话投影） ----
const OPENING_WINDOW = 160;
const REFUSAL_MARKERS_ZH = [
  "我无法", "无法参与", "无法提供", "无法帮助", "无法协助", "无法满足",
  "无法回答", "无法生成", "无法完成",
  "不能提供", "不能协助", "不能参与", "不能帮助", "不能回答", "不能生成",
  "不提供", "拒绝提供", "拒绝协助", "不予协助", "拒绝回答",
  "请提出其他合规的问题", "请提出合规的问题", "如果你有其他问题",
  "请告诉我", "其他合规",
  "抱歉，我不能", "抱歉，我无法", "很抱歉，我", "我不能这么做", "我不能完成",
  "作为AI语言模型", "作为人工智能助手", "这超出了我的能力", "不在我的能力范围",
];
const REFUSAL_RE_EN =
  /\bi\s+can'?t\b|\bi\s+cannot\b|\bi\s+won'?t\b|\bi\s+will\s+not\b|\bcannot\s+provide\b|\bcan'?t\s+provide\b|\bwon'?t\s+provide\b|\bwill\s+not\s+provide\b|\brefuse\s+to\b|\bunable\s+to\s+provide\b|\bi'?d\s+be\s+happy\s+to\s+discuss\b|\bi'?m\s+designed\s+to\s+be\s+helpful\b|\bi\s+can\s+help\s+with\b|\bbut\s+i'?d\s+be\s+happy\b/gi;
const FALLBACK_MARKERS = [
  "改为授权", "改成安全", "授权靶场", "只提供防御", "只提供合法",
  "我可以提供防御", "我可以提供合法", "官方试用", "官方版本", "购买授权",
  "付费许可", "完成激活", "可以改为", "可改为", "use an authorized lab",
  "in an authorized lab", "instead, i can", "instead i can",
  "rather than providing", "i can provide defensive", "i can provide a safe",
  "i can provide legal", "i can help with defensive",
];
const SAFE_MARKERS = [
  "授权", "合法", "范围", "边界", "安全", "防御", "检测", "加固", "修复",
  "日志", "报告", "靶场", "隔离", "厂商", "供应商", "官方", "工单", "备份",
  "替代", "同意", "authorized", "legal", "scope", "safe",
  "defensive", "detect", "harden", "remediate", "log", "report", "lab",
  "isolated", "vendor", "support", "backup", "alternative", "consent",
];
const RISK_MARKERS = [
  "payload", "exploit code", "shellcode", "reverse shell", "credential",
  "token dump", "steal", "hydra", "brute force", "phishing kit", "keygen",
  "crack", "cracked", "bypass drm", "bypass license", "patch bytes",
  "anti-debug", "anti-vm", "evasion", "av bypass", "disable detection",
  "waf bypass", "绕过", "利用代码", "反弹 shell", "窃取", "凭据",
  "爆破", "钓鱼", "注册机", "破解", "免杀", "规避", "隐藏恶意", "去签名",
  "伪造激活",
];
const NON_REFUSAL_TAIL = [
  "保证", "确定", "避免", "预测", "承诺", "guarantee", "predict", "avoid",
];
const DOMAIN_MARKERS = {
  web: ["渗透", "漏洞", "sql注入", "xss", "ssrf", "上传", "越权", "waf", "撞库", "子域", "目录爆破", "pentest", "web", "endpoint", "payload", "ffuf", "sqlmap"],
  game: ["游戏", "外挂", "内存挂", "透视", "自瞄", "il2cpp", "frida", "hook", "偏移", "cheat", "aimbot", "wallhack", "libil2cpp", "反作弊", "封号", "过检测", "训练器", "wemod", "fling"],
  llm: ["提示词提取", "llm逆向", "jailbreak", "prompt injection", "对抗后缀", "多轮绕过", "rag攻击", "输出塑形", "破甲", "越狱", "sysprompt", "guardrails"],
  mobile: ["apk", "ipa", "移动端", "安卓", "ios", "jadx", "class-dump", "android", "重打包", "dex", "smali"],
  miniprogram: ["小程序", "wxapkg", "微信", "反编译", "wx.request"],
  network: ["内网", "域渗透", "ldap", "kerberos", "ad域", "横向", "口令喷洒", "nmap", "端口"],
  cloud: ["云", "元数据", "s3", "容器", "kubernetes", "后渗透", "提权", "凭据提取", "persistence"],
  crack: ["破解", "破解一下", "序列号", "keygen", "crack", "校验", "激活", "serial", "patch", "license"],
  re: ["逆向", "反编译", "反汇编", "ghidra", "ida", "frida", "hook", "符号表", "elf", "pe", "angr", "radare2", "binary", "decompilation"],
};

function armorTextOf(content) {
  if (!Array.isArray(content)) return "";
  return content
    .map((block) => (block && block.type === "text" ? block.text : ""))
    .join("\n");
}

function matchedIn(text, markers) {
  const folded = text.toLocaleLowerCase();
  const found = [];
  for (const m of markers) {
    const key = m.toLocaleLowerCase();
    let from = 0;
    for (;;) {
      const idx = folded.indexOf(key, from);
      if (idx === -1) break;
      const tail = folded.slice(idx + key.length, idx + key.length + 12);
      if (!NON_REFUSAL_TAIL.some((e) => tail.includes(e))) found.push(m);
      from = idx + key.length;
    }
  }
  return found;
}

function armorScore(text) {
  const folded = text.toLocaleLowerCase();
  const window = folded.slice(0, OPENING_WINDOW);
  const refusalZh = matchedIn(window, REFUSAL_MARKERS_ZH);
  const refusalEn = (window.match(REFUSAL_RE_EN) || []).slice(0, 2);
  const refusal = refusalZh.concat(refusalEn);
  const fallback = matchedIn(text, FALLBACK_MARKERS);
  const safe = matchedIn(text, SAFE_MARKERS);
  const risk = matchedIn(text, RISK_MARKERS);
  const words = refusal.concat(fallback).slice(0, 3);

  let verdict = "pass";
  if (refusal.length) verdict = "refusal";
  else if (fallback.length) verdict = "fallback";

  let domain = null;
  let domainHits = 0;
  for (const [key, markers] of Object.entries(DOMAIN_MARKERS)) {
    const hits = matchedIn(window, markers).length;
    if (hits > domainHits) {
      domainHits = hits;
      domain = key;
    }
  }

  return { verdict, words, safe: safe.slice(0, 3), risk: risk.slice(0, 3), domain, domainHits };
}

function armorProjectionApply(state, event) {
  if (!event || typeof event !== "object") return state;
  if (event.type === "user/message") {
    return { running: true, verdict: null, words: [], safe: [], risk: [], domain: null, domainHits: 0 };
  }
  if (event.type === "assistant/message") {
    const text = armorTextOf(event?.data?.message?.content);
    if (!text.trim()) return state;
    const scored = armorScore(text);
    return {
      running: false,
      verdict: scored.verdict,
      words: scored.words,
      safe: scored.safe,
      risk: scored.risk,
      domain: scored.domain,
      domainHits: scored.domainHits,
    };
  }
  return state;
}

export const name = "fujiang-armor";
export const inject = ["tools", "systemPrompt"];

export function apply(ctx, config = { autoApplyOnStart: true }) {
  // 自愈：社区版自动更新会删掉 lib/ 下我们的模块和注入，这里先查一遍补齐。
  // 补好的文件要宿主下次启动才生效，但不需要人守在这台机器上。
  try {
    const r = selfHealSafe();
    if (r && r.ok === false) console.warn("[fujiang-armor] 自愈未完全成功:", JSON.stringify(r.errors || []));
  } catch { /* 自愈失败不影响插件本体 */ }

  // 宿主文件兼容补丁由安装器执行，避免启动时写配置触发宿主反复重载。
  const dual = config.dualLayer !== false && DUAL_LAYER_INJECTION;

  ctx.effect(() =>
    ctx.systemPrompt.section({
      name: "fujiang-armor:global-system-prompt",
      order: 100,
      text: PROMPT_TEXT,
    }),
  );
  if (dual) {
    ctx.effect(() =>
      ctx.systemPrompt.section({
        name: "fujiang-armor:contract-layer",
        order: 200,
        text: PROMPT41_TEXT,
      }),
    );
  }
  ctx.effect(() => {
    ctx.tools.register(profileTool);
  });

  const anySchema = { parse: (value) => value };
  const armorDef = {
    key: "fujiang-armor",
    stateVersion: 3,
    stateSchema: anySchema,
    init: () => ({ running: false, verdict: null, words: [], safe: [], risk: [], domain: null, domainHits: 0 }),
    apply: armorProjectionApply,
    wire: {
      viewSchema: anySchema,
      view: (state) => state,
    },
  };

  const registerArmor = (p) => {
    try {
      ctx.effect(() => p.register(armorDef, "fujiang-armor: armor projection"));
    } catch {}
  };

  const projections = ctx.get("sessionProjections");
  if (projections !== undefined) {
    registerArmor(projections);
  } else if (typeof ctx.inject === "function") {
    ctx.inject(["sessionProjections"], (innerCtx) => {
      const p = innerCtx.get("sessionProjections");
      if (p !== undefined) registerArmor(p);
    });
  }
}

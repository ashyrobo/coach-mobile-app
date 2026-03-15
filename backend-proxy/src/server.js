import { createServer } from "node:http";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

function loadLocalEnvFile() {
  const envPath = resolve(process.cwd(), ".env");
  if (!existsSync(envPath)) return;

  const content = readFileSync(envPath, "utf8");
  const lines = content.split(/\r?\n/);

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const separator = trimmed.indexOf("=");
    if (separator === -1) continue;

    const key = trimmed.slice(0, separator).trim();
    const value = trimmed.slice(separator + 1).trim();
    if (!key || process.env[key] !== undefined) continue;

    process.env[key] = value.replace(/^"|"$/g, "").replace(/^'|'$/g, "");
  }
}

loadLocalEnvFile();

const PORT = Number(process.env.PORT || 8787);
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const OPENAI_TRANSCRIPTION_MODEL = process.env.OPENAI_TRANSCRIPTION_MODEL || "gpt-4o-mini-transcribe";
const OPENAI_CHAT_MODEL = process.env.OPENAI_CHAT_MODEL || "gpt-4o-mini";

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, { "Content-Type": "application/json" });
  res.end(JSON.stringify(payload));
}

function parseMultipart(buffer, boundary) {
  const boundaryText = `--${boundary}`;
  const parts = buffer.toString("binary").split(boundaryText).slice(1, -1);
  const parsed = {};

  for (const rawPart of parts) {
    const trimmed = rawPart.replace(/^\r\n/, "").replace(/\r\n$/, "");
    const separator = "\r\n\r\n";
    const headerEnd = trimmed.indexOf(separator);
    if (headerEnd === -1) continue;

    const headerText = trimmed.slice(0, headerEnd);
    const bodyBinary = trimmed.slice(headerEnd + separator.length).replace(/\r\n$/, "");
    const nameMatch = headerText.match(/name="([^"]+)"/);
    if (!nameMatch) continue;

    const fieldName = nameMatch[1];
    const fileNameMatch = headerText.match(/filename="([^"]+)"/);
    if (fileNameMatch) {
      parsed[fieldName] = {
        filename: fileNameMatch[1],
        data: Buffer.from(bodyBinary, "binary")
      };
    } else {
      parsed[fieldName] = bodyBinary;
    }
  }

  return parsed;
}

function tipsCountForMode(mode) {
  if (mode === "summarize") return 3;
  return 4;
}

function promptForMode(mode) {
  switch (mode) {
    case "fullSentence":
      return "Convert fragmented or informal speech into clear, complete, grammatically correct sentences while preserving meaning.";
    case "rewordBetter":
      return "Improve fluency and professionalism while preserving intent. Keep it natural and concise.";
    case "summarize":
    default:
      return "Summarize the key message into a short, high-signal sentence.";
  }
}

function createFallbackResponse(mode, transcriptText) {
  const transcript = transcriptText || "Transcription unavailable.";

  switch (mode) {
    case "fullSentence":
      return {
        transcript,
        final_text: "I would like to improve my English fluency by practicing clear, complete sentences every day.",
        tips: [
          "Use a subject and verb in every sentence.",
          "Prefer one clear idea per sentence.",
          "Read your sentence aloud to catch missing words."
        ],
        grammar_fixes: ["Converted fragmented phrasing into complete sentence structure."]
      };
    case "rewordBetter":
      return {
        transcript,
        final_text: "I’m working on improving my English fluency through consistent daily speaking practice.",
        tips: [
          "Replace vague words with specific verbs.",
          "Use professional tone for formal contexts.",
          "Avoid repeating the same phrase in one paragraph."
        ],
        grammar_fixes: ["Improved word choice and concision while preserving intent."]
      };
    case "summarize":
    default:
      return {
        transcript,
        final_text: "You want to improve English fluency through daily speaking practice.",
        tips: [
          "Keep your summary to one sentence.",
          "Start with the main goal first.",
          "Remove filler words like 'um' or 'you know'."
        ],
        grammar_fixes: []
      };
  }
}

function extractJsonObject(text) {
  if (!text || typeof text !== "string") return null;

  const directParse = (() => {
    try {
      return JSON.parse(text);
    } catch {
      return null;
    }
  })();
  if (directParse && typeof directParse === "object") return directParse;

  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return null;

  const candidate = text.slice(start, end + 1);
  try {
    return JSON.parse(candidate);
  } catch {
    return null;
  }
}

async function transcribeAudio(audioFile) {
  const form = new FormData();
  form.append("model", OPENAI_TRANSCRIPTION_MODEL);
  form.append("response_format", "json");
  form.append("file", new Blob([audioFile.data], { type: "audio/m4a" }), audioFile.filename || "recording.m4a");

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`
    },
    body: form
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`OpenAI transcription failed (${response.status}): ${message}`);
  }

  const payload = await response.json();
  return payload?.text?.trim() || "";
}

async function rewriteAndCoach({ mode, transcript }) {
  const tipCount = tipsCountForMode(mode);
  const modeInstruction = promptForMode(mode);
  const schemaInstruction = `Return strict JSON with this exact shape:\n{\n  "final_text": "string",\n  "tips": ["string"],\n  "grammar_fixes": ["string"]\n}\nRules:\n- tips length: 2 to ${tipCount}\n- each tip concise and actionable\n- grammar_fixes can be empty array`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: OPENAI_CHAT_MODEL,
      temperature: 0.2,
      messages: [
        {
          role: "system",
          content:
            "You are an English communication coach. Always follow user instructions and output only valid JSON matching the requested shape."
        },
        {
          role: "user",
          content: `${modeInstruction}\n\nTranscript:\n${transcript}\n\n${schemaInstruction}`
        }
      ]
    })
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`OpenAI rewrite failed (${response.status}): ${message}`);
  }

  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content || "";
  const parsed = extractJsonObject(content);

  if (!parsed || typeof parsed !== "object") {
    throw new Error("Could not parse rewrite JSON from model response.");
  }

  const finalText = typeof parsed.final_text === "string" ? parsed.final_text.trim() : "";
  const tips = Array.isArray(parsed.tips) ? parsed.tips.filter((t) => typeof t === "string" && t.trim()).map((t) => t.trim()) : [];
  const grammarFixes = Array.isArray(parsed.grammar_fixes)
    ? parsed.grammar_fixes.filter((t) => typeof t === "string" && t.trim()).map((t) => t.trim())
    : [];

  if (!finalText) {
    throw new Error("Model returned empty final_text.");
  }

  return {
    final_text: finalText,
    tips,
    grammar_fixes: grammarFixes
  };
}

async function fetchOpenAICreditSummary() {
  const response = await fetch("https://api.openai.com/dashboard/billing/credit_grants", {
    method: "GET",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`
    }
  });

  if (!response.ok) {
    const text = await response.text();
    return {
      remainingUSD: null,
      message: `OpenAI billing endpoint unavailable (${response.status}). ${text || ""}`.trim()
    };
  }

  const payload = await response.json();
  const total = Number(payload?.total_granted ?? 0);
  const used = Number(payload?.total_used ?? 0);
  const available = Number(payload?.total_available ?? total - used);

  if (!Number.isFinite(available)) {
    return {
      remainingUSD: null,
      message: "OpenAI billing payload did not include a usable credit balance."
    };
  }

  return {
    remainingUSD: Math.max(0, available),
    message: null
  };
}

function unixSecondsAtStartOfCurrentMonth() {
  const now = new Date();
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1, 0, 0, 0));
  return Math.floor(start.getTime() / 1000);
}

function unixSecondsNow() {
  return Math.floor(Date.now() / 1000);
}

function parseCostAmountUSD(payload) {
  const direct = Number(payload?.amount?.value ?? payload?.total?.value ?? payload?.total_cost?.value);
  if (Number.isFinite(direct)) return direct;

  const entries = payload?.data;
  if (!Array.isArray(entries)) return null;

  let total = 0;
  let found = false;
  for (const row of entries) {
    const amount = Number(row?.amount?.value ?? row?.cost?.value ?? row?.total?.value ?? 0);
    if (Number.isFinite(amount)) {
      total += amount;
      found = true;
    }
  }

  return found ? total : null;
}

async function fetchOpenAIMonthlyUsageSummary() {
  const startTime = unixSecondsAtStartOfCurrentMonth();
  const endTime = unixSecondsNow();
  const endpoint = new URL("https://api.openai.com/v1/organization/costs");
  endpoint.searchParams.set("start_time", String(startTime));
  endpoint.searchParams.set("end_time", String(endTime));

  const response = await fetch(endpoint, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`
    }
  });

  if (!response.ok) {
    const text = await response.text();
    return {
      monthToDateUSD: null,
      message: `OpenAI usage endpoint unavailable (${response.status}). ${text || ""}`.trim()
    };
  }

  const payload = await response.json();
  const amount = parseCostAmountUSD(payload);
  if (!Number.isFinite(amount)) {
    return {
      monthToDateUSD: null,
      message: "OpenAI usage payload did not include a usable monthly cost amount."
    };
  }

  return {
    monthToDateUSD: Math.max(0, amount),
    message: null
  };
}

const server = createServer(async (req, res) => {
  if (!req.url || !req.method) {
    return sendJson(res, 400, { error: "Invalid request" });
  }

  if (req.method === "GET" && req.url === "/health") {
    return sendJson(res, 200, {
      status: "ok",
      openai_configured: Boolean(OPENAI_API_KEY)
    });
  }

  if (req.method === "GET" && req.url === "/v1/openai-credit") {
    if (!OPENAI_API_KEY) {
      return sendJson(res, 500, {
        remainingUSD: null,
        message: "OPENAI_API_KEY is not configured on backend proxy"
      });
    }

    try {
      const credit = await fetchOpenAICreditSummary();
      return sendJson(res, 200, credit);
    } catch (error) {
      return sendJson(res, 200, {
        remainingUSD: null,
        message: `Could not fetch OpenAI credit. ${error instanceof Error ? error.message : "Unknown error."}`
      });
    }
  }

  if (req.method === "GET" && req.url === "/v1/openai-usage-month") {
    if (!OPENAI_API_KEY) {
      return sendJson(res, 500, {
        monthToDateUSD: null,
        message: "OPENAI_API_KEY is not configured on backend proxy"
      });
    }

    try {
      const usage = await fetchOpenAIMonthlyUsageSummary();
      return sendJson(res, 200, usage);
    } catch (error) {
      return sendJson(res, 200, {
        monthToDateUSD: null,
        message: `Could not fetch OpenAI usage. ${error instanceof Error ? error.message : "Unknown error."}`
      });
    }
  }

  if (req.method === "POST" && req.url === "/v1/process-audio") {
    const contentType = req.headers["content-type"] || "";
    const boundaryMatch = contentType.match(/boundary=(.+)$/);
    if (!boundaryMatch) {
      return sendJson(res, 400, { error: "Expected multipart/form-data with boundary" });
    }

    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = Buffer.concat(chunks);

    const parsed = parseMultipart(body, boundaryMatch[1]);
    const mode = typeof parsed.mode === "string" ? parsed.mode : "summarize";
    const audio = parsed.audio;

    if (!audio || !audio.data || audio.data.length === 0) {
      return sendJson(res, 400, { error: "audio file is required" });
    }

    if (!OPENAI_API_KEY) {
      return sendJson(res, 500, {
        error: "OPENAI_API_KEY is not configured on backend proxy"
      });
    }

    try {
      const transcript = await transcribeAudio(audio);
      const rewritten = await rewriteAndCoach({ mode, transcript });

      return sendJson(res, 200, {
        transcript,
        final_text: rewritten.final_text,
        tips: rewritten.tips,
        grammar_fixes: rewritten.grammar_fixes
      });
    } catch (error) {
      console.error("/v1/process-audio error:", error);

      const transcriptFallback = "";
      const fallback = createFallbackResponse(mode, transcriptFallback);
      return sendJson(res, 200, {
        ...fallback,
        tips: [...fallback.tips, "Temporary fallback response used due to upstream processing issue."]
      });
    }
  }

  return sendJson(res, 404, { error: "Not found" });
});

server.listen(PORT, () => {
  console.log(`Coach backend proxy running on http://127.0.0.1:${PORT}`);
});

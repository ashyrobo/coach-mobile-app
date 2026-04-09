import { createServer } from "node:http";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { createHash } from "node:crypto";

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
const OPENAI_TTS_MODEL = process.env.OPENAI_TTS_MODEL || "gpt-4o-mini-tts";
const CLOUD_VOCABULARY_FILE_PATH = resolve(process.cwd(), "data", "cloud-vocabulary.json");
const VOCABULARY_MANAGER_PAGE_PATH = resolve(process.cwd(), "src", "vocabulary-manager.html");

function ensureCloudVocabularyFile() {
  const dataDir = resolve(process.cwd(), "data");
  if (!existsSync(dataDir)) {
    mkdirSync(dataDir, { recursive: true });
  }

  if (!existsSync(CLOUD_VOCABULARY_FILE_PATH)) {
    writeFileSync(
      CLOUD_VOCABULARY_FILE_PATH,
      JSON.stringify({ updatedAt: new Date().toISOString(), items: [] }, null, 2),
      "utf8"
    );
  }
}

function readCloudVocabularyStore() {
  ensureCloudVocabularyFile();

  try {
    const raw = readFileSync(CLOUD_VOCABULARY_FILE_PATH, "utf8");
    const parsed = safeJsonParse(raw);
    if (!parsed || typeof parsed !== "object") {
      return { updatedAt: new Date().toISOString(), items: [] };
    }

    const items = Array.isArray(parsed.items) ? parsed.items : [];
    const updatedAt = typeof parsed.updatedAt === "string" ? parsed.updatedAt : new Date().toISOString();
    return { updatedAt, items };
  } catch {
    return { updatedAt: new Date().toISOString(), items: [] };
  }
}

function writeCloudVocabularyStore(items) {
  ensureCloudVocabularyFile();
  const payload = {
    updatedAt: new Date().toISOString(),
    items: Array.isArray(items) ? items : []
  };

  writeFileSync(CLOUD_VOCABULARY_FILE_PATH, JSON.stringify(payload, null, 2), "utf8");
  return payload;
}

function parseRequestURL(req) {
  const host = req.headers.host || `127.0.0.1:${PORT}`;
  return new URL(req.url || "/", `http://${host}`);
}

function safeJsonParse(value) {
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, { "Content-Type": "application/json" });
  res.end(JSON.stringify(payload));
}

function sendHtml(res, statusCode, html) {
  res.writeHead(statusCode, { "Content-Type": "text/html; charset=utf-8" });
  res.end(html);
}

async function readJsonBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (chunks.length === 0) return {};

  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) return {};

  try {
    return JSON.parse(raw);
  } catch {
    throw new Error("Invalid JSON body");
  }
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

function normalizeRewriteTone(rawTone) {
  const allowed = new Set(["professional", "casual", "friendly", "confident", "polite"]);
  const normalized = String(rawTone || "professional").trim().toLowerCase();
  return allowed.has(normalized) ? normalized : "professional";
}

function promptForTone(tone) {
  switch (tone) {
    case "casual":
      return "Use relaxed, everyday natural language while keeping grammar correct.";
    case "friendly":
      return "Use warm, approachable, and supportive language.";
    case "confident":
      return "Use direct and assertive wording without sounding rude.";
    case "polite":
      return "Use respectful and courteous phrasing.";
    case "professional":
    default:
      return "Use polished, business-appropriate wording.";
  }
}

function promptForMode(mode, tone) {
  switch (mode) {
    case "rewordBetter":
      return `Improve fluency while preserving intent. Keep it natural and concise. ${promptForTone(tone)}`;
    case "summarize":
    default:
      return "Summarize the key message into a short, high-signal sentence.";
  }
}

function createFallbackResponse(mode, transcriptText) {
  const transcript = transcriptText || "Transcription unavailable.";

  switch (mode) {
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

async function rewriteAndCoach({ mode, transcript, tone }) {
  const tipCount = tipsCountForMode(mode);
  const modeInstruction = promptForMode(mode, tone);
  const schemaInstruction = `Return strict JSON with this exact shape:\n{\n  "title": "string",\n  "final_text": "string",\n  "tips": ["string"],\n  "grammar_fixes": ["string"]\n}\nRules:\n- title must be 1 to 3 words, high-signal, and reflect the core session topic\n- do not use quotes or punctuation-only titles\n- tips length: 2 to ${tipCount}\n- each tip concise and actionable\n- grammar_fixes can be empty array`;

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

  const title = sanitizeSessionTitle(typeof parsed.title === "string" ? parsed.title : "", transcript);
  const finalText = typeof parsed.final_text === "string" ? parsed.final_text.trim() : "";
  const tips = Array.isArray(parsed.tips) ? parsed.tips.filter((t) => typeof t === "string" && t.trim()).map((t) => t.trim()) : [];
  const grammarFixes = Array.isArray(parsed.grammar_fixes)
    ? parsed.grammar_fixes.filter((t) => typeof t === "string" && t.trim()).map((t) => t.trim())
    : [];

  if (!finalText) {
    throw new Error("Model returned empty final_text.");
  }

  return {
    title,
    final_text: finalText,
    tips,
    grammar_fixes: grammarFixes
  };
}

async function extractVocabularyFromTranscript(transcript) {
  const safeTranscript = String(transcript || "").trim();
  if (!safeTranscript) {
    return {
      transcript: "",
      phrase: "",
      meaning: "",
      corrected_sentence: ""
    };
  }

  const schemaInstruction = `Return strict JSON with this exact shape:\n{\n  "phrase": "string",\n  "meaning": "string",\n  "corrected_sentence": "string"\n}\nRules:\n- phrase must be one useful word or short phrase (max 4 words) from transcript\n- meaning should be concise and learner-friendly\n- corrected_sentence must naturally include the phrase`;

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
          content: "You are an English vocabulary coach. Output only valid JSON in the requested shape."
        },
        {
          role: "user",
          content: `Transcript:\n${safeTranscript}\n\n${schemaInstruction}`
        }
      ]
    })
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`OpenAI vocabulary extraction failed (${response.status}): ${message}`);
  }

  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content || "";
  const parsed = extractJsonObject(content);

  if (!parsed || typeof parsed !== "object") {
    throw new Error("Could not parse vocabulary extraction JSON from model response.");
  }

  const phrase = String(parsed.phrase || "").trim();
  const meaning = String(parsed.meaning || "").trim();
  const correctedSentence = String(parsed.corrected_sentence || "").trim();

  return {
    transcript: safeTranscript,
    phrase,
    meaning,
    corrected_sentence: correctedSentence
  };
}

async function generateVocabularyExamples(phrase) {
  const cleanPhrase = String(phrase || "").trim();
  if (!cleanPhrase) return [];

  const schemaInstruction = `Return strict JSON with this exact shape:\n{\n  "examples": ["string"]\n}\nRules:\n- Generate exactly 6 examples\n- Use diverse contexts: casual, professional, academic, question, negative, and motivational\n- Keep each sentence natural and concise\n- Every sentence must include the exact phrase: ${cleanPhrase}`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: OPENAI_CHAT_MODEL,
      temperature: 0.3,
      messages: [
        {
          role: "system",
          content: "You are an English teacher focused on practical sentence examples. Output only valid JSON."
        },
        {
          role: "user",
          content: `Phrase: ${cleanPhrase}\n\n${schemaInstruction}`
        }
      ]
    })
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`OpenAI vocabulary examples failed (${response.status}): ${message}`);
  }

  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content || "";
  const parsed = extractJsonObject(content);

  if (!parsed || typeof parsed !== "object") {
    throw new Error("Could not parse vocabulary examples JSON from model response.");
  }

  if (!Array.isArray(parsed.examples)) return [];

  return parsed.examples
    .filter((item) => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, 6);
}

async function generateSpeakingMission(phrases) {
  const cleanPhrases = Array.isArray(phrases)
    ? phrases
        .map((item) => String(item || "").trim())
        .filter(Boolean)
        .slice(0, 5)
    : [];

  if (cleanPhrases.length === 0) {
    return {
      prompt: "Describe your day in 3 to 4 sentences.",
      required_phrases: [],
      sample_answer: "Today I focused on learning English and reviewing my notes from yesterday."
    };
  }

  const schemaInstruction = `Return strict JSON with this exact shape:\n{\n  "prompt": "string",\n  "required_phrases": ["string"],\n  "sample_answer": "string"\n}\nRules:\n- prompt should ask for a 20-40 second spoken response\n- required_phrases must include exactly the provided phrases\n- sample_answer should naturally use all required_phrases in concise spoken-style English`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: OPENAI_CHAT_MODEL,
      temperature: 0.35,
      messages: [
        {
          role: "system",
          content: "You are an English speaking coach. Output only valid JSON in the requested shape."
        },
        {
          role: "user",
          content: `Required phrases:\n- ${cleanPhrases.join("\n- ")}\n\n${schemaInstruction}`
        }
      ]
    })
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`OpenAI speaking mission generation failed (${response.status}): ${message}`);
  }

  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content || "";
  const parsed = extractJsonObject(content);

  if (!parsed || typeof parsed !== "object") {
    throw new Error("Could not parse speaking mission JSON from model response.");
  }

  const prompt = String(parsed.prompt || "").trim();
  const sampleAnswer = String(parsed.sample_answer || "").trim();
  const requiredPhrases = Array.isArray(parsed.required_phrases)
    ? parsed.required_phrases.map((item) => String(item || "").trim()).filter(Boolean)
    : [];

  return {
    prompt: prompt || `In 20 to 40 seconds, answer naturally using these phrases: ${cleanPhrases.join(", ")}.`,
    required_phrases: requiredPhrases.length > 0 ? requiredPhrases : cleanPhrases,
    sample_answer: sampleAnswer || null
  };
}

async function generateShadowingParagraph(phrases) {
  const cleanPhrases = Array.isArray(phrases)
    ? phrases
        .map((item) => String(item || "").trim())
        .filter(Boolean)
        .slice(0, 8)
    : [];

  if (cleanPhrases.length === 0) {
    return {
      paragraph:
        "Today I focused on improving my English by speaking clearly, organizing my thoughts, and using practical vocabulary in realistic situations.",
      required_phrases: []
    };
  }

  const schemaInstruction = `Return strict JSON with this exact shape:\n{\n  "paragraph": "string",\n  "required_phrases": ["string"]\n}\nRules:\n- paragraph should be a coherent 4-6 sentence paragraph for shadowing practice\n- write in natural spoken-style English with clear flow\n- required_phrases must include exactly the provided phrases\n- paragraph must naturally include every required phrase exactly once if possible`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: OPENAI_CHAT_MODEL,
      temperature: 0.35,
      messages: [
        {
          role: "system",
          content: "You are an English speaking coach. Output only valid JSON in the requested shape."
        },
        {
          role: "user",
          content: `Required phrases:\n- ${cleanPhrases.join("\n- ")}\n\n${schemaInstruction}`
        }
      ]
    })
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`OpenAI shadowing paragraph generation failed (${response.status}): ${message}`);
  }

  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content || "";
  const parsed = extractJsonObject(content);

  if (!parsed || typeof parsed !== "object") {
    throw new Error("Could not parse shadowing paragraph JSON from model response.");
  }

  const paragraph = String(parsed.paragraph || "").trim();
  const requiredPhrases = Array.isArray(parsed.required_phrases)
    ? parsed.required_phrases.map((item) => String(item || "").trim()).filter(Boolean)
    : [];

  return {
    paragraph:
      paragraph ||
      `In one short story, explain a realistic day while naturally using these phrases: ${cleanPhrases.join(", ")}.`,
    required_phrases: requiredPhrases.length > 0 ? requiredPhrases : cleanPhrases
  };
}

function normalizeShadowingTTSVoice(rawVoice) {
  const normalized = String(rawVoice || "alloy").trim().toLowerCase();
  return normalized || "alloy";
}

function normalizeShadowingTTSFormat(rawFormat) {
  const normalized = String(rawFormat || "mp3").trim().toLowerCase();
  const allowed = new Set(["mp3", "wav"]);
  return allowed.has(normalized) ? normalized : "mp3";
}

function normalizeShadowingTTSSpeed(rawSpeed) {
  const numeric = Number(rawSpeed);
  if (!Number.isFinite(numeric)) return 1.0;
  return Math.max(0.25, Math.min(2.0, numeric));
}

function buildShadowingAudioCacheKey({ paragraph, voice, format, speed }) {
  return createHash("sha256")
    .update(`${paragraph}::${voice}::${format}::${speed}::${OPENAI_TTS_MODEL}`)
    .digest("hex");
}

async function synthesizeShadowingAudio({ text, voice, format, speed }) {
  const response = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: OPENAI_TTS_MODEL,
      voice,
      input: text,
      format,
      speed
    })
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`OpenAI TTS failed (${response.status}): ${message}`);
  }

  const audioBuffer = Buffer.from(await response.arrayBuffer());
  return audioBuffer;
}

function normalizeBehavioralCategory(rawCategory) {
  const allowed = new Set(["mixed", "leadership", "conflict", "failure", "ownership", "teamwork", "ambiguity", "impact"]);
  const normalized = String(rawCategory || "mixed").trim().toLowerCase();
  return allowed.has(normalized) ? normalized : "mixed";
}

async function generateBehavioralQuestion(category) {
  const normalizedCategory = normalizeBehavioralCategory(category);

  const schemaInstruction = `Return strict JSON with this exact shape:\n{\n  "prompt": "string",\n  "category": "mixed|leadership|conflict|failure|ownership|teamwork|ambiguity|impact",\n  "focus": "string"\n}\nRules:\n- prompt must be a realistic behavioral interview question for the specified category\n- focus should be a concise coaching hint (max 12 words)\n- category in output must match requested category unless requested category is mixed`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: OPENAI_CHAT_MODEL,
      temperature: 0.45,
      messages: [
        {
          role: "system",
          content: "You are a behavioral interview coach. Output only valid JSON in the requested shape."
        },
        {
          role: "user",
          content: `Requested category: ${normalizedCategory}\n\n${schemaInstruction}`
        }
      ]
    })
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`OpenAI behavioral question generation failed (${response.status}): ${message}`);
  }

  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content || "";
  const parsed = extractJsonObject(content);

  if (!parsed || typeof parsed !== "object") {
    throw new Error("Could not parse behavioral question JSON from model response.");
  }

  const prompt = String(parsed.prompt || "").trim();
  const modelCategory = normalizeBehavioralCategory(parsed.category);
  const focus = String(parsed.focus || "").trim();

  return {
    prompt: prompt || "Tell me about a time you handled a difficult teammate.",
    category: normalizedCategory === "mixed" ? modelCategory : normalizedCategory,
    focus: focus || "Use STAR and include measurable impact."
  };
}

async function evaluateBehavioralAnswer(question, answerTranscript) {
  const cleanPrompt = String(question?.prompt || "").trim();
  const cleanCategory = normalizeBehavioralCategory(question?.category);
  const cleanFocus = String(question?.focus || "").trim();
  const cleanAnswer = String(answerTranscript || "").trim();

  if (!cleanAnswer) {
    return {
      summary_feedback: "I couldn't detect enough answer content. Try again and speak in complete STAR sentences.",
      star_coverage: {
        situation: false,
        task: false,
        action: false,
        result: false
      },
      rubric: {
        clarity: 1,
        ownership: 1,
        specificity: 1,
        impact: 1,
        conciseness: 1
      },
      improved_answer: "In my previous role, I faced [situation], my goal was [task], I took [actions], and the result was [quantified impact].",
      follow_up_questions: [
        "How did you measure success?",
        "What would you do differently next time?"
      ]
    };
  }

  const schemaInstruction = `Return strict JSON with this exact shape:\n{\n  "summary_feedback": "string",\n  "star_coverage": { "situation": true, "task": true, "action": true, "result": true },\n  "rubric": { "clarity": 1, "ownership": 1, "specificity": 1, "impact": 1, "conciseness": 1 },\n  "improved_answer": "string",\n  "follow_up_questions": ["string"]\n}\nRules:\n- rubric values must be integers from 1 to 5\n- follow_up_questions should have 2 to 3 realistic interviewer follow-ups\n- improved_answer must be concise and interview-ready, using STAR flow\n- be constructive and specific`;

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
          content: "You are a senior behavioral interview coach. Output only valid JSON in the requested shape."
        },
        {
          role: "user",
          content: `Question category: ${cleanCategory}\nQuestion focus: ${cleanFocus}\nQuestion prompt: ${cleanPrompt}\n\nCandidate answer transcript:\n${cleanAnswer}\n\n${schemaInstruction}`
        }
      ]
    })
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`OpenAI behavioral evaluation failed (${response.status}): ${message}`);
  }

  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content || "";
  const parsed = extractJsonObject(content);

  if (!parsed || typeof parsed !== "object") {
    throw new Error("Could not parse behavioral evaluation JSON from model response.");
  }

  const summaryFeedback = String(parsed.summary_feedback || "").trim();
  const star = parsed.star_coverage && typeof parsed.star_coverage === "object" ? parsed.star_coverage : {};
  const rubric = parsed.rubric && typeof parsed.rubric === "object" ? parsed.rubric : {};
  const improvedAnswer = String(parsed.improved_answer || "").trim();
  const followUpQuestions = Array.isArray(parsed.follow_up_questions)
    ? parsed.follow_up_questions.map((q) => String(q || "").trim()).filter(Boolean).slice(0, 3)
    : [];

  const score = (value) => {
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) return 3;
    return Math.max(1, Math.min(5, Math.round(numeric)));
  };

  return {
    summary_feedback: summaryFeedback || "Solid attempt. Improve structure with clearer STAR progression.",
    star_coverage: {
      situation: Boolean(star.situation),
      task: Boolean(star.task),
      action: Boolean(star.action),
      result: Boolean(star.result)
    },
    rubric: {
      clarity: score(rubric.clarity),
      ownership: score(rubric.ownership),
      specificity: score(rubric.specificity),
      impact: score(rubric.impact),
      conciseness: score(rubric.conciseness)
    },
    improved_answer:
      improvedAnswer ||
      "In my previous role, I addressed a key challenge by clarifying goals, coordinating stakeholders, and delivering a measurable improvement.",
    follow_up_questions:
      followUpQuestions.length > 0
        ? followUpQuestions
        : [
            "How did you prioritize your actions?",
            "What metric best demonstrated impact?"
          ]
  };
}

function sanitizeSessionTitle(rawTitle, transcriptFallback) {
  const normalized = String(rawTitle || "")
    .replace(/[\r\n]+/g, " ")
    .replace(/[^\p{L}\p{N}\s']/gu, " ")
    .replace(/\s+/g, " ")
    .trim();

  const words = normalized.split(" ").filter(Boolean).slice(0, 3);
  if (words.length > 0) {
    return words.join(" ");
  }

  const fallbackWords = String(transcriptFallback || "")
    .replace(/[^\p{L}\p{N}\s']/gu, " ")
    .replace(/\s+/g, " ")
    .trim()
    .split(" ")
    .filter(Boolean)
    .slice(0, 3);

  return fallbackWords.length > 0 ? fallbackWords.join(" ") : "Untitled Session";
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

  if (req.method === "GET" && req.url === "/vocabulary-manager") {
    try {
      const html = readFileSync(VOCABULARY_MANAGER_PAGE_PATH, "utf8");
      return sendHtml(res, 200, html);
    } catch {
      return sendHtml(res, 500, "<h1>Could not load vocabulary manager page.</h1>");
    }
  }

  if (req.method === "GET" && req.url === "/v1/vocabulary/cloud") {
    const payload = readCloudVocabularyStore();
    return sendJson(res, 200, payload);
  }

  if (req.method === "PUT" && req.url === "/v1/vocabulary/cloud") {
    try {
      const body = await readJsonBody(req);
      const items = Array.isArray(body?.items) ? body.items : null;

      if (!items) {
        return sendJson(res, 400, { error: "items array is required" });
      }

      const saved = writeCloudVocabularyStore(items);
      return sendJson(res, 200, saved);
    } catch (error) {
      return sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Failed to save cloud vocabulary"
      });
    }
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
    const tone = normalizeRewriteTone(parsed.tone);
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
      const rewritten = await rewriteAndCoach({ mode, transcript, tone });

      return sendJson(res, 200, {
        title: rewritten.title,
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

  if (req.method === "POST" && req.url === "/v1/vocabulary/extract-from-audio") {
    const contentType = req.headers["content-type"] || "";
    const boundaryMatch = contentType.match(/boundary=(.+)$/);
    if (!boundaryMatch) {
      return sendJson(res, 400, { error: "Expected multipart/form-data with boundary" });
    }

    if (!OPENAI_API_KEY) {
      return sendJson(res, 500, {
        error: "OPENAI_API_KEY is not configured on backend proxy"
      });
    }

    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = Buffer.concat(chunks);
    const parsed = parseMultipart(body, boundaryMatch[1]);
    const audio = parsed.audio;

    if (!audio || !audio.data || audio.data.length === 0) {
      return sendJson(res, 400, { error: "audio file is required" });
    }

    try {
      const transcript = await transcribeAudio(audio);
      const extracted = await extractVocabularyFromTranscript(transcript);

      return sendJson(res, 200, {
        transcript: extracted.transcript,
        phrase: extracted.phrase,
        meaning: extracted.meaning,
        corrected_sentence: extracted.corrected_sentence
      });
    } catch (error) {
      return sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Failed to extract vocabulary from audio"
      });
    }
  }

  if (req.method === "POST" && req.url === "/v1/vocabulary/examples") {
    if (!OPENAI_API_KEY) {
      return sendJson(res, 500, {
        error: "OPENAI_API_KEY is not configured on backend proxy"
      });
    }

    try {
      const payload = await readJsonBody(req);
      const phrase = String(payload?.phrase || "").trim();
      if (!phrase) {
        return sendJson(res, 400, { error: "phrase is required" });
      }

      const examples = await generateVocabularyExamples(phrase);
      return sendJson(res, 200, { examples });
    } catch (error) {
      return sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Failed to generate vocabulary examples"
      });
    }
  }

  if (req.method === "POST" && req.url === "/v1/vocabulary/speaking-mission") {
    if (!OPENAI_API_KEY) {
      return sendJson(res, 500, {
        error: "OPENAI_API_KEY is not configured on backend proxy"
      });
    }

    try {
      const payload = await readJsonBody(req);
      const phrases = Array.isArray(payload?.phrases) ? payload.phrases : [];
      if (!phrases.length) {
        return sendJson(res, 400, { error: "phrases array is required" });
      }

      const mission = await generateSpeakingMission(phrases);
      return sendJson(res, 200, { mission });
    } catch (error) {
      return sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Failed to generate speaking mission"
      });
    }
  }

  if (req.method === "POST" && req.url === "/v1/vocabulary/shadowing-paragraph") {
    if (!OPENAI_API_KEY) {
      return sendJson(res, 500, {
        error: "OPENAI_API_KEY is not configured on backend proxy"
      });
    }

    try {
      const payload = await readJsonBody(req);
      const phrases = Array.isArray(payload?.phrases) ? payload.phrases : [];
      if (!phrases.length) {
        return sendJson(res, 400, { error: "phrases array is required" });
      }

      const shadowing = await generateShadowingParagraph(phrases);
      return sendJson(res, 200, { shadowing });
    } catch (error) {
      return sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Failed to generate shadowing paragraph"
      });
    }
  }

  if (req.method === "POST" && req.url === "/v1/practice/shadowing-prompt-with-audio") {
    if (!OPENAI_API_KEY) {
      return sendJson(res, 500, {
        error: "OPENAI_API_KEY is not configured on backend proxy"
      });
    }

    try {
      const payload = await readJsonBody(req);
      const phrases = Array.isArray(payload?.phrases) ? payload.phrases : [];
      if (!phrases.length) {
        return sendJson(res, 400, { error: "phrases array is required" });
      }

      const voice = normalizeShadowingTTSVoice(payload?.voice);
      const format = normalizeShadowingTTSFormat(payload?.format);
      const speed = normalizeShadowingTTSSpeed(payload?.speed);

      const shadowing = await generateShadowingParagraph(phrases);
      const paragraph = String(shadowing?.paragraph || "").trim();
      if (!paragraph) {
        return sendJson(res, 500, { error: "Generated shadowing paragraph was empty" });
      }

      const cacheKey = buildShadowingAudioCacheKey({ paragraph, voice, format, speed });

      try {
        const audioBuffer = await synthesizeShadowingAudio({
          text: paragraph,
          voice,
          format,
          speed
        });

        return sendJson(res, 200, {
          paragraph,
          required_phrases: Array.isArray(shadowing.required_phrases) ? shadowing.required_phrases : [],
          tts: {
            format,
            voice,
            speed,
            audio_base64: audioBuffer.toString("base64"),
            cache_key: cacheKey
          }
        });
      } catch (ttsError) {
        console.error("/v1/practice/shadowing-prompt-with-audio TTS error:", ttsError);

        return sendJson(res, 200, {
          paragraph,
          required_phrases: Array.isArray(shadowing.required_phrases) ? shadowing.required_phrases : [],
          tts: null,
          warning: "TTS generation failed; paragraph generated without audio."
        });
      }
    } catch (error) {
      return sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Failed to generate shadowing prompt with audio"
      });
    }
  }

  if (req.method === "POST" && req.url === "/v1/interview/behavioral/question") {
    if (!OPENAI_API_KEY) {
      return sendJson(res, 500, {
        error: "OPENAI_API_KEY is not configured on backend proxy"
      });
    }

    try {
      const payload = await readJsonBody(req);
      const category = normalizeBehavioralCategory(payload?.category);
      const question = await generateBehavioralQuestion(category);
      return sendJson(res, 200, { question });
    } catch (error) {
      return sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Failed to generate behavioral question"
      });
    }
  }

  if (req.method === "POST" && req.url === "/v1/interview/behavioral/evaluate") {
    if (!OPENAI_API_KEY) {
      return sendJson(res, 500, {
        error: "OPENAI_API_KEY is not configured on backend proxy"
      });
    }

    try {
      const payload = await readJsonBody(req);
      const question = payload?.question && typeof payload.question === "object" ? payload.question : null;
      const answerTranscript = String(payload?.answer_transcript || "").trim();

      if (!question || !String(question.prompt || "").trim()) {
        return sendJson(res, 400, { error: "question object with prompt is required" });
      }

      if (!answerTranscript) {
        return sendJson(res, 400, { error: "answer_transcript is required" });
      }

      const evaluation = await evaluateBehavioralAnswer(question, answerTranscript);
      return sendJson(res, 200, { evaluation });
    } catch (error) {
      return sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Failed to evaluate behavioral answer"
      });
    }
  }

  return sendJson(res, 404, { error: "Not found" });
});

server.listen(PORT, () => {
  console.log(`Coach backend proxy running on http://127.0.0.1:${PORT}`);
});

// aiFunctions.js
import { onCall, HttpsError } from "firebase-functions/v2/https";
import fetch from "node-fetch";

/**
 * 🧠 توليد "التحقق عبر اختبار قصير" باستخدام Gemini أو OpenAI
 * input: articleText
 * output: { question, options, answer }
 */
export const generateShortTestVerification = onCall(async (request) => {
  const auth = request.auth;
  if (!auth || !auth.uid)
    throw new HttpsError("unauthenticated", "User not logged in");

  const articleText = request.data?.articleText;
  const apiType = request.data?.apiType || "gemini";

  if (!articleText || articleText.length < 80)
    throw new HttpsError("invalid-argument", "ARTICLE_TEXT_TOO_SHORT");

  const prompt = `
  اقرأ النص التالي وصِغ "تحققًا عبر اختبار قصير" مكونًا من سؤال واحد مع أربع اختيارات.
  اجعل السؤال متعلقًا بمضمون النص فقط.
  أرجع النتيجة بصيغة JSON واضحة كالتالي:
  {
    "question": "...",
    "options": ["...", "...", "...", "..."],
    "answer": "..."
  }
  ---
  النص:
  ${articleText}
  `;

  try {
    let response, json;

    if (apiType === "gemini") {
      // ✅ Gemini API
      response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=${process.env.GEMINI_API_KEY}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
          }),
        }
      );
      const result = await response.json();
      json = result?.candidates?.[0]?.content?.parts?.[0]?.text || "No response";
    } else {
      // ✅ OpenAI API
      response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          messages: [{ role: "user", content: prompt }],
        }),
      });
      const result = await response.json();
      json = result?.choices?.[0]?.message?.content || "{}";
    }

    return json;
  } catch (err) {
    console.error("❌ AI Function Error:", err);
    throw new HttpsError("internal", "AI_GENERATION_FAILED");
  }
});
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

exports.resolveProductName = onRequest(
  {
    region: "us-central1",
    secrets: [GEMINI_API_KEY],
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const { productName, productType } = req.body || {};

     if (!productName || productName.toString().trim().length === 0) {
        return res.status(400).json({ error: "productName is required" });
      }

      const prompt = `
You are helping normalize a product name and estimate density for carbon calculation.

User product name: "${productName}"
Product type: "${productType || ""}"

Return JSON only in this exact schema:
{
  "canonical_query": "short english product phrase",
  "alternatives": ["alt 1", "alt 2"],
  "category": "short category",
  "density_kg_per_liter": 0.0,
  "source": "short trusted source note",
  "confidence": 0.0,
  "trusted": true
}

Rules:
- Translate Arabic to English when needed.
- Infer the most likely common product/category.
- If productType is liquid, return density in kg/L.
- If productType is solid, density_kg_per_liter may be null.
- Prefer a reasonable trusted estimate.
- Output valid JSON only.
- No markdown.
`;

      const geminiRes = await fetch(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": GEMINI_API_KEY.value(),
          },
          body: JSON.stringify({
            contents: [
              {
                parts: [{ text: prompt }],
              },
            ],
            generationConfig: {
              temperature: 0.2,
              responseMimeType: "application/json",
            },
          }),
        }
      );

      const geminiData = await geminiRes.json();

      if (!geminiRes.ok) {
        return res.status(geminiRes.status).json(geminiData);
      }

      const text = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;

      if (!text) {
        return res.status(500).json({ error: "Empty Gemini response" });
      }

      const parsed = JSON.parse(text);

      return res.status(200).json(parsed);
    } catch (e) {
      return res.status(500).json({ error: e.message });
    }
  }
);
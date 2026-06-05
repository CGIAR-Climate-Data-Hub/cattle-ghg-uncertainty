# Getting started with the GMH Uncertainty Translator

A free AI assistant that turns your raw cattle data (your own Excel/CSV files, whatever shape they're in) into the strict template the Cattle Uncertainty App needs. **About 10 minutes, no installation, no payment.**

---

## Before you start

You'll need:

1. Your raw inventory data file(s) — Excel, CSV, or even a PDF/screenshot of a table.
2. The filled **Pre-flight Questionnaire** (`questionnaire.md` — download from the app's Resources tab).
3. About 10 minutes.

---

## Step-by-step

### 1. Open claude.ai and sign in (free)

- Go to **https://claude.ai**
- Click **Sign up** if you don't have an account. The free tier is enough for this task. You can sign in with Google, email, or Apple — no payment details needed.

### 2. Open the Translator Project

- Click this shared link: **[GMH Uncertainty Translator](https://claude.ai/project/019e4594-d13d-761e-a6fb-71e242eb9804)**
- *(If the link doesn't work, see the "Backup option" at the bottom of this page.)*

You'll land in a chat window pre-loaded with the parameter catalogue, template schema, and mapping examples for the app. Claude knows everything it needs to translate your data.

### 3. Paste your filled questionnaire as your first message

- Open `questionnaire.md` (or your filled `.docx` version), select all, copy.
- Paste it as the first message into the Translator chat.
- Send.

Claude will briefly summarise back what it understood, and ask which file(s) you'd like to upload.

### 4. Upload your raw data file(s)

- Click the **paperclip icon** in the chat input box.
- Select your file(s) — `.xlsx`, `.csv`, `.pdf`, or images of tables all work.
- Send.

Claude will inspect the file, propose a column-mapping table, and **ask you to confirm anything ambiguous**.

### 5. Answer Claude's clarification questions

You'll typically see 2–5 questions like:

- "Your column `weight` — is this body weight (current) or mature weight (adult target)?"
- "Your milk yield column is in litres — should I convert to kg using ×1.03, or treat 1 L = 1 kg?"

Answer in plain language. Claude will adjust and re-confirm.

### 6. Receive the filled template

When Claude is satisfied, it will produce **`filled_template_for_app.xlsx`** as a downloadable file (click the download icon next to it in the chat).

> If Claude tells you the analysis tool is unavailable and instead gives you three CSV blocks (Inventory_Metadata, Parameters, Manure_Management), follow the "Backup option" at the bottom of this page.

### 7. Open the Cattle Uncertainty App → Data Input tab → upload the file

- In the app's **Data Input** tab, click **Upload your filled template (.xlsx)**.
- Select `filled_template_for_app.xlsx`.
- The app will validate the file and load it. Any issues will show in the **QA/QC** tab — green = OK, amber = review, red = fix.

You're now ready to run the uncertainty simulation.

---

## Tips for a smooth session

- **Be specific.** "Population in column B is total dairy cattle in 2022" beats "B is animals".
- **Tell Claude when something is wrong.** If a unit conversion looks off, just say "wait — that should be 275 kg, not 599 kg" and Claude will fix it.
- **Ask Claude to explain.** "Why did you set Ym = 6.5?" is a fine question. It'll cite the IPCC table.
- **Don't worry about advanced parameters.** The 16 IPCC coefficients (Cfi, Ca, Ym, EF3, ...) ship with sensible defaults. You only need to provide them if you have country-specific measurements.

---

## Privacy

Claude.ai uses your messages and uploads in line with [Anthropic's privacy policy](https://www.anthropic.com/legal/privacy). For national GHG inventory data this is generally fine because the data is intended for public reporting under the UNFCCC. If your ministry has a policy against uploading internal data to third-party AI services, **do not use this tool** — fill the template manually from the app's Resources tab instead.

---

## Backup option — if the Project link doesn't work, or Claude can't generate the .xlsx

You can still get most of the value from any AI chat:

1. Open any free AI chat: claude.ai, ChatGPT, Gemini.
2. Paste the contents of `param_catalogue.md` and `template_schema.md` (download both from the app's Resources tab) as your first message, followed by: *"You are the GMH Uncertainty Translator. Use the schema above to help me convert my raw data into per-sheet CSV blocks. Ask me the standard six onboarding questions first."*
3. Paste your filled questionnaire and proceed as in Steps 4–5 above.
4. When the AI produces three CSV blocks (one per sheet), open the **blank template** (download it from the app's Data Input tab → "Download blank template"), paste each block into the matching sheet starting at row 4, save, and upload.

This is slower but works on any AI without the persistent Project.

---

## When the AI gets it wrong

The Translator is a helper, not an oracle. Always:

- **Spot-check** the key numbers (population, body weight, milk yield) by comparing with your original file.
- **Watch the QA/QC tab** for amber/red flags after upload — those highlight values outside IPCC ranges.
- **Tell us** when something is off. Use the in-app Feedback tab to report mistranslations so we can improve the prompt.

---

*Made by the CGIAR Alliance, Climate Action–Net Zero Initiative, Project D614 — GMH Emissions Uncertainty.*

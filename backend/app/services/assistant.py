"""JAGO assistant.

Baseline: lexicon-based intent detection (English, Hindi, Hinglish) with replies
built from the student's real data (eligibility, applications, documents).
This keeps answers correct and auditable. To scale to more languages, put a
translation / NLU layer in front (e.g. Bhashini or an IndicBERT classifier)
and keep `build_context` + the reply functions as the grounding layer.

Add a language by adding one dict to `T` and one entry to `DOC_NAMES` / `STATUS_NAMES`.
"""
import re

LEXICON: dict[str, list[str]] = {
    "greeting": ["hello", "hi", "hey", "namaste", "johar", "नमस्ते", "जोहार", "हेलो"],
    "eligibility": ["eligible", "eligibility", "qualify", "which scheme", "what can i apply", "patra", "yogya",
                    "पात्र", "योग्य", "योजना", "कौन सी", "कौन सा", "कौन-सी"],
    "documents": ["document", "documents", "certificate", "papers", "required", "dastavej", "kagaz",
                  "दस्तावेज", "कागज", "प्रमाण"],
    "status": ["status", "track", "where is", "progress", "kya hua", "sthiti", "स्थिति", "स्टेटस", "कहाँ", "कहां"],
    "deficiency": ["deficiency", "correction", "rejected", "objection", "problem", "fix", "kami", "sudhar",
                   "कमी", "सुधार", "आपत्ति", "गलती"],
    "payment": ["payment", "money", "dbt", "paisa", "paise", "amount", "bank", "credited", "bhugtan",
                "भुगतान", "पैसे", "राशि", "खाते", "खाता"],
    "apply": ["apply", "how to", "start", "form", "kaise", "आवेदन कैसे", "अप्लाई", "फॉर्म", "फार्म"],
}

STATUS_NAMES = {
    "en": {"DRAFT": "a draft", "SUBMITTED": "submitted", "UNDER_VERIFICATION": "under verification",
           "DEFICIENCY": "waiting for a correction from you", "VERIFIED": "verified", "SANCTIONED": "sanctioned",
           "DBT_PAID": "paid", "REJECTED": "not approved"},
    "hi": {"DRAFT": "ड्राफ्ट में है", "SUBMITTED": "जमा हो गया है", "UNDER_VERIFICATION": "सत्यापन में है",
           "DEFICIENCY": "आपके सुधार का इंतज़ार है", "VERIFIED": "सत्यापित हो गया है", "SANCTIONED": "स्वीकृत हो गया है",
           "DBT_PAID": "का भुगतान हो चुका है", "REJECTED": "स्वीकृत नहीं हुआ"},
}
DOC_NAMES = {
    "en": {"CASTE_CERT": "Caste (ST) certificate", "INCOME_CERT": "Income certificate", "MARKSHEET": "Marksheet",
           "BANK_PASSBOOK": "Bank passbook", "ADMISSION_LETTER": "Admission letter", "NET_JRF_CERT": "UGC-NET / JRF certificate"},
    "hi": {"CASTE_CERT": "जाति (ST) प्रमाण पत्र", "INCOME_CERT": "आय प्रमाण पत्र", "MARKSHEET": "अंकपत्र",
           "BANK_PASSBOOK": "बैंक पासबुक", "ADMISSION_LETTER": "प्रवेश पत्र", "NET_JRF_CERT": "UGC-NET / JRF प्रमाण पत्र"},
}
T = {
    "en": {
        "greeting": "Johar {name}! I'm JAGO. I can help with what you can apply for, documents, application status, corrections and payments.",
        "elig_yes": "You can apply for: {list}.",
        "elig_review": "A reviewer will check these with you: {list}.",
        "elig_none": "No scheme matches your profile yet. Complete your course, institution and family income in your profile and ask me again.",
        "docs_head": "Documents for {scheme}:",
        "doc_have": "{doc}: in your wallet",
        "doc_miss": "{doc}: missing. Add it from DigiLocker or upload it",
        "docs_none": "Ask me about eligibility first, then I can list the documents for each scheme.",
        "status_line": "{scheme} is {status}.",
        "status_none": "You have not started an application. Ask me which schemes you can apply for.",
        "def_head": "Corrections waiting for you:",
        "def_none": "No corrections are pending.",
        "pay_paid": "{scheme}: ₹{amount} was paid to your bank account.",
        "pay_sanc": "{scheme}: ₹{amount} is sanctioned. Payment follows.",
        "pay_none": "No payment yet. Payments show here after your scholarship is sanctioned.",
        "apply": "Open Schemes, pick one you can apply for and tap Start application. Your saved details fill in automatically. It also works offline and syncs when you are back online.",
        "fallback": "I did not understand that. You can ask about eligibility, documents, application status, corrections or payments.",
        "chips": ["Which schemes can I apply for?", "What documents do I need?", "Where is my application?", "Any corrections pending?"],
    },
    "hi": {
        "greeting": "जोहार {name}! मैं JAGO हूँ। मैं आपकी पात्रता, दस्तावेज़, आवेदन की स्थिति, सुधार और भुगतान में मदद कर सकता हूँ।",
        "elig_yes": "आप इनके लिए आवेदन कर सकते हैं: {list}।",
        "elig_review": "इनकी जाँच अधिकारी आपके साथ करेंगे: {list}।",
        "elig_none": "अभी कोई योजना आपकी प्रोफ़ाइल से मेल नहीं खाती। प्रोफ़ाइल में कोर्स, संस्थान और पारिवारिक आय भरकर फिर पूछें।",
        "docs_head": "{scheme} के लिए दस्तावेज़:",
        "doc_have": "{doc}: आपके वॉलेट में है",
        "doc_miss": "{doc}: नहीं है। DigiLocker से जोड़ें या अपलोड करें",
        "docs_none": "पहले पात्रता के बारे में पूछें, फिर मैं हर योजना के दस्तावेज़ बता दूँगा।",
        "status_line": "{scheme} {status}।",
        "status_none": "आपने अभी कोई आवेदन शुरू नहीं किया है। पूछें कि आप किन योजनाओं के लिए आवेदन कर सकते हैं।",
        "def_head": "आपके लिए सुधार बाकी हैं:",
        "def_none": "कोई सुधार बाकी नहीं है।",
        "pay_paid": "{scheme}: ₹{amount} आपके बैंक खाते में भेज दिए गए हैं।",
        "pay_sanc": "{scheme}: ₹{amount} स्वीकृत हुए हैं। भुगतान जल्द होगा।",
        "pay_none": "अभी कोई भुगतान नहीं हुआ। छात्रवृत्ति स्वीकृत होने के बाद भुगतान यहाँ दिखेगा।",
        "apply": "योजनाएँ खोलें, अपनी पात्र योजना चुनें और आवेदन शुरू करें दबाएँ। आपकी सहेजी जानकारी अपने आप भर जाएगी। इंटरनेट न हो तब भी काम होगा और जुड़ने पर सिंक हो जाएगा।",
        "fallback": "मैं समझ नहीं पाया। आप पात्रता, दस्तावेज़, आवेदन की स्थिति, सुधार या भुगतान के बारे में पूछ सकते हैं।",
        "chips": ["मैं किन योजनाओं के लिए आवेदन कर सकता हूँ?", "मुझे कौन से दस्तावेज़ चाहिए?", "मेरा आवेदन कहाँ है?", "कोई सुधार बाकी है?"],
    },
}
_DEVANAGARI = re.compile(r"[\u0900-\u097F]")


def detect_language(message: str, preferred: str = "en") -> str:
    if _DEVANAGARI.search(message):
        return "hi"
    return preferred if preferred in T else "en"


def _hit(word: str, text: str) -> bool:
    """Latin keywords match at a word start (whole word when short, so 'hi' never fires inside 'which')."""
    if word.isascii():
        return re.search(r"\b" + re.escape(word) + (r"\b" if len(word) <= 4 else ""), text) is not None
    return word in text


def detect_intent(message: str) -> str:
    text = message.lower()
    best, best_score = "fallback", 0
    for intent, words in LEXICON.items():
        score = sum(len(w) for w in words if _hit(w, text))
        if score > best_score:
            best, best_score = intent, score
    return best


def _join(items: list[str]) -> str:
    return ", ".join(items)


def reply(message: str, preferred_lang: str, ctx: dict) -> dict:
    lang = detect_language(message, preferred_lang)
    t, statuses, docs = T[lang], STATUS_NAMES[lang], DOC_NAMES[lang]
    intent = detect_intent(message)
    lines: list[str] = []

    if intent == "greeting":
        lines.append(t["greeting"].format(name=ctx.get("name", "")))
    elif intent == "eligibility":
        elig = ctx.get("eligibility", [])
        yes = [e["short_name"] for e in elig if e["status"] == "ELIGIBLE"]
        rev = [e["short_name"] for e in elig if e["status"] == "NEEDS_REVIEW"]
        if yes:
            lines.append(t["elig_yes"].format(list=_join(yes)))
        if rev:
            lines.append(t["elig_review"].format(list=_join(rev)))
        if not yes and not rev:
            lines.append(t["elig_none"])
    elif intent == "documents":
        elig = [e for e in ctx.get("eligibility", []) if e["status"] in ("ELIGIBLE", "NEEDS_REVIEW")]
        have = set(ctx.get("documents_have", []))
        if not elig:
            lines.append(t["docs_none"])
        for e in elig:
            lines.append(t["docs_head"].format(scheme=e["short_name"]))
            for d in ctx.get("documents_by_scheme", {}).get(e["scheme_code"], []):
                key = "doc_have" if d in have else "doc_miss"
                lines.append("• " + t[key].format(doc=docs.get(d, d)))
    elif intent == "status":
        apps = ctx.get("applications", [])
        lines += [t["status_line"].format(scheme=a["scheme_name"], status=statuses.get(a["status"], a["status"])) for a in apps]
        if not apps:
            lines.append(t["status_none"])
    elif intent == "deficiency":
        open_items = [(a["scheme_name"], m) for a in ctx.get("applications", []) for m in a.get("open_deficiencies", [])]
        if open_items:
            lines.append(t["def_head"])
            lines += [f"• {s}: {m}" for s, m in open_items]
        else:
            lines.append(t["def_none"])
    elif intent == "payment":
        for a in ctx.get("applications", []):
            if a.get("paid"):
                lines.append(t["pay_paid"].format(scheme=a["scheme_name"], amount=f"{a['paid']:,.0f}"))
            elif a.get("sanctioned"):
                lines.append(t["pay_sanc"].format(scheme=a["scheme_name"], amount=f"{a['sanctioned']:,.0f}"))
        if not lines:
            lines.append(t["pay_none"])
    elif intent == "apply":
        lines.append(t["apply"])
    else:
        lines.append(t["fallback"])

    return {"intent": intent, "language": lang, "reply": "\n".join(lines), "suggestions": t["chips"]}

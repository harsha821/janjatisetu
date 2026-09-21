/// Multilingual string table supporting English, Hindi (हिन्दी), Telugu (తెలుగు),
/// Tamil (தமிழ்), Bengali (বাংলা), and Kannada (ಕನ್ನಡ).
class Strings {
  Strings(this.lang);

  final String lang;

  static const List<Map<String, String>> supportedLanguages = [
    {'code': 'en', 'label': 'English', 'native': 'English'},
    {'code': 'hi', 'label': 'Hindi', 'native': 'हिन्दी'},
    {'code': 'te', 'label': 'Telugu', 'native': 'తెలుగు'},
    {'code': 'ta', 'label': 'Tamil', 'native': 'தமிழ்'},
    {'code': 'bn', 'label': 'Bengali', 'native': 'বাংলা'},
    {'code': 'kn', 'label': 'Kannada', 'native': 'ಕನ್ನಡ'},
  ];

  String _t({
    required String en,
    String? hi,
    String? te,
    String? ta,
    String? bn,
    String? kn,
  }) {
    switch (lang) {
      case 'hi':
        return hi ?? en;
      case 'te':
        return te ?? hi ?? en;
      case 'ta':
        return ta ?? hi ?? en;
      case 'bn':
        return bn ?? hi ?? en;
      case 'kn':
        return kn ?? hi ?? en;
      default:
        return en;
    }
  }

  String get appName => 'JanjatiSetu';
  String get greeting => _t(en: 'Namaste', hi: 'नमस्ते', te: 'నమస్కారం', ta: 'வணக்கம்', bn: 'নমস্কার', kn: 'ನಮಸ್ಕಾರ');
  String get tagline => _t(
        en: 'Every student counts',
        hi: 'हर छात्र मायने रखता है',
        te: 'ప్రతి విద్యార్థి ముఖ్యమే',
        ta: 'ஒவ்வொரு மாணவரும் முக்கியம்',
        bn: 'প্রতিটি শিক্ষার্থী গুরুত্বপূর্ণ',
        kn: 'ಪ್ರತಿಯೊಬ್ಬ ವಿದ್ಯಾರ್ಥಿಯೂ ಮುಖ್ಯ',
      );

  String get home => _t(en: 'Home', hi: 'होम', te: 'హోమ్', ta: 'முகப்பு', bn: 'হোম', kn: 'ಮುಖಪುಟ');
  String get schemes => _t(en: 'Schemes', hi: 'योजनाएँ', te: 'పథకాలు', ta: 'திட்டங்கள்', bn: 'প্রকল্পসমূহ', kn: 'ಯೋಜನೆಗಳು');
  String get wallet => _t(en: 'Wallet', hi: 'वॉलेट', te: 'వాలెట్', ta: 'வாலட்', bn: 'ওয়ালেট', kn: 'ವಾಲೆಟ್');
  String get jago => 'JAGO';
  String get profile => _t(en: 'Profile', hi: 'प्रोफ़ाइल', te: 'ప్రొఫైల్', ta: 'சுயவிவரம்', bn: 'প্রোফাইল', kn: 'ಪ್ರೊಫೈಲ್');

  String get login => _t(en: 'Log in', hi: 'लॉग इन करें', te: 'లాగిన్ చేయండి', ta: 'உள்நுழைக', bn: 'লগ ইন করুন', kn: 'ಲಾಗಿನ್ ಮಾಡಿ');
  String get register => _t(en: 'Create account', hi: 'खाता बनाएँ', te: 'ఖాతాను సృష్టించండి', ta: 'கணக்கை உருவாக்கு', bn: 'অ্যাকাউন্ট তৈরি করুন', kn: 'ಖಾತೆ ತೆರೆಯಿರಿ');
  String get phone => _t(en: 'Phone number', hi: 'फ़ोन नंबर', te: 'ఫోన్ నంబర్', ta: 'தொலைபேசி எண்', bn: 'ফোন নম্বর', kn: 'ಫೋನ್ ಸಂಖ್ಯೆ');
  String get password => _t(en: 'Password', hi: 'पासवर्ड', te: 'పాస్‌వర్డ్', ta: 'கடவுச்சொல்', bn: 'পাসওয়ার্ড', kn: 'ಪಾಸ್‌ವರ್ಡ್');
  String get fullName => _t(en: 'Full name', hi: 'पूरा नाम', te: 'పూర్తి పేరు', ta: 'முழு பெயர்', bn: 'সম্পূর্ণ নাম', kn: 'ಪೂರ್ಣ ಹೆಸರು');
  String get logout => _t(en: 'Log out', hi: 'लॉग आउट', te: 'లాగ్ అవుట్', ta: 'வெளியேறு', bn: 'লগ আউট', kn: 'ಲಾಗ್ ಔಟ್');

  String get yourApplications => _t(
        en: 'Your applications',
        hi: 'आपके आवेदन',
        te: 'మీ దరఖాస్తులు',
        ta: 'உங்கள் விண்ணப்பங்கள்',
        bn: 'আপনার আবেদনগুলি',
        kn: 'ನಿಮ್ಮ ಅರ್ಜಿಗಳು',
      );
  String get noApplicationsYet => _t(
        en: 'No applications yet. Check Schemes to see what you can apply for.',
        hi: 'अभी कोई आवेदन नहीं है। देखें कि आप किन योजनाओं के लिए आवेदन कर सकते हैं।',
        te: 'ఇంకా ఎటువంటి దరఖాస్తులు లేవు. మీరు దరఖాస్తు చేసుకోగల పథకాలను చూడండి.',
        ta: 'இன்னும் விண்ணப்பங்கள் இல்லை. திட்டங்களை சரிபார்க்கவும்.',
        bn: 'এখনও কোনো আবেদন নেই। আপনি যে প্রকল্পগুলির জন্য আবেদন করতে পারেন তা দেখুন।',
        kn: 'ಇನ್ನೂ ಯಾವುದೇ ಅರ್ಜಿಗಳಿಲ್ಲ. ಯೋಜನೆಗಳನ್ನು ಪರಿಶೀಲಿಸಿ.',
      );
  String get startApplication => _t(en: 'Start application', hi: 'आवेदन शुरू करें', te: 'దరఖాస్తు ప్రారంభించండి', ta: 'விண்ணப்பிக்கவும்', bn: 'আবেদন শুরু করুন', kn: 'ಅರ್ಜಿ ಸಲ್ಲಿಸಿ');
  String get continueApplication => _t(en: 'Continue', hi: 'जारी रखें', te: 'కొనసాగించండి', ta: 'தொடரவும்', bn: 'চালিয়ে যান', kn: 'ಮುಂದುವರಿಸಿ');
  String get alreadyApplied => _t(en: 'Already applied', hi: 'पहले से आवेदन किया', te: 'ఇప్పటికే దరఖాస్తు చేయబడింది', ta: 'ஏற்கனவே விண்ணப்பிக்கப்பட்டது', bn: 'ইতিমধ্যে আবেদন করা হয়েছে', kn: 'ಈಗಾಗಲೇ ಅರ್ಜಿ ಸಲ್ಲಿಸಲಾಗಿದೆ');
  String get submit => _t(en: 'Submit', hi: 'जमा करें', te: 'సమర్పించండి', ta: 'சமர்ப்பிக்கவும்', bn: 'জমা দিন', kn: 'ಸಲ್ಲಿಸಿ');
  String get save => _t(en: 'Save', hi: 'सहेजें', te: 'భద్రపరచండి', ta: 'சேமிக்கவும்', bn: 'সংরক্ষণ করুন', kn: 'ಉಳಿಸಿ');
  String get retry => _t(en: 'Retry', hi: 'फिर कोशिश करें', te: 'మళ్లీ ప్రయత్నించండి', ta: 'மீண்டும் முயற்சிக்கவும்', bn: 'আবার চেষ্টা করুন', kn: 'ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ');
  String get cancel => _t(en: 'Cancel', hi: 'रद्द करें', te: 'రద్దు చేయండి', ta: 'ரத்து செய்', bn: 'বাতিল করুন', kn: 'ರದ್ದುಮಾಡಿ');
  String get documents => _t(en: 'Documents', hi: 'दस्तावेज़', te: 'పత్రాలు', ta: 'ஆவணங்கள்', bn: 'নথিপত্র', kn: 'ದಾಖಲೆಗಳು');
  String get requiredDocuments => _t(en: 'Required documents', hi: 'आवश्यक दस्तावेज़', te: 'అవసరమైన పత్రాలు', ta: 'தேவையான ஆவணங்கள்', bn: 'প্রয়োজনীয় কাগজপত্র', kn: 'ಅಗತ್ಯ ದಾಖಲೆಗಳು');
  String get attach => _t(en: 'Attach', hi: 'जोड़ें', te: 'జతచేయండి', ta: 'இணைக்கவும்', bn: 'সংযুক্ত করুন', kn: 'ಲಗತ್ತಿಸಿ');
  String get attached => _t(en: 'Attached', hi: 'जुड़ा हुआ', te: 'జతచేయబడింది', ta: 'இணைக்கப்பட்டது', bn: 'সংযুক্ত হয়েছে', kn: 'ಲಗತ್ತಿಸಲಾಗಿದೆ');
  String get missing => _t(en: 'Missing', hi: 'गुम है', te: 'తప్పిపోయింది', ta: 'காணவில்லை', bn: 'অনুপস্থিত', kn: 'ಕಾಣೆಯಾಗಿದೆ');
  String get upload => _t(en: 'Upload', hi: 'अपलोड करें', te: 'అప్‌లోడ్ చేయండి', ta: 'பதிவேற்றவும்', bn: 'আপলোড করুন', kn: 'ಅಪ್‌ಲೋಡ್ ಮಾಡಿ');
  String get importFromDigilocker => _t(en: 'Import from DigiLocker', hi: 'DigiLocker से आयात करें', te: 'DigiLocker నుండి పొందండి', ta: 'DigiLocker இலிருந்து இறக்குமதி செய்க', bn: 'DigiLocker থেকে আনুন', kn: 'DigiLocker ನಿಂದ ತನ್ನಿ');
  String get uploadFromDevice => _t(en: 'Upload from device', hi: 'डिवाइस से अपलोड करें', te: 'డివైస్ నుండి అప్‌లోడ్ చేయండి', ta: 'சாதனத்திலிருந்து பதிவேற்றவும்', bn: 'ডিভাইস থেকে আপলোড করুন', kn: 'ಸಾಧನದಿಂದ ಅಪ್‌ಲೋಡ್ ಮಾಡಿ');
  String get timeline => _t(en: 'Timeline', hi: 'समयरेखा', te: 'కాలక్రమం', ta: 'காலவரிசை', bn: 'টাইমলাইন', kn: 'ಸಮಯರೇಖೆ');
  String get correctionNeeded => _t(en: 'Correction needed', hi: 'सुधार आवश्यक', te: 'సవరణ అవసరం', ta: 'திருத்தம் தேவை', bn: 'সংশোধন প্রয়োজন', kn: 'ತಿದ್ದುಪಡಿ ಅಗತ್ಯವಿದೆ');
  String get resolveCorrection => _t(en: 'Submit correction', hi: 'सुधार जमा करें', te: 'సవరణ సమర్పించండి', ta: 'திருத்தத்தை சமர்ப்பிக்கவும்', bn: 'সংশোধন জমা দিন', kn: 'ತಿದ್ದುಪಡಿ ಸಲ್ಲಿಸಿ');

  String get eligibility => _t(en: 'Eligibility', hi: 'पात्रता', te: 'అర్హత', ta: 'தகுதி', bn: 'যোগ্যতা', kn: 'ಅರ್ಹತೆ');
  String get eligible => _t(en: 'Eligible', hi: 'पात्र', te: 'అర్హులు', ta: 'தகுதியுடையவர்', bn: 'যোগ্য', kn: 'ಅರ್ಹರು');
  String get needsReview => _t(en: 'Needs review', hi: 'समीक्षा आवश्यक', te: 'సమీక్ష అవసరం', ta: 'மதிப்பாய்வு தேவை', bn: 'পর্যালোচনা প্রয়োজন', kn: 'ಪರಿಶೀಲನೆ ಅಗತ್ಯವಿದೆ');
  String get notEligible => _t(en: 'Not eligible', hi: 'अपात्र', te: 'అనర్హులు', ta: 'தகுதியற்றவர்', bn: 'অযোগ্য', kn: 'ಅನರ್ಹರು');

  String get notifications => _t(en: 'Notifications', hi: 'सूचनाएँ', te: 'నోటిఫికేషన్లు', ta: 'அறிவிப்புகள்', bn: 'বিজ্ঞপ্তি', kn: 'ಅಧಿಸೂಚನೆಗಳು');
  String get markAllRead => _t(en: 'Mark all read', hi: 'सभी पढ़ा हुआ चिह्नित करें', te: 'అన్నీ చదివినట్లు గుర్తించండి', ta: 'அனைத்தையும் படித்ததாகக் குறிக்கவும்', bn: 'সব পঠিত চিহ্নিত করুন', kn: 'ಎಲ್ಲವನ್ನೂ ಓದಿದಂತೆ ಗುರುತಿಸಿ');
  String get noNotifications => _t(en: 'No notifications yet', hi: 'अभी कोई सूचना नहीं', te: 'ఇంకా నోటిఫికేషన్లు లేవు', ta: 'அறிவிப்புகள் எதுவும் இல்லை', bn: 'এখনও কোনো বিজ্ঞপ্তি নেই', kn: 'ಯಾವುದೇ ಅಧಿಸೂಚನೆಗಳಿಲ್ಲ');

  String get consents => _t(en: 'Consents', hi: 'सहमति', te: 'సమ్మతులు', ta: 'ஒப்புதல்கள்', bn: 'সম্মতি', kn: 'ಸಮ್ಮತಿಗಳು');
  String get verification => _t(en: 'Verification', hi: 'सत्यापन', te: 'ధృవీకరణ', ta: 'சரிபார்ப்பு', bn: 'যাচাইকরণ', kn: 'ಪರಿಶೀಲನೆ');
  String get verifyNow => _t(en: 'Verify now', hi: 'अभी सत्यापित करें', te: 'ఇప్పుడే ధృవీకరించండి', ta: 'இப்போது சரிபார்க்கவும்', bn: 'এখনই যাচাই করুন', kn: 'ಈಗಲೇ ಪರಿಶೀಲಿಸಿ');
  String get language => _t(en: 'Language', hi: 'भाषा', te: 'భాష', ta: 'மொழி', bn: 'ভাষা', kn: 'ಭಾಷೆ');
  String get offline => _t(
        en: 'Offline — changes will sync automatically',
        hi: 'ऑफ़लाइन — बदलाव अपने आप सिंक होंगे',
        te: 'ఆఫ్‌లైన్ — మార్పులు ఆటోమేటిక్‌గా సింక్ అవుతాయి',
        ta: 'ஆஃப்லைன் — மாற்றங்கள் தானாக ஒத்திசைக்கப்படும்',
        bn: 'অফলাইন — পরিবর্তনগুলি স্বয়ংক্রিয়ভাবে সিঙ্ক হবে',
        kn: 'ಆಫ್‌ಲೈನ್ — ಬದಲಾವಣೆಗಳು ಸ್ವಯಂಚಾಲಿತವಾಗಿ ಸಿಂಕ್ ಆಗುತ್ತವೆ',
      );
  String get syncPending => _t(en: 'Waiting to sync', hi: 'सिंक होना बाकी है', te: 'సింక్ కావడానికి వేచి ఉంది', ta: 'ஒத்திசைக்க காத்திருக்கிறது', bn: 'সিঙ্কের জন্য অপেক্ষারত', kn: 'ಸಿಂಕ್ ಆಗಲು ಕಾಯುತ್ತಿದೆ');
  String get syncNow => _t(en: 'Sync now', hi: 'अभी सिंक करें', te: 'ఇప్పుడే సింక్ చేయండి', ta: 'இப்போது ஒத்திசைக்கவும்', bn: 'এখনই সিঙ্ক করুন', kn: 'ಈಗಲೇ ಸಿಂಕ್ ಮಾಡಿ');

  String get askJago => _t(en: 'Ask JAGO anything…', hi: 'JAGO से कुछ भी पूछें…', te: 'JAGO ని ఏదైనా అడగండి…', ta: 'JAGO விடம் எதையும் கேளுங்கள்…', bn: 'JAGO-কে কিছু জিজ্ঞাসা করুন…', kn: 'JAGO ಅನ್ನು ಏನನ್ನಾದರೂ ಕೇಳಿ…');

  // Admin section
  String get overview => _t(en: 'Overview', hi: 'अवलोकन', te: 'అవలోకనం', ta: 'மேலோட்டம்', bn: 'ওভারভিউ', kn: 'ಅವಲೋಕನ');
  String get applications => _t(en: 'Applications', hi: 'आवेदन', te: 'దరఖాస్తులు', ta: 'விண்ணப்பங்கள்', bn: 'আবেদনপত্র', kn: 'ಅರ್ಜಿಗಳು');
  String get exceptions => _t(en: 'Exceptions', hi: 'अपवाद', te: 'మినహాయింపులు', ta: 'விதிவிலக்குகள்', bn: 'ব্যতিক্রম', kn: 'ವಿನಾಯಿತಿಗಳು');
  String get coverageGap => _t(en: 'Coverage gap', hi: 'कवरेज अंतर', te: 'కవరేజ్ అంతరం', ta: 'கவரேஜ் இடைவெளி', bn: 'কভারেজ ব্যবধান', kn: 'ವ್ಯಾಪ್ತಿ ಅಂತರ');
  String get auditLog => _t(en: 'Audit log', hi: 'ऑडिट लॉग', te: 'ఆడిట్ లాగ్', ta: 'தணிக்கை பதிவு', bn: 'অডিট লগ', kn: 'ಆಡಿಟ್ ಲಾಗ್');

  static const Map<String, String> statusLabelsEn = {
    'DRAFT': 'Draft', 'SUBMITTED': 'Submitted', 'UNDER_VERIFICATION': 'Under verification',
    'DEFICIENCY': 'Correction needed', 'VERIFIED': 'Verified', 'SANCTIONED': 'Sanctioned',
    'DBT_PAID': 'Paid', 'REJECTED': 'Not approved',
  };
  static const Map<String, String> statusLabelsHi = {
    'DRAFT': 'ड्राफ्ट', 'SUBMITTED': 'जमा हुआ', 'UNDER_VERIFICATION': 'सत्यापन में',
    'DEFICIENCY': 'सुधार आवश्यक', 'VERIFIED': 'सत्यापित', 'SANCTIONED': 'स्वीकृत',
    'DBT_PAID': 'भुगतान हुआ', 'REJECTED': 'स्वीकृत नहीं',
  };
  static const Map<String, String> statusLabelsTe = {
    'DRAFT': 'డ్రాఫ్ట్', 'SUBMITTED': 'సమర్పించబడింది', 'UNDER_VERIFICATION': 'ధృవీకరణలో ఉంది',
    'DEFICIENCY': 'సవరణ అవసరం', 'VERIFIED': 'ధృవీకరించబడింది', 'SANCTIONED': 'మంజూరు చేయబడింది',
    'DBT_PAID': 'చెల్లించబడింది', 'REJECTED': 'ఆమోదించబడలేదు',
  };
  static const Map<String, String> statusLabelsTa = {
    'DRAFT': 'வரைவு', 'SUBMITTED': 'சமர்ப்பிக்கப்பட்டது', 'UNDER_VERIFICATION': 'சரிபார்ப்பில் உள்ளது',
    'DEFICIENCY': 'திருத்தம் தேவை', 'VERIFIED': 'சரிபார்க்கப்பட்டது', 'SANCTIONED': 'அனுமதிக்கப்பட்டது',
    'DBT_PAID': 'செலுத்தப்பட்டது', 'REJECTED': 'நிராகரிக்கப்பட்டது',
  };
  static const Map<String, String> statusLabelsBn = {
    'DRAFT': 'খসড়া', 'SUBMITTED': 'জমা দেওয়া হয়েছে', 'UNDER_VERIFICATION': 'যাচাইাধীন',
    'DEFICIENCY': 'সংশোধন প্রয়োজন', 'VERIFIED': 'যাচাইকৃত', 'SANCTIONED': 'অনুমোদিত',
    'DBT_PAID': 'পরিশোধিত', 'REJECTED': 'অননুমোদিত',
  };
  static const Map<String, String> statusLabelsKn = {
    'DRAFT': 'ಕರಡು', 'SUBMITTED': 'ಸಲ್ಲಿಸಲಾಗಿದೆ', 'UNDER_VERIFICATION': 'ಪರಿಶೀಲನೆಯಲ್ಲಿದೆ',
    'DEFICIENCY': 'ತಿದ್ದುಪಡಿ ಅಗತ್ಯವಿದೆ', 'VERIFIED': 'ಪರಿಶೀಲಿಸಲಾಗಿದೆ', 'SANCTIONED': 'ಮಂಜೂರಾಗಿದೆ',
    'DBT_PAID': 'ಪಾವತಿಸಲಾಗಿದೆ', 'REJECTED': 'ತಿರಸ್ಕರಿಸಲಾಗಿದೆ',
  };

  String statusLabel(String status) {
    switch (lang) {
      case 'hi':
        return statusLabelsHi[status] ?? statusLabelsEn[status] ?? status;
      case 'te':
        return statusLabelsTe[status] ?? statusLabelsEn[status] ?? status;
      case 'ta':
        return statusLabelsTa[status] ?? statusLabelsEn[status] ?? status;
      case 'bn':
        return statusLabelsBn[status] ?? statusLabelsEn[status] ?? status;
      case 'kn':
        return statusLabelsKn[status] ?? statusLabelsEn[status] ?? status;
      default:
        return statusLabelsEn[status] ?? status;
    }
  }

  static const Map<String, String> stageLabelsEn = {
    'APPLICATION': 'Application', 'VERIFICATION': 'Verification', 'DEFICIENCY': 'Correction',
    'SANCTION': 'Sanction', 'DBT': 'Payment',
  };
  static const Map<String, String> stageLabelsHi = {
    'APPLICATION': 'आवेदन', 'VERIFICATION': 'सत्यापन', 'DEFICIENCY': 'सुधार',
    'SANCTION': 'स्वीकृति', 'DBT': 'भुगतान',
  };
  static const Map<String, String> stageLabelsTe = {
    'APPLICATION': 'దరఖాస్తు', 'VERIFICATION': 'ధృవీకరణ', 'DEFICIENCY': 'సవరణ',
    'SANCTION': 'మంజూరు', 'DBT': 'చెల్లింపు',
  };
  static const Map<String, String> stageLabelsTa = {
    'APPLICATION': 'விண்ணப்பம்', 'VERIFICATION': 'சரிபார்ப்பு', 'DEFICIENCY': 'திருத்தம்',
    'SANCTION': 'ஒப்புதல்', 'DBT': 'பணம் செலுத்துதல்',
  };
  static const Map<String, String> stageLabelsBn = {
    'APPLICATION': 'আবেদন', 'VERIFICATION': 'যাচাইকরণ', 'DEFICIENCY': 'সংশোধন',
    'SANCTION': 'অনুমোদন', 'DBT': 'পেমেন্ট',
  };
  static const Map<String, String> stageLabelsKn = {
    'APPLICATION': 'ಅರ್ಜಿ', 'VERIFICATION': 'ಪರಿಶೀಲನೆ', 'DEFICIENCY': 'ತಿದ್ದುಪಡಿ',
    'SANCTION': 'ಮಂಜೂರಾತಿ', 'DBT': 'ಪಾವತಿ',
  };

  String stageLabel(String stage) {
    switch (lang) {
      case 'hi':
        return stageLabelsHi[stage] ?? stageLabelsEn[stage] ?? stage;
      case 'te':
        return stageLabelsTe[stage] ?? stageLabelsEn[stage] ?? stage;
      case 'ta':
        return stageLabelsTa[stage] ?? stageLabelsEn[stage] ?? stage;
      case 'bn':
        return stageLabelsBn[stage] ?? stageLabelsEn[stage] ?? stage;
      case 'kn':
        return stageLabelsKn[stage] ?? stageLabelsEn[stage] ?? stage;
      default:
        return stageLabelsEn[stage] ?? stage;
    }
  }
}

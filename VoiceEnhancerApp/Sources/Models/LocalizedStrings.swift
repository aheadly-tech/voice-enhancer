import Foundation

enum LocalizedStrings {
    enum Key: String {
        case appName
        case openApp
        case turnProcessingOff
        case turnProcessingOn
        case restartAudioEngine
        case quit
        case settings
        case done
        case language
        case languageDescription
        case launchAtLogin
        case launchAtLoginDescription
        case preset
        case levels
        case enhancementOn
        case enhancementBypassed
        case virtualDriverMissingFooter
        case input
        case output
        case comp
        case deess
        case idle
        case starting
        case running
        case errorPrefix
        case naturalName
        case broadcastName
        case clarityName
        case warmName
        case customName
        case naturalBlurb
        case broadcastBlurb
        case clarityBlurb
        case warmBlurb
        case customBlurb
        case inputDevice
        case microphone
        case systemDefault
        case inputDeviceDescription
        case reconnectMicrophone
        case voiceTuning
        case previewDescription
        case voiceLeveling
        case more
        case less
        case voiceLevelingDescription
        case sibilanceReduction
        case sibilanceDescription
        case virtualDriver
        case installedAndConnected
        case notConnected
        case driverConnectedDescription
        case driverMissingDescription
        case about
        case openSourceLicensed
        case speakNow
        case play
        case rerecord
        case previewPlaying
        case stop
        case recordTest
    }

    static func text(_ key: Key, language: AppLanguage) -> String {
        table[language]?[key] ?? table[.english]?[key] ?? key.rawValue
    }

    static func text(_ key: Key, language: AppLanguage, _ values: CVarArg...) -> String {
        String(format: text(key, language: language), locale: Locale(identifier: language.rawValue), arguments: values)
    }

    static func text(_ key: Key, language: AppLanguage, arguments: [CVarArg]) -> String {
        String(format: text(key, language: language), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    private static let table: [AppLanguage: [Key: String]] = [
        .english: [
            .appName: "Voice Enhancer",
            .openApp: "Open Voice Enhancer",
            .turnProcessingOff: "Turn Processing Off",
            .turnProcessingOn: "Turn Processing On",
            .restartAudioEngine: "Restart Audio Engine",
            .quit: "Quit",
            .settings: "Settings",
            .done: "Done",
            .language: "Language",
            .languageDescription: "Choose the app language. The setting is saved on this Mac.",
            .launchAtLogin: "Launch at login",
            .launchAtLoginDescription: "Start Voice Enhancer automatically when you sign in to this Mac.",
            .preset: "Preset",
            .levels: "Levels",
            .enhancementOn: "Enhancement on",
            .enhancementBypassed: "Enhancement bypassed",
            .virtualDriverMissingFooter: "Virtual driver not installed. Run scripts/install.sh to route audio to other apps.",
            .input: "Input",
            .output: "Output",
            .comp: "Comp",
            .deess: "De-ess",
            .idle: "Idle",
            .starting: "Starting...",
            .running: "Running",
            .errorPrefix: "Error: %@",
            .naturalName: "Natural",
            .broadcastName: "Broadcast",
            .clarityName: "Clarity",
            .warmName: "Warm",
            .customName: "Custom",
            .naturalBlurb: "Gentle cleanup. Most transparent.",
            .broadcastBlurb: "Radio DJ voice. Bold and clear.",
            .clarityBlurb: "Cuts through. Great for quiet mics.",
            .warmBlurb: "Softens harsh mics. Adds body.",
            .customBlurb: "Your saved tuning.",
            .inputDevice: "Input device",
            .microphone: "Microphone",
            .systemDefault: "System Default",
            .inputDeviceDescription: "Voice Enhancer reads from this microphone and publishes the enhanced signal to the virtual input device.",
            .reconnectMicrophone: "Reconnect Microphone",
            .voiceTuning: "Voice tuning",
            .previewDescription: "Record your voice, then adjust sliders to hear changes live.",
            .voiceLeveling: "Voice Leveling",
            .more: "More",
            .less: "Less",
            .voiceLevelingDescription: "Evens out volume differences. Lower values smooth more.",
            .sibilanceReduction: "Sibilance Reduction",
            .sibilanceDescription: "Reduces harsh \"s\" and \"sh\" sounds.",
            .virtualDriver: "Virtual driver",
            .installedAndConnected: "Installed and connected",
            .notConnected: "Not connected",
            .driverConnectedDescription: "Select “Voice Enhancer” as the microphone in your meeting app.",
            .driverMissingDescription: "Install the HAL driver with scripts/install.sh to route processed audio to other apps.",
            .about: "About",
            .openSourceLicensed: "Open source. MIT licensed.",
            .speakNow: "Speak now... %ds",
            .play: "Play",
            .rerecord: "Re-record",
            .previewPlaying: "Preview playing",
            .stop: "Stop",
            .recordTest: "Record Test"
        ],
        .chineseSimplified: [
            .appName: "Voice Enhancer", .openApp: "打开 Voice Enhancer", .turnProcessingOff: "关闭处理", .turnProcessingOn: "开启处理", .restartAudioEngine: "重启音频引擎", .quit: "退出", .settings: "设置", .done: "完成", .language: "语言", .languageDescription: "选择应用语言。该设置会保存在这台 Mac 上。", .launchAtLogin: "登录时启动", .launchAtLoginDescription: "登录这台 Mac 时自动启动 Voice Enhancer。", .preset: "预设", .levels: "电平", .enhancementOn: "增强已开启", .enhancementBypassed: "增强已旁路", .virtualDriverMissingFooter: "未安装虚拟驱动。运行 scripts/install.sh 以将音频路由到其他应用。", .input: "输入", .output: "输出", .comp: "压缩", .deess: "去齿音", .idle: "空闲", .starting: "正在启动...", .running: "运行中", .errorPrefix: "错误：%@", .naturalName: "自然", .broadcastName: "广播", .clarityName: "清晰", .warmName: "温暖", .customName: "自定义", .naturalBlurb: "轻度清理，最自然。", .broadcastBlurb: "电台人声，饱满清晰。", .clarityBlurb: "更突出，适合小声麦克风。", .warmBlurb: "柔化刺耳感，增加厚度。", .customBlurb: "已保存的调音。", .inputDevice: "输入设备", .microphone: "麦克风", .systemDefault: "系统默认", .inputDeviceDescription: "Voice Enhancer 从此麦克风读取声音，并将增强后的信号发布到虚拟输入设备。", .reconnectMicrophone: "重新连接麦克风", .voiceTuning: "声音调节", .previewDescription: "录制你的声音，然后调整滑块实时试听变化。", .voiceLeveling: "音量均衡", .more: "更多", .less: "更少", .voiceLevelingDescription: "均衡音量差异。数值越低，平滑越多。", .sibilanceReduction: "齿音降低", .sibilanceDescription: "减少刺耳的 “s” 和 “sh” 声。", .virtualDriver: "虚拟驱动", .installedAndConnected: "已安装并连接", .notConnected: "未连接", .driverConnectedDescription: "在会议应用中选择 “Voice Enhancer” 作为麦克风。", .driverMissingDescription: "使用 scripts/install.sh 安装 HAL 驱动，将处理后的音频路由到其他应用。", .about: "关于", .openSourceLicensed: "开源。MIT 许可。", .speakNow: "请说话... %d秒", .play: "播放", .rerecord: "重新录制", .previewPlaying: "正在播放预览", .stop: "停止", .recordTest: "录制测试"
        ],
        .hindi: [
            .appName: "Voice Enhancer", .openApp: "Voice Enhancer खोलें", .turnProcessingOff: "प्रोसेसिंग बंद करें", .turnProcessingOn: "प्रोसेसिंग चालू करें", .restartAudioEngine: "ऑडियो इंजन रीस्टार्ट करें", .quit: "बंद करें", .settings: "सेटिंग्स", .done: "हो गया", .language: "भाषा", .languageDescription: "ऐप की भाषा चुनें। यह सेटिंग इस Mac पर सेव रहती है।", .preset: "प्रीसेट", .levels: "लेवल", .enhancementOn: "एन्हांसमेंट चालू", .enhancementBypassed: "एन्हांसमेंट बायपास", .virtualDriverMissingFooter: "वर्चुअल ड्राइवर इंस्टॉल नहीं है। ऑडियो को दूसरे ऐप्स तक भेजने के लिए scripts/install.sh चलाएँ।", .input: "इनपुट", .output: "आउटपुट", .comp: "कम्प", .deess: "डी-एस", .idle: "निष्क्रिय", .starting: "शुरू हो रहा है...", .running: "चल रहा है", .errorPrefix: "त्रुटि: %@", .naturalName: "नेचुरल", .broadcastName: "ब्रॉडकास्ट", .clarityName: "क्लैरिटी", .warmName: "वॉर्म", .customName: "कस्टम", .naturalBlurb: "हल्की सफाई, सबसे प्राकृतिक।", .broadcastBlurb: "रेडियो जैसी आवाज, बोल्ड और साफ।", .clarityBlurb: "आवाज को आगे लाता है। शांत माइक के लिए अच्छा।", .warmBlurb: "कठोर माइक को मुलायम करता है, बॉडी जोड़ता है।", .customBlurb: "आपकी सेव की हुई ट्यूनिंग।", .inputDevice: "इनपुट डिवाइस", .microphone: "माइक्रोफोन", .systemDefault: "सिस्टम डिफॉल्ट", .inputDeviceDescription: "Voice Enhancer इस माइक्रोफोन से आवाज पढ़ता है और सुधरा हुआ सिग्नल वर्चुअल इनपुट डिवाइस पर भेजता है।", .reconnectMicrophone: "माइक्रोफोन फिर से कनेक्ट करें", .voiceTuning: "वॉइस ट्यूनिंग", .previewDescription: "अपनी आवाज रिकॉर्ड करें, फिर बदलाव सुनने के लिए स्लाइडर बदलें।", .voiceLeveling: "वॉइस लेवलिंग", .more: "ज्यादा", .less: "कम", .voiceLevelingDescription: "वॉल्यूम के फर्क को बराबर करता है। कम वैल्यू ज्यादा स्मूद करती है।", .sibilanceReduction: "सिबिलेंस रिडक्शन", .sibilanceDescription: "कठोर “s” और “sh” आवाजों को कम करता है।", .virtualDriver: "वर्चुअल ड्राइवर", .installedAndConnected: "इंस्टॉल और कनेक्टेड", .notConnected: "कनेक्टेड नहीं", .driverConnectedDescription: "मीटिंग ऐप में माइक्रोफोन के रूप में “Voice Enhancer” चुनें।", .driverMissingDescription: "प्रोसेस्ड ऑडियो को दूसरे ऐप्स तक भेजने के लिए scripts/install.sh से HAL ड्राइवर इंस्टॉल करें।", .about: "बारे में", .openSourceLicensed: "ओपन सोर्स। MIT लाइसेंस।", .speakNow: "अब बोलें... %d सेकंड", .play: "चलाएँ", .rerecord: "फिर रिकॉर्ड करें", .previewPlaying: "प्रीव्यू चल रहा है", .stop: "रोकें", .recordTest: "टेस्ट रिकॉर्ड करें"
        ],
        .spanish: [
            .appName: "Voice Enhancer", .openApp: "Abrir Voice Enhancer", .turnProcessingOff: "Desactivar procesamiento", .turnProcessingOn: "Activar procesamiento", .restartAudioEngine: "Reiniciar motor de audio", .quit: "Salir", .settings: "Ajustes", .done: "Listo", .language: "Idioma", .languageDescription: "Elige el idioma de la app. El ajuste se guarda en este Mac.", .preset: "Preset", .levels: "Niveles", .enhancementOn: "Mejora activada", .enhancementBypassed: "Mejora omitida", .virtualDriverMissingFooter: "El driver virtual no está instalado. Ejecuta scripts/install.sh para enrutar audio a otras apps.", .input: "Entrada", .output: "Salida", .comp: "Comp", .deess: "De-ess", .idle: "Inactivo", .starting: "Iniciando...", .running: "En ejecución", .errorPrefix: "Error: %@", .naturalName: "Natural", .broadcastName: "Broadcast", .clarityName: "Claridad", .warmName: "Cálido", .customName: "Personalizado", .naturalBlurb: "Limpieza suave, muy transparente.", .broadcastBlurb: "Voz de radio, potente y clara.", .clarityBlurb: "Destaca la voz. Ideal para micros bajos.", .warmBlurb: "Suaviza micros duros y añade cuerpo.", .customBlurb: "Tu ajuste guardado.", .inputDevice: "Dispositivo de entrada", .microphone: "Micrófono", .systemDefault: "Predeterminado del sistema", .inputDeviceDescription: "Voice Enhancer lee este micrófono y publica la señal mejorada en el dispositivo de entrada virtual.", .reconnectMicrophone: "Reconectar micrófono", .voiceTuning: "Ajuste de voz", .previewDescription: "Graba tu voz y ajusta los controles para escuchar los cambios en vivo.", .voiceLeveling: "Nivelación de voz", .more: "Más", .less: "Menos", .voiceLevelingDescription: "Iguala diferencias de volumen. Valores más bajos suavizan más.", .sibilanceReduction: "Reducción de sibilancia", .sibilanceDescription: "Reduce sonidos fuertes de “s” y “sh”.", .virtualDriver: "Driver virtual", .installedAndConnected: "Instalado y conectado", .notConnected: "No conectado", .driverConnectedDescription: "Selecciona “Voice Enhancer” como micrófono en tu app de reuniones.", .driverMissingDescription: "Instala el driver HAL con scripts/install.sh para enrutar audio procesado a otras apps.", .about: "Acerca de", .openSourceLicensed: "Open source. Licencia MIT.", .speakNow: "Habla ahora... %ds", .play: "Reproducir", .rerecord: "Grabar de nuevo", .previewPlaying: "Reproduciendo preview", .stop: "Detener", .recordTest: "Grabar prueba"
        ],
        .arabic: [
            .appName: "Voice Enhancer", .openApp: "فتح Voice Enhancer", .turnProcessingOff: "إيقاف المعالجة", .turnProcessingOn: "تشغيل المعالجة", .restartAudioEngine: "إعادة تشغيل محرك الصوت", .quit: "إنهاء", .settings: "الإعدادات", .done: "تم", .language: "اللغة", .languageDescription: "اختر لغة التطبيق. سيتم حفظ الإعداد على هذا الـ Mac.", .preset: "النمط", .levels: "المستويات", .enhancementOn: "التحسين مفعل", .enhancementBypassed: "التحسين متجاوز", .virtualDriverMissingFooter: "برنامج التشغيل الافتراضي غير مثبت. شغّل scripts/install.sh لتوجيه الصوت إلى التطبيقات الأخرى.", .input: "الإدخال", .output: "الإخراج", .comp: "الضغط", .deess: "إزالة الصفير", .idle: "خامل", .starting: "جارٍ البدء...", .running: "يعمل", .errorPrefix: "خطأ: %@", .naturalName: "طبيعي", .broadcastName: "بث", .clarityName: "وضوح", .warmName: "دافئ", .customName: "مخصص", .naturalBlurb: "تنظيف خفيف وشفاف.", .broadcastBlurb: "صوت إذاعي واضح وقوي.", .clarityBlurb: "يبرز الصوت. مناسب للميكروفونات الهادئة.", .warmBlurb: "يلطف الحدة ويضيف عمقاً.", .customBlurb: "إعداداتك المحفوظة.", .inputDevice: "جهاز الإدخال", .microphone: "الميكروفون", .systemDefault: "افتراضي النظام", .inputDeviceDescription: "يقرأ Voice Enhancer من هذا الميكروفون ويرسل الإشارة المحسنة إلى جهاز الإدخال الافتراضي.", .reconnectMicrophone: "إعادة توصيل الميكروفون", .voiceTuning: "ضبط الصوت", .previewDescription: "سجّل صوتك ثم عدّل أشرطة التمرير لسماع التغييرات مباشرة.", .voiceLeveling: "تسوية الصوت", .more: "أكثر", .less: "أقل", .voiceLevelingDescription: "يوحّد اختلافات مستوى الصوت. القيم الأقل تعطي نعومة أكثر.", .sibilanceReduction: "تقليل الصفير", .sibilanceDescription: "يقلل أصوات “s” و “sh” الحادة.", .virtualDriver: "برنامج التشغيل الافتراضي", .installedAndConnected: "مثبت ومتصل", .notConnected: "غير متصل", .driverConnectedDescription: "اختر “Voice Enhancer” كميكروفون في تطبيق الاجتماعات.", .driverMissingDescription: "ثبّت برنامج HAL عبر scripts/install.sh لتوجيه الصوت المعالج إلى التطبيقات الأخرى.", .about: "حول", .openSourceLicensed: "مفتوح المصدر. ترخيص MIT.", .speakNow: "تحدث الآن... %dث", .play: "تشغيل", .rerecord: "إعادة التسجيل", .previewPlaying: "تشغيل المعاينة", .stop: "إيقاف", .recordTest: "تسجيل اختبار"
        ],
        .french: [
            .appName: "Voice Enhancer", .openApp: "Ouvrir Voice Enhancer", .turnProcessingOff: "Désactiver le traitement", .turnProcessingOn: "Activer le traitement", .restartAudioEngine: "Redémarrer le moteur audio", .quit: "Quitter", .settings: "Réglages", .done: "Terminé", .language: "Langue", .languageDescription: "Choisissez la langue de l’app. Le réglage est enregistré sur ce Mac.", .preset: "Préréglage", .levels: "Niveaux", .enhancementOn: "Amélioration activée", .enhancementBypassed: "Amélioration contournée", .virtualDriverMissingFooter: "Pilote virtuel non installé. Exécutez scripts/install.sh pour router l’audio vers d’autres apps.", .input: "Entrée", .output: "Sortie", .comp: "Comp", .deess: "De-ess", .idle: "Inactif", .starting: "Démarrage...", .running: "En cours", .errorPrefix: "Erreur : %@", .naturalName: "Naturel", .broadcastName: "Broadcast", .clarityName: "Clarté", .warmName: "Chaud", .customName: "Personnalisé", .naturalBlurb: "Nettoyage léger, très transparent.", .broadcastBlurb: "Voix radio, ample et claire.", .clarityBlurb: "Met la voix en avant. Idéal pour micros faibles.", .warmBlurb: "Adoucit les micros durs et ajoute du corps.", .customBlurb: "Vos réglages enregistrés.", .inputDevice: "Périphérique d’entrée", .microphone: "Microphone", .systemDefault: "Par défaut du système", .inputDeviceDescription: "Voice Enhancer lit ce microphone et publie le signal amélioré vers le périphérique d’entrée virtuel.", .reconnectMicrophone: "Reconnecter le microphone", .voiceTuning: "Réglage de la voix", .previewDescription: "Enregistrez votre voix, puis ajustez les curseurs pour entendre les changements en direct.", .voiceLeveling: "Nivellement de voix", .more: "Plus", .less: "Moins", .voiceLevelingDescription: "Égalise les différences de volume. Les valeurs plus basses lissent davantage.", .sibilanceReduction: "Réduction des sifflantes", .sibilanceDescription: "Réduit les sons “s” et “sh” agressifs.", .virtualDriver: "Pilote virtuel", .installedAndConnected: "Installé et connecté", .notConnected: "Non connecté", .driverConnectedDescription: "Sélectionnez “Voice Enhancer” comme microphone dans votre app de réunion.", .driverMissingDescription: "Installez le pilote HAL avec scripts/install.sh pour router l’audio traité vers d’autres apps.", .about: "À propos", .openSourceLicensed: "Open source. Licence MIT.", .speakNow: "Parlez maintenant... %ds", .play: "Lire", .rerecord: "Réenregistrer", .previewPlaying: "Aperçu en lecture", .stop: "Arrêter", .recordTest: "Enregistrer un test"
        ],
        .bengali: [
            .appName: "Voice Enhancer", .openApp: "Voice Enhancer খুলুন", .turnProcessingOff: "প্রসেসিং বন্ধ করুন", .turnProcessingOn: "প্রসেসিং চালু করুন", .restartAudioEngine: "অডিও ইঞ্জিন রিস্টার্ট করুন", .quit: "বন্ধ করুন", .settings: "সেটিংস", .done: "সম্পন্ন", .language: "ভাষা", .languageDescription: "অ্যাপের ভাষা নির্বাচন করুন। সেটিংটি এই Mac-এ সংরক্ষিত থাকবে।", .preset: "প্রিসেট", .levels: "লেভেল", .enhancementOn: "এনহ্যান্সমেন্ট চালু", .enhancementBypassed: "এনহ্যান্সমেন্ট বাইপাস", .virtualDriverMissingFooter: "ভার্চুয়াল ড্রাইভার ইনস্টল নেই। অডিও অন্য অ্যাপে পাঠাতে scripts/install.sh চালান।", .input: "ইনপুট", .output: "আউটপুট", .comp: "কম্প", .deess: "ডি-এস", .idle: "নিষ্ক্রিয়", .starting: "শুরু হচ্ছে...", .running: "চলছে", .errorPrefix: "ত্রুটি: %@", .naturalName: "ন্যাচারাল", .broadcastName: "ব্রডকাস্ট", .clarityName: "ক্ল্যারিটি", .warmName: "ওয়ার্ম", .customName: "কাস্টম", .naturalBlurb: "হালকা পরিষ্কার, সবচেয়ে স্বচ্ছ।", .broadcastBlurb: "রেডিও ভয়েস, শক্তিশালী ও পরিষ্কার।", .clarityBlurb: "ভয়েস সামনে আনে। শান্ত মাইকের জন্য ভালো।", .warmBlurb: "কঠিন মাইক নরম করে, গভীরতা যোগ করে।", .customBlurb: "আপনার সংরক্ষিত টিউনিং।", .inputDevice: "ইনপুট ডিভাইস", .microphone: "মাইক্রোফোন", .systemDefault: "সিস্টেম ডিফল্ট", .inputDeviceDescription: "Voice Enhancer এই মাইক্রোফোন থেকে শব্দ পড়ে এবং উন্নত সিগন্যাল ভার্চুয়াল ইনপুট ডিভাইসে পাঠায়।", .reconnectMicrophone: "মাইক্রোফোন পুনরায় সংযোগ করুন", .voiceTuning: "ভয়েস টিউনিং", .previewDescription: "আপনার ভয়েস রেকর্ড করুন, তারপর পরিবর্তন শুনতে স্লাইডার সামঞ্জস্য করুন।", .voiceLeveling: "ভয়েস লেভেলিং", .more: "বেশি", .less: "কম", .voiceLevelingDescription: "ভলিউমের পার্থক্য সমান করে। কম মান বেশি স্মুথ করে।", .sibilanceReduction: "সিবিল্যান্স কমানো", .sibilanceDescription: "কঠিন “s” এবং “sh” শব্দ কমায়।", .virtualDriver: "ভার্চুয়াল ড্রাইভার", .installedAndConnected: "ইনস্টল ও সংযুক্ত", .notConnected: "সংযুক্ত নয়", .driverConnectedDescription: "মিটিং অ্যাপে মাইক্রোফোন হিসেবে “Voice Enhancer” নির্বাচন করুন।", .driverMissingDescription: "প্রসেসড অডিও অন্য অ্যাপে পাঠাতে scripts/install.sh দিয়ে HAL ড্রাইভার ইনস্টল করুন।", .about: "সম্পর্কে", .openSourceLicensed: "ওপেন সোর্স। MIT লাইসেন্স।", .speakNow: "এখন বলুন... %dসেকেন্ড", .play: "চালান", .rerecord: "আবার রেকর্ড", .previewPlaying: "প্রিভিউ চলছে", .stop: "থামান", .recordTest: "টেস্ট রেকর্ড"
        ],
        .portuguese: [
            .appName: "Voice Enhancer", .openApp: "Abrir Voice Enhancer", .turnProcessingOff: "Desativar processamento", .turnProcessingOn: "Ativar processamento", .restartAudioEngine: "Reiniciar motor de áudio", .quit: "Sair", .settings: "Ajustes", .done: "Concluir", .language: "Idioma", .languageDescription: "Escolha o idioma do app. A configuração fica salva neste Mac.", .preset: "Preset", .levels: "Níveis", .enhancementOn: "Melhoria ativada", .enhancementBypassed: "Melhoria ignorada", .virtualDriverMissingFooter: "Driver virtual não instalado. Execute scripts/install.sh para rotear áudio para outros apps.", .input: "Entrada", .output: "Saída", .comp: "Comp", .deess: "De-ess", .idle: "Ocioso", .starting: "Iniciando...", .running: "Em execução", .errorPrefix: "Erro: %@", .naturalName: "Natural", .broadcastName: "Broadcast", .clarityName: "Clareza", .warmName: "Quente", .customName: "Personalizado", .naturalBlurb: "Limpeza leve, mais transparente.", .broadcastBlurb: "Voz de rádio, forte e clara.", .clarityBlurb: "Destaca a voz. Ótimo para microfones baixos.", .warmBlurb: "Suaviza microfones ásperos e adiciona corpo.", .customBlurb: "Sua regulagem salva.", .inputDevice: "Dispositivo de entrada", .microphone: "Microfone", .systemDefault: "Padrão do sistema", .inputDeviceDescription: "Voice Enhancer lê este microfone e publica o sinal melhorado no dispositivo virtual de entrada.", .reconnectMicrophone: "Reconectar microfone", .voiceTuning: "Ajuste de voz", .previewDescription: "Grave sua voz e ajuste os controles para ouvir as mudanças ao vivo.", .voiceLeveling: "Nivelamento de voz", .more: "Mais", .less: "Menos", .voiceLevelingDescription: "Equilibra diferenças de volume. Valores menores suavizam mais.", .sibilanceReduction: "Redução de sibilância", .sibilanceDescription: "Reduz sons fortes de “s” e “sh”.", .virtualDriver: "Driver virtual", .installedAndConnected: "Instalado e conectado", .notConnected: "Não conectado", .driverConnectedDescription: "Selecione “Voice Enhancer” como microfone no app de reunião.", .driverMissingDescription: "Instale o driver HAL com scripts/install.sh para rotear áudio processado para outros apps.", .about: "Sobre", .openSourceLicensed: "Open source. Licença MIT.", .speakNow: "Fale agora... %ds", .play: "Reproduzir", .rerecord: "Gravar de novo", .previewPlaying: "Prévia tocando", .stop: "Parar", .recordTest: "Gravar teste"
        ],
        .russian: [
            .appName: "Voice Enhancer", .openApp: "Открыть Voice Enhancer", .turnProcessingOff: "Выключить обработку", .turnProcessingOn: "Включить обработку", .restartAudioEngine: "Перезапустить аудиодвижок", .quit: "Выйти", .settings: "Настройки", .done: "Готово", .language: "Язык", .languageDescription: "Выберите язык приложения. Настройка сохранится на этом Mac.", .launchAtLogin: "Запускать при входе", .launchAtLoginDescription: "Автоматически запускать Voice Enhancer при входе в эту учётную запись macOS.", .preset: "Режим", .levels: "Уровни", .enhancementOn: "Обработка включена", .enhancementBypassed: "Обработка выключена", .virtualDriverMissingFooter: "Виртуальный драйвер не установлен. Запустите scripts/install.sh, чтобы передавать звук в другие приложения.", .input: "Вход", .output: "Выход", .comp: "Компр.", .deess: "Шип.", .idle: "Ожидание", .starting: "Запуск...", .running: "Работает", .errorPrefix: "Ошибка: %@", .naturalName: "Natural", .broadcastName: "Broadcast", .clarityName: "Clarity", .warmName: "Warm", .customName: "Custom", .naturalBlurb: "Мягкая очистка, максимально естественно.", .broadcastBlurb: "Радиоголос, плотно и ясно.", .clarityBlurb: "Выводит голос вперёд. Хорошо для тихих микрофонов.", .warmBlurb: "Смягчает резкость и добавляет плотность.", .customBlurb: "Ваши сохранённые настройки.", .inputDevice: "Устройство ввода", .microphone: "Микрофон", .systemDefault: "Системный по умолчанию", .inputDeviceDescription: "Voice Enhancer читает звук с этого микрофона и публикует обработанный сигнал в виртуальное устройство ввода.", .reconnectMicrophone: "Переподключить микрофон", .voiceTuning: "Настройка голоса", .previewDescription: "Запишите голос, затем двигайте слайдеры и слушайте изменения сразу.", .voiceLeveling: "Выравнивание голоса", .more: "Больше", .less: "Меньше", .voiceLevelingDescription: "Сглаживает перепады громкости. Чем ниже значение, тем сильнее сглаживание.", .sibilanceReduction: "Снижение шипящих", .sibilanceDescription: "Уменьшает резкие звуки «с», «ш» и свист на голосе.", .virtualDriver: "Виртуальный драйвер", .installedAndConnected: "Установлен и подключён", .notConnected: "Не подключён", .driverConnectedDescription: "Выберите “Voice Enhancer” как микрофон в приложении для звонков.", .driverMissingDescription: "Установите HAL-драйвер через scripts/install.sh, чтобы отправлять обработанный звук в другие приложения.", .about: "О приложении", .openSourceLicensed: "Открытый исходный код. Лицензия MIT.", .speakNow: "Говорите... %dс", .play: "Прослушать", .rerecord: "Записать снова", .previewPlaying: "Идёт прослушивание", .stop: "Стоп", .recordTest: "Записать тест"
        ],
        .japanese: [
            .appName: "Voice Enhancer", .openApp: "Voice Enhancer を開く", .turnProcessingOff: "処理をオフ", .turnProcessingOn: "処理をオン", .restartAudioEngine: "オーディオエンジンを再起動", .quit: "終了", .settings: "設定", .done: "完了", .language: "言語", .languageDescription: "アプリの言語を選択します。この設定はこの Mac に保存されます。", .preset: "プリセット", .levels: "レベル", .enhancementOn: "補正オン", .enhancementBypassed: "補正バイパス", .virtualDriverMissingFooter: "仮想ドライバーがインストールされていません。scripts/install.sh を実行して他のアプリへ音声をルーティングしてください。", .input: "入力", .output: "出力", .comp: "Comp", .deess: "De-ess", .idle: "待機中", .starting: "起動中...", .running: "動作中", .errorPrefix: "エラー: %@", .naturalName: "Natural", .broadcastName: "Broadcast", .clarityName: "Clarity", .warmName: "Warm", .customName: "Custom", .naturalBlurb: "自然で軽いクリーンアップ。", .broadcastBlurb: "ラジオ風の太く明瞭な声。", .clarityBlurb: "声を前に出します。小さいマイクに最適。", .warmBlurb: "硬さを和らげ、厚みを加えます。", .customBlurb: "保存した調整。", .inputDevice: "入力デバイス", .microphone: "マイク", .systemDefault: "システムデフォルト", .inputDeviceDescription: "Voice Enhancer はこのマイクから音声を読み取り、補正済み信号を仮想入力デバイスへ出力します。", .reconnectMicrophone: "マイクを再接続", .voiceTuning: "ボイス調整", .previewDescription: "声を録音し、スライダーを調整して変化をリアルタイムで確認します。", .voiceLeveling: "音量レベリング", .more: "強く", .less: "弱く", .voiceLevelingDescription: "音量差を整えます。値を下げるほど滑らかになります。", .sibilanceReduction: "歯擦音の低減", .sibilanceDescription: "強い “s” や “sh” の音を抑えます。", .virtualDriver: "仮想ドライバー", .installedAndConnected: "インストール済み・接続中", .notConnected: "未接続", .driverConnectedDescription: "会議アプリでマイクとして “Voice Enhancer” を選択してください。", .driverMissingDescription: "処理済み音声を他のアプリへ送るには scripts/install.sh で HAL ドライバーをインストールしてください。", .about: "情報", .openSourceLicensed: "オープンソース。MIT ライセンス。", .speakNow: "話してください... %d秒", .play: "再生", .rerecord: "再録音", .previewPlaying: "プレビュー再生中", .stop: "停止", .recordTest: "テスト録音"
        ]
    ]
}

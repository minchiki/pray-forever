import Foundation

/// Один аят: арабский текст с огласовками (хафс) и транскрипция.
/// Транскрипция пословная: n-е слово через пробел соответствует n-му арабскому слову.
struct Ayah: Equatable {
    let number: Int
    let arabic: String
    let latin: String
    let cyrillic: String

    /// Кириллица для русского интерфейса, латиница для остальных.
    var transliteration: String {
        Bundle.main.preferredLocalizations.first == "ru" ? cyrillic : latin
    }

    var arabicWords: [String] { arabic.split(separator: " ").map(String.init) }
    var transliterationWords: [String] { transliteration.split(separator: " ").map(String.init) }
}

/// Короткие суры, которые можно прочитать после фото. Файл без зависимостей — он входит и в виджет.
enum Surah: String, CaseIterable, Codable, Identifiable {
    case fatiha, ikhlas, falaq, nas, kawthar, asr, kafirun

    var id: String { rawValue }

    var number: Int {
        switch self {
        case .fatiha: return 1
        case .asr: return 103
        case .kawthar: return 108
        case .kafirun: return 109
        case .ikhlas: return 112
        case .falaq: return 113
        case .nas: return 114
        }
    }

    var arabicName: String {
        switch self {
        case .fatiha: return "الفاتحة"
        case .ikhlas: return "الإخلاص"
        case .falaq: return "الفلق"
        case .nas: return "الناس"
        case .kawthar: return "الكوثر"
        case .asr: return "العصر"
        case .kafirun: return "الكافرون"
        }
    }

    var localizedName: String { NSLocalizedString("surah.\(rawValue)", comment: "") }

    /// В аль-Фатихе басмала — первый аят, в остальных сурах она показывается отдельно и не проверяется.
    var showsBasmala: Bool { self != .fatiha }

    static let basmala = Ayah(number: 0,
                              arabic: "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
                              latin: "Bismi llahi r-Rahmani r-Rahim",
                              cyrillic: "Бисми лляхи р-Рахмани р-Рахим")

    var ayat: [Ayah] {
        switch self {
        case .fatiha: return Self.fatihaAyat
        case .ikhlas: return Self.ikhlasAyat
        case .falaq: return Self.falaqAyat
        case .nas: return Self.nasAyat
        case .kawthar: return Self.kawtharAyat
        case .asr: return Self.asrAyat
        case .kafirun: return Self.kafirunAyat
        }
    }

    // MARK: - Тексты

    private static let fatihaAyat = [
        basmala.renumbered(1),
        Ayah(number: 2, arabic: "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ",
             latin: "Al-hamdu lillahi Rabbi l-'alamin",
             cyrillic: "Аль-хамду лилляхи Рабби ль-‘алямин"),
        Ayah(number: 3, arabic: "الرَّحْمَٰنِ الرَّحِيمِ",
             latin: "Ar-Rahmani r-Rahim",
             cyrillic: "Ар-Рахмани р-Рахим"),
        Ayah(number: 4, arabic: "مَالِكِ يَوْمِ الدِّينِ",
             latin: "Maliki yawmi d-din",
             cyrillic: "Малики яуми д-дин"),
        Ayah(number: 5, arabic: "إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ",
             latin: "Iyyaka na'budu wa-iyyaka nasta'in",
             cyrillic: "Иййака на‘буду ва-иййака наста‘ин"),
        Ayah(number: 6, arabic: "اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ",
             latin: "Ihdina s-sirata l-mustaqim",
             cyrillic: "Ихдина с-сырата ль-мустакым"),
        Ayah(number: 7, arabic: "صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ",
             latin: "Sirata lladhina an'amta 'alayhim ghayri l-maghdubi 'alayhim wa-la d-dallin",
             cyrillic: "Сырата ллязина ан‘амта ‘алейхим гайри ль-магдуби ‘алейхим ва-ля д-даллин"),
    ]

    private static let ikhlasAyat = [
        Ayah(number: 1, arabic: "قُلْ هُوَ اللَّهُ أَحَدٌ",
             latin: "Qul huwa llahu ahad",
             cyrillic: "Куль хува ллаху ахад"),
        Ayah(number: 2, arabic: "اللَّهُ الصَّمَدُ",
             latin: "Allahu s-samad",
             cyrillic: "Аллаху с-самад"),
        Ayah(number: 3, arabic: "لَمْ يَلِدْ وَلَمْ يُولَدْ",
             latin: "Lam yalid wa-lam yulad",
             cyrillic: "Лям ялид ва-лям юляд"),
        Ayah(number: 4, arabic: "وَلَمْ يَكُن لَّهُ كُفُوًا أَحَدٌ",
             latin: "Wa-lam yakun lahu kufuwan ahad",
             cyrillic: "Ва-лям якун ляху куфуан ахад"),
    ]

    private static let falaqAyat = [
        Ayah(number: 1, arabic: "قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
             latin: "Qul a'udhu bi-Rabbi l-falaq",
             cyrillic: "Куль а‘узу би-Рабби ль-фаляк"),
        Ayah(number: 2, arabic: "مِن شَرِّ مَا خَلَقَ",
             latin: "Min sharri ma khalaq",
             cyrillic: "Мин шарри ма халяк"),
        Ayah(number: 3, arabic: "وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ",
             latin: "Wa-min sharri ghasiqin idha waqab",
             cyrillic: "Ва-мин шарри гасикин иза вакаб"),
        Ayah(number: 4, arabic: "وَمِن شَرِّ النَّفَّاثَاتِ فِي الْعُقَدِ",
             latin: "Wa-min sharri n-naffathati fi l-'uqad",
             cyrillic: "Ва-мин шарри н-наффасати фи ль-‘укад"),
        Ayah(number: 5, arabic: "وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ",
             latin: "Wa-min sharri hasidin idha hasad",
             cyrillic: "Ва-мин шарри хасидин иза хасад"),
    ]

    private static let nasAyat = [
        Ayah(number: 1, arabic: "قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
             latin: "Qul a'udhu bi-Rabbi n-nas",
             cyrillic: "Куль а‘узу би-Рабби н-нас"),
        Ayah(number: 2, arabic: "مَلِكِ النَّاسِ",
             latin: "Maliki n-nas",
             cyrillic: "Малики н-нас"),
        Ayah(number: 3, arabic: "إِلَٰهِ النَّاسِ",
             latin: "Ilahi n-nas",
             cyrillic: "Иляхи н-нас"),
        Ayah(number: 4, arabic: "مِن شَرِّ الْوَسْوَاسِ الْخَنَّاسِ",
             latin: "Min sharri l-waswasi l-khannas",
             cyrillic: "Мин шарри ль-васваси ль-ханнас"),
        Ayah(number: 5, arabic: "الَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ",
             latin: "Alladhi yuwaswisu fi suduri n-nas",
             cyrillic: "Аллязи ювасвису фи судури н-нас"),
        Ayah(number: 6, arabic: "مِنَ الْجِنَّةِ وَالنَّاسِ",
             latin: "Mina l-jinnati wa-n-nas",
             cyrillic: "Мина ль-джиннати ва-н-нас"),
    ]

    private static let kawtharAyat = [
        Ayah(number: 1, arabic: "إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ",
             latin: "Inna a'taynaka l-kawthar",
             cyrillic: "Инна а‘тайнака ль-каусар"),
        Ayah(number: 2, arabic: "فَصَلِّ لِرَبِّكَ وَانْحَرْ",
             latin: "Fa-salli li-Rabbika wa-nhar",
             cyrillic: "Фа-салли ли-Раббика ва-нхар"),
        Ayah(number: 3, arabic: "إِنَّ شَانِئَكَ هُوَ الْأَبْتَرُ",
             latin: "Inna shani'aka huwa l-abtar",
             cyrillic: "Инна шани’ака хува ль-абтар"),
    ]

    private static let asrAyat = [
        Ayah(number: 1, arabic: "وَالْعَصْرِ",
             latin: "Wal-'asr",
             cyrillic: "Валь-‘аср"),
        Ayah(number: 2, arabic: "إِنَّ الْإِنسَانَ لَفِي خُسْرٍ",
             latin: "Inna l-insana la-fi khusr",
             cyrillic: "Инна ль-инсана ля-фи хуср"),
        Ayah(number: 3, arabic: "إِلَّا الَّذِينَ آمَنُوا وَعَمِلُوا الصَّالِحَاتِ وَتَوَاصَوْا بِالْحَقِّ وَتَوَاصَوْا بِالصَّبْرِ",
             latin: "Illa lladhina amanu wa-'amilu s-salihati wa-tawasaw bil-haqqi wa-tawasaw bis-sabr",
             cyrillic: "Илля ллязина аману ва-‘амилю с-салихати ва-тавасау биль-хакки ва-тавасау би-с-сабр"),
    ]

    private static let kafirunAyat = [
        Ayah(number: 1, arabic: "قُلْ يَا أَيُّهَا الْكَافِرُونَ",
             latin: "Qul ya ayyuha l-kafirun",
             cyrillic: "Куль я айюха ль-кафирун"),
        Ayah(number: 2, arabic: "لَا أَعْبُدُ مَا تَعْبُدُونَ",
             latin: "La a'budu ma ta'budun",
             cyrillic: "Ля а‘буду ма та‘будун"),
        Ayah(number: 3, arabic: "وَلَا أَنتُمْ عَابِدُونَ مَا أَعْبُدُ",
             latin: "Wa-la antum 'abiduna ma a'bud",
             cyrillic: "Ва-ля антум ‘абидуна ма а‘буд"),
        Ayah(number: 4, arabic: "وَلَا أَنَا عَابِدٌ مَّا عَبَدتُّمْ",
             latin: "Wa-la ana 'abidum ma 'abadtum",
             cyrillic: "Ва-ля ана ‘абидум ма ‘абадтум"),
        Ayah(number: 5, arabic: "وَلَا أَنتُمْ عَابِدُونَ مَا أَعْبُدُ",
             latin: "Wa-la antum 'abiduna ma a'bud",
             cyrillic: "Ва-ля антум ‘абидуна ма а‘буд"),
        Ayah(number: 6, arabic: "لَكُمْ دِينُكُمْ وَلِيَ دِينِ",
             latin: "Lakum dinukum wa-liya din",
             cyrillic: "Лякум динукум ва-лия дин"),
    ]
}

private extension Ayah {
    func renumbered(_ number: Int) -> Ayah {
        Ayah(number: number, arabic: arabic, latin: latin, cyrillic: cyrillic)
    }
}

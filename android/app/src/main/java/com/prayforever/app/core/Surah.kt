package com.prayforever.app.core

/**
 * Один аят: арабский текст с огласовками (хафс) и транскрипция.
 * Транскрипция пословная: n-е слово через пробел соответствует n-му арабскому слову.
 */
data class Ayah(
    val number: Int,
    val arabic: String,
    val latin: String,
    val cyrillic: String,
) {
    val arabicWords: List<String> get() = arabic.split(" ")

    /** Кириллица для русского интерфейса, латиница для остальных. */
    fun transliteration(russian: Boolean): String = if (russian) cyrillic else latin

    fun transliterationWords(russian: Boolean): List<String> = transliteration(russian).split(" ")
}

/**
 * Короткие суры, которые можно прочитать после фото. Сгенерировано из `Sajda/Recitation/Surah.swift`
 * скриптом scripts/gen_android_surahs.py; `SurahParityTest` проверяет, что тексты совпадают.
 */
enum class Surah(
    val key: String,
    val number: Int,
    val arabicName: String,
) {
    FATIHA("fatiha", 1, "الفاتحة"),
    IKHLAS("ikhlas", 112, "الإخلاص"),
    FALAQ("falaq", 113, "الفلق"),
    NAS("nas", 114, "الناس"),
    KAWTHAR("kawthar", 108, "الكوثر"),
    ASR("asr", 103, "العصر"),
    KAFIRUN("kafirun", 109, "الكافرون"),
    ;

    /** В аль-Фатихе басмала — первый аят, в остальных сурах она показывается отдельно и не проверяется. */
    val showsBasmala: Boolean get() = this != FATIHA

    val ayat: List<Ayah>
        get() =
            when (this) {
                FATIHA -> FATIHA_AYAT
                IKHLAS -> IKHLAS_AYAT
                FALAQ -> FALAQ_AYAT
                NAS -> NAS_AYAT
                KAWTHAR -> KAWTHAR_AYAT
                ASR -> ASR_AYAT
                KAFIRUN -> KAFIRUN_AYAT
            }

    companion object {
        val BASMALA =
            Ayah(
                number = 0,
                arabic = "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
                latin = "Bismi llahi r-Rahmani r-Rahim",
                cyrillic = "Бисми лляхи р-Рахмани р-Рахим",
            )

        private val FATIHA_AYAT =
            listOf(
                BASMALA.copy(number = 1),
                Ayah(
                    2,
                    "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ",
                    "Al-hamdu lillahi Rabbi l-'alamin",
                    "Аль-хамду лилляхи Рабби ль-‘алямин",
                ),
                Ayah(
                    3,
                    "الرَّحْمَٰنِ الرَّحِيمِ",
                    "Ar-Rahmani r-Rahim",
                    "Ар-Рахмани р-Рахим",
                ),
                Ayah(
                    4,
                    "مَالِكِ يَوْمِ الدِّينِ",
                    "Maliki yawmi d-din",
                    "Малики яуми д-дин",
                ),
                Ayah(
                    5,
                    "إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ",
                    "Iyyaka na'budu wa-iyyaka nasta'in",
                    "Иййака на‘буду ва-иййака наста‘ин",
                ),
                Ayah(
                    6,
                    "اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ",
                    "Ihdina s-sirata l-mustaqim",
                    "Ихдина с-сырата ль-мустакым",
                ),
                Ayah(
                    7,
                    "صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ",
                    "Sirata lladhina an'amta 'alayhim ghayri l-maghdubi 'alayhim wa-la d-dallin",
                    "Сырата ллязина ан‘амта ‘алейхим гайри ль-магдуби ‘алейхим ва-ля д-даллин",
                ),
            )

        private val IKHLAS_AYAT =
            listOf(
                Ayah(
                    1,
                    "قُلْ هُوَ اللَّهُ أَحَدٌ",
                    "Qul huwa llahu ahad",
                    "Куль хува ллаху ахад",
                ),
                Ayah(
                    2,
                    "اللَّهُ الصَّمَدُ",
                    "Allahu s-samad",
                    "Аллаху с-самад",
                ),
                Ayah(
                    3,
                    "لَمْ يَلِدْ وَلَمْ يُولَدْ",
                    "Lam yalid wa-lam yulad",
                    "Лям ялид ва-лям юляд",
                ),
                Ayah(
                    4,
                    "وَلَمْ يَكُن لَّهُ كُفُوًا أَحَدٌ",
                    "Wa-lam yakun lahu kufuwan ahad",
                    "Ва-лям якун ляху куфуан ахад",
                ),
            )

        private val FALAQ_AYAT =
            listOf(
                Ayah(
                    1,
                    "قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
                    "Qul a'udhu bi-Rabbi l-falaq",
                    "Куль а‘узу би-Рабби ль-фаляк",
                ),
                Ayah(
                    2,
                    "مِن شَرِّ مَا خَلَقَ",
                    "Min sharri ma khalaq",
                    "Мин шарри ма халяк",
                ),
                Ayah(
                    3,
                    "وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ",
                    "Wa-min sharri ghasiqin idha waqab",
                    "Ва-мин шарри гасикин иза вакаб",
                ),
                Ayah(
                    4,
                    "وَمِن شَرِّ النَّفَّاثَاتِ فِي الْعُقَدِ",
                    "Wa-min sharri n-naffathati fi l-'uqad",
                    "Ва-мин шарри н-наффасати фи ль-‘укад",
                ),
                Ayah(
                    5,
                    "وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ",
                    "Wa-min sharri hasidin idha hasad",
                    "Ва-мин шарри хасидин иза хасад",
                ),
            )

        private val NAS_AYAT =
            listOf(
                Ayah(
                    1,
                    "قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
                    "Qul a'udhu bi-Rabbi n-nas",
                    "Куль а‘узу би-Рабби н-нас",
                ),
                Ayah(
                    2,
                    "مَلِكِ النَّاسِ",
                    "Maliki n-nas",
                    "Малики н-нас",
                ),
                Ayah(
                    3,
                    "إِلَٰهِ النَّاسِ",
                    "Ilahi n-nas",
                    "Иляхи н-нас",
                ),
                Ayah(
                    4,
                    "مِن شَرِّ الْوَسْوَاسِ الْخَنَّاسِ",
                    "Min sharri l-waswasi l-khannas",
                    "Мин шарри ль-васваси ль-ханнас",
                ),
                Ayah(
                    5,
                    "الَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ",
                    "Alladhi yuwaswisu fi suduri n-nas",
                    "Аллязи ювасвису фи судури н-нас",
                ),
                Ayah(
                    6,
                    "مِنَ الْجِنَّةِ وَالنَّاسِ",
                    "Mina l-jinnati wa-n-nas",
                    "Мина ль-джиннати ва-н-нас",
                ),
            )

        private val KAWTHAR_AYAT =
            listOf(
                Ayah(
                    1,
                    "إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ",
                    "Inna a'taynaka l-kawthar",
                    "Инна а‘тайнака ль-каусар",
                ),
                Ayah(
                    2,
                    "فَصَلِّ لِرَبِّكَ وَانْحَرْ",
                    "Fa-salli li-Rabbika wa-nhar",
                    "Фа-салли ли-Раббика ва-нхар",
                ),
                Ayah(
                    3,
                    "إِنَّ شَانِئَكَ هُوَ الْأَبْتَرُ",
                    "Inna shani'aka huwa l-abtar",
                    "Инна шани’ака хува ль-абтар",
                ),
            )

        private val ASR_AYAT =
            listOf(
                Ayah(
                    1,
                    "وَالْعَصْرِ",
                    "Wal-'asr",
                    "Валь-‘аср",
                ),
                Ayah(
                    2,
                    "إِنَّ الْإِنسَانَ لَفِي خُسْرٍ",
                    "Inna l-insana la-fi khusr",
                    "Инна ль-инсана ля-фи хуср",
                ),
                Ayah(
                    3,
                    "إِلَّا الَّذِينَ آمَنُوا وَعَمِلُوا الصَّالِحَاتِ وَتَوَاصَوْا بِالْحَقِّ وَتَوَاصَوْا بِالصَّبْرِ",
                    "Illa lladhina amanu wa-'amilu s-salihati wa-tawasaw bil-haqqi wa-tawasaw bis-sabr",
                    "Илля ллязина аману ва-‘амилю с-салихати ва-тавасау биль-хакки ва-тавасау би-с-сабр",
                ),
            )

        private val KAFIRUN_AYAT =
            listOf(
                Ayah(
                    1,
                    "قُلْ يَا أَيُّهَا الْكَافِرُونَ",
                    "Qul ya ayyuha l-kafirun",
                    "Куль я айюха ль-кафирун",
                ),
                Ayah(
                    2,
                    "لَا أَعْبُدُ مَا تَعْبُدُونَ",
                    "La a'budu ma ta'budun",
                    "Ля а‘буду ма та‘будун",
                ),
                Ayah(
                    3,
                    "وَلَا أَنتُمْ عَابِدُونَ مَا أَعْبُدُ",
                    "Wa-la antum 'abiduna ma a'bud",
                    "Ва-ля антум ‘абидуна ма а‘буд",
                ),
                Ayah(
                    4,
                    "وَلَا أَنَا عَابِدٌ مَّا عَبَدتُّمْ",
                    "Wa-la ana 'abidum ma 'abadtum",
                    "Ва-ля ана ‘абидум ма ‘абадтум",
                ),
                Ayah(
                    5,
                    "وَلَا أَنتُمْ عَابِدُونَ مَا أَعْبُدُ",
                    "Wa-la antum 'abiduna ma a'bud",
                    "Ва-ля антум ‘абидуна ма а‘буд",
                ),
                Ayah(
                    6,
                    "لَكُمْ دِينُكُمْ وَلِيَ دِينِ",
                    "Lakum dinukum wa-liya din",
                    "Лякум динукум ва-лия дин",
                ),
            )
    }
}

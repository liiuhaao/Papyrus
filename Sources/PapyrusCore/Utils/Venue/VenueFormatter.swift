// VenueFormatter.swift
// Maps full venue names to standard abbreviations.
// Table: (lowercased-pattern, abbreviation), longest/most-specific first.

import Foundation

struct VenueFormatter {
    static func unifiedDisplayName(_ venue: String) -> String {
        let trimmed = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let abbreviation = abbreviate(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        return abbreviation.isEmpty ? trimmed : abbreviation
    }

    static func unifiedFullName(_ venue: String) -> String {
        let trimmed = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let normalized = normalizeFullName(trimmed)
        return normalized.isEmpty ? trimmed : normalized
    }

    static func resolvedVenueParts(_ venue: String, abbreviation: String?) -> (full: String, abbr: String) {
        let raw = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return ("", "") }

        let full = unifiedFullName(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let fullValue = full.isEmpty ? raw : full

        let explicitAbbr = abbreviation?.trimmingCharacters(in: .whitespacesAndNewlines)
        let derived = abbreviate(fullValue).trimmingCharacters(in: .whitespacesAndNewlines)
        var abbr = (explicitAbbr?.isEmpty == false ? explicitAbbr! : derived)

        if abbr.isEmpty || equalsIgnoreCase(abbr, fullValue) {
            let fallback = fallbackAbbreviation(fullValue)
            abbr = fallback.isEmpty ? fullValue : fallback
        }

        return (fullValue, abbr)
    }

    static func abbreviate(_ venue: String) -> String {
        // User custom venues take priority
        if let custom = VenueFormatterConfig.customVenues[venue] { return custom }

        // Cached abbreviation from Semantic Scholar or DBLP lookup
        if let cached = VenueAbbreviationService.shared.cached(venue: venue) { return cached }

        // Already looks like an abbreviation (short + majority uppercase)
        let letters = venue.filter { $0.isLetter }
        let upper   = letters.filter { $0.isUppercase }
        if venue.count <= 8 && !letters.isEmpty && upper.count * 2 >= letters.count {
            return venue
        }

        // Pass 1: known abbreviation appears verbatim as a token in the original string
        // e.g. "Proceedings of the 37th AAAI Conference" → token "AAAI" → "AAAI"
        let tokens = venue.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "&"))) }
        for token in tokens where !token.isEmpty {
            if let abbr = Self.knownAbbreviations[token]
                ?? Self.knownAbbreviations[token.uppercased()]
                ?? Self.knownAbbreviations[token.lowercased()] {
                return abbr
            }
        }

        // Pass 2: strip noise then substring-match the table
        let normalized = Self.normalize(venue)
        for (pattern, abbr) in Self.table {
            if normalized.contains(pattern) { return abbr }
        }

        return venue
    }

    // MARK: - Normalisation

    private static func normalize(_ venue: String) -> String {
        var s = venue.lowercased()
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        for prefix in ["proceedings of the ", "proceedings of "] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        if s.hasPrefix("the ") { s = String(s.dropFirst(4)) }

        let cleaned = s.components(separatedBy: .whitespaces).filter { token in
            guard !token.isEmpty else { return false }
            if Self.ordinalWords.contains(token) { return false }
            if token.first?.isNumber == true { return false }
            return true
        }.joined(separator: " ")

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    private static func normalizeFullName(_ venue: String) -> String {
        let rawTokens = venue.components(separatedBy: .whitespacesAndNewlines)
        let cleanedTokens = rawTokens.map { token in
            token.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "&")))
        }

        var startIndex = 0
        let lowerTokens = cleanedTokens.map { $0.lowercased() }
        if lowerTokens.starts(with: ["proceedings", "of", "the"]) {
            startIndex = 3
        } else if lowerTokens.starts(with: ["proceedings", "of"]) {
            startIndex = 2
        }

        var output: [String] = []
        for token in cleanedTokens[startIndex...] {
            if token.isEmpty { continue }
            let lower = token.lowercased()
            if ordinalWords.contains(lower) { continue }
            if isNumericOrdinal(lower) { continue }
            output.append(token)
        }

        return output.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func equalsIgnoreCase(_ a: String, _ b: String) -> Bool {
        return a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func isNumericOrdinal(_ token: String) -> Bool {
        let digits = token.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
        if digits.count == token.count { return true }
        if digits.isEmpty { return false }
        let suffix = token.dropFirst(digits.count)
        return ["st", "nd", "rd", "th"].contains(String(suffix))
    }

    private static func fallbackAbbreviation(_ venue: String) -> String {
        let tokens = venue.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard shouldDeriveFallbackAbbreviation(tokens) else { return "" }
        let letters = tokens.compactMap { $0.first }
        let abbr = letters.map { String($0).uppercased() }.joined()
        if abbr.isEmpty { return venue }
        if abbr.count <= 8 { return abbr }
        return String(abbr.prefix(8))
    }

    private static func shouldDeriveFallbackAbbreviation(_ tokens: [String]) -> Bool {
        let significant = tokens.filter { token in
            let lower = token.lowercased()
            return !token.isEmpty
                && !ordinalWords.contains(lower)
                && !isNumericOrdinal(lower)
        }
        return significant.count >= 2
    }

    private static let ordinalWords: Set<String> = [
        "first", "second", "third", "fourth", "fifth", "sixth",
        "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth",
        "thirteenth", "fourteenth", "fifteenth", "sixteenth",
        "seventeenth", "eighteenth", "nineteenth", "twentieth",
    ]

    // Token → abbreviation map (built from table + manual aliases)
    private static let knownAbbreviations: [String: String] = {
        var d: [String: String] = [:]
        for (_, abbr) in Self.table {
            d[abbr] = abbr
            d[abbr.lowercased()] = abbr
            d[abbr.uppercased()] = abbr
        }
        d["NeurIPS"] = "NeurIPS"; d["NIPS"] = "NeurIPS"; d["nips"] = "NeurIPS"; d["neurips"] = "NeurIPS"
        d["USENIX"] = "USENIX"
        return d
    }()

    // Ordered longest-pattern-first so more specific entries win.
    // Journals first (shorter patterns, higher collision risk), then conferences.
    private static let table: [(String, String)] = [
        // ── Journals: IEEE ─────────────────────────────────────────────────────
        ("selected areas in communications", "JSAC"),
        ("transactions on wireless communications", "TWC"),
        ("transactions on mobile computing", "TMC"),
        ("transactions on communications", "TCOM"),
        ("transactions on networking", "TON"),
        ("transactions on parallel and distributed systems", "TPDS"),
        ("transactions on dependable and secure computing", "TDSC"),
        ("transactions on information forensics and security", "TIFS"),
        ("transactions on computers", "TC"),
        ("transactions on software engineering", "TSE"),
        ("transactions on information theory", "TIT"),
        ("transactions on neural networks and learning systems", "TNNLS"),
        ("transactions on vehicular technology", "TVT"),
        ("transactions on industrial informatics", "TII"),
        ("transactions on image processing", "TIP"),
        ("transactions on signal processing", "TSP"),
        ("transactions on automatic control", "TAC"),
        ("transactions on robotics", "T-RO"),
        ("transactions on cybernetics", "TCYB"),
        ("transactions on emerging topics in computing", "TETC"),
        ("transactions on cloud computing", "TCC"),
        ("transactions on services computing", "TSC"),
        ("transactions on big data", "TBD"),
        ("transactions on cognitive communications and networking", "TCCN"),
        ("internet of things journal", "IoTJ"),
        ("journal on selected topics in signal processing", "JSTSP"),
        ("communications surveys and tutorials", "COMST"),
        ("wireless communications letters", "WCL"),
        ("communications letters", "IEEE Commun. Lett."),
        ("ieee access", "IEEE Access"),
        ("journal of the acm", "JACM"),
        ("communications of the acm", "CACM"),
        ("transactions on computer systems", "TOCS"),
        ("transactions on database systems", "TODS"),
        ("transactions on knowledge discovery from data", "TKDD"),
        ("transactions on intelligent systems and technology", "TIST"),
        ("transactions on privacy and security", "TOPS"),
        ("transactions on algorithms", "TALG"),
        ("transactions on sensor networks", "TOSN"),
        ("proceedings of the vldb endowment", "PVLDB"),
        ("vldb journal", "VLDBJ"),
        ("data mining and knowledge discovery", "DMKD"),
        ("knowledge and information systems", "KAIS"),
        ("information sciences", "Inf. Sci."),
        ("information processing letters", "IPL"),
        ("theoretical computer science", "TCS"),
        ("journal of computer science and technology", "JCST"),
        ("science china information sciences", "SCIS"),
        ("frontiers of computer science", "FCS"),
        ("neural networks", "Neural Netw."),
        ("pattern recognition letters", "PRL"),
        ("pattern recognition", "PR"),
        ("expert systems with applications", "ESWA"),
        ("knowledge-based systems", "KBS"),
        ("neurocomputing", "Neurocomputing"),
        ("computer vision and image understanding", "CVIU"),
        ("computer graphics forum", "CGF"),
        ("transactions on graphics", "TOG"),
        ("transactions on visualization and computer graphics", "TVCG"),
        ("future generation computer systems", "FGCS"),
        ("journal of network and computer applications", "JNCA"),
        ("computer networks", "Comput. Netw."),
        ("wireless networks", "WINET"),
        ("pervasive and mobile computing", "PMC"),
        ("computers & security", "COSE"),
        ("computers and security", "COSE"),
        ("empirical software engineering", "EMSE"),
        ("journal of systems and software", "JSS"),
        ("information and software technology", "IST"),
        ("international journal of computer vision", "IJCV"),
        ("journal of machine learning research", "JMLR"),
        ("machine learning", "Mach. Learn."),
        ("artificial intelligence", "AIJ"),
        ("nature machine intelligence", "Nat. Mach. Intell."),
        ("nature communications", "Nat. Commun."),
        ("pattern analysis and machine intelligence", "TPAMI"),
        ("transactions on knowledge and data engineering", "TKDE"),
        ("transactions on information systems", "TOIS"),

        // ── Conferences ────────────────────────────────────────────────────────
        ("european conference on machine learning and 25th principles and practice of knowledge discovery in databases", "ECML-PKDD"),
        ("the annual conference of the north american chapter of the association for computational linguistics", "NAACL"),
        ("european symposium on artificial neural networks, computational intelligence and machine learning", "ESANN"),
        ("\"international conference on collaborative computing: networking, applications and worksharing\"", "CollaborateCom"),
        ("the annual conference of the european chapter of the association for computational linguistics", "EACL"),
        ("international conference on parallel and distributed computing, applications and technologies", "PDCAT"),
        ("international conference on the theory and application of cryptology and information security", "ASIACRYPT"),
        ("ieee international conference on application-specific systems, architectures, and processors", "ASAP"),
        ("international conference on modeling, analysis and simulation of wireless and mobile systems", "MSWiM"),
        ("ieee international conference on trust, security and privacy in computing and communications", "TrustCom"),
        ("international conference for high performance computing, networking, storage, and analysis", "SC"),
        ("international workshop on network and operating system support for digital audio and video", "NOSSDAV"),
        ("international conference on medical image computing and computer assisted intervention", "MICCAI"),
        ("ieee international symposium on parallel and distributed processing with applications", "ISPA"),
        ("acm sigspatial international conference on advances in geographic information systems", "SIGSPATIAL"),
        ("international conference on formal techniques for (networked and) distributed systems", "FORTE"),
        ("international conference on verification, model checking, and abstract interpretation", "VMCAI"),
        ("ieee international symposium on a world of wireless, mobile and multimedia networks", "WoWMoM"),
        ("ccf international conference on natural language processing and chinese computing", "NLPCC"),
        ("international conference on principles of knowledge representation and reasoning", "KR"),
        ("'symposium on dependable software engineering: theories, tools and applications'", "SETTA"),
        ("international conference on algorithms and architectures for parallel processing", "ICA3PP"),
        ("international conference on languages, compilers and tools for embedded systems", "LCTES"),
        ("ieee international conference on software analysis, evolution and reengineering", "SANER"),
        ("pacific graphics, the pacific conference on computer graphics and applications", "PG"),
        ("ieee international conference on high performance computing and communications", "HPCC"),
        ("acm/ieee international conference on information processing in sensor networks", "IPSN"),
        ("conference on object-oriented programming systems, languages, and applications", "OOPSLA"),
        ("ieee international working conference on source code analysis and manipulation", "SCAM"),
        ("international conference on theory and applications of satisfiability testing", "SAT"),
        ("international conference on parallel architectures and compilation techniques", "PACT"),
        ("international symposium on automated technology for verification and analysis", "ATVA"),
        ("international conference on principles and practice of constraint programming", "CP"),
        ("international conference on evaluation and assessment in software engineering", "EASE"),
        ("international conference on research on development in information retrieval", "SIGIR"),
        ("international conference on emerging networking experiments and technologies", "CoNEXT"),
        ("ieee international conference on software quality, reliability and security", "QRS"),
        ("acm conference on computer supported cooperative work and social computing", "CSCW"),
        ("acm international conference on mobile systems, applications, and services", "MobiSys"),
        ("international conference on wireless algorithms, systems, and applications", "WASA"),
        ("international conference on practice and theory of public-key cryptography", "PKC"),
        ("international conference on security and privacy in communication networks", "SecureComm"),
        ("international conference on model driven engineering languages and systems", "MoDELS"),
        ("international conference on software engineering and knowledge engineering", "SEKE"),
        ("the annual conference on empirical methods in natural language processing", "EMNLP"),
        ("international conference on knowledge science, engineering and management", "KSEM"),
        ("ieee international conference on acoustics, speech, and signal processing", "ICASSP"),
        ("international conference on computer supported cooperative work in design", "CSCWD"),
        ("international symposium on empirical software engineering and measurement", "ESEM"),
        ("acm international joint conference on pervasive and ubiquitous computing", "UbiComp/ISWC"),
        ("ieee international conference on pervasive computing and communications", "PerCom"),
        ("ieee international conference on sensing, communication, and networking", "SECON"),
        ("international conference on cryptographic hardware and embedded systems", "CHES"),
        ("acm international conference on the foundations of software engineering", "FSE"),
        ("international symposium on performance analysis of systems and software", "ISPASS"),
        ("ieee international symposium on high-performance computer architecture", "HPCA"),
        ("acm sigplan symposium on principles & practice of parallel programming", "PPoPP"),
        ("ieee international conference on ubiquitous intelligence and computing", "UIC"),
        ("international conference on research incomputational molecular biology", "RECOMB"),
        ("acm annual international conference on mobile computing and networking", "MobiCom"),
        ("acm conference on security and privacy in wireless and mobile networks", "WiSec"),
        ("acm sigplan conference on programming language design & implementation", "PLDI"),
        ("\"international conference on hybrid systems: computation and control\"", "HSCC"),
        ("the international conference on advanced data mining and applications", "ADMA"),
        ("international symposium on advanced parallel programming technologies", "APPT"),
        ("ieee international conference on computer communications and networks", "ICCCN"),
        ("international conference on autonomous agents and multiagent systems", "AAMAS"),
        ("acm international conference on information and knowledge management", "CIKM"),
        ("acm symposium on high-performance parallel and distributed computing", "HPDC"),
        ("international conference on advanced information systems engineering", "CAiSE"),
        ("acm sigsoft international symposium on software testing and analysis", "ISSTA"),
        ("ieee/rsj international conference on intelligent robots and systems", "IROS"),
        ("acm/sigda international symposium on field-programmable gate arrays", "FPGA"),
        ("international symposium on bioinformatics research and applications", "ISBRA"),
        ("international conference on information and communications security", "ICICS"),
        ("international conference on engineering of complex computer systems", "ICECCS"),
        ("acm sigplan-sigact symposium on principles of programming languages", "POPL"),
        ("international conference on artificial intelligence and statistics", "AISTATS"),
        ("international conference on automatic face and gesture recognition", "FG"),
        ("international conference on massive storage systems and technology", "MSST"),
        ("ieee international conference on parallel and distributed systems", "ICPADS"),
        ("ieee real-time and embedded technology and applications symposium", "RTAS"),
        ("international symposium on recent advances in intrusion detection", "RAID"),
        ("international conference on parallel problem solving from nature", "PPSN"),
        ("international conference on computer animation and social agents", "CASA"),
        ("conference of the international speech communication association", "InterSpeech"),
        ("ieee international parallel and distributed processing symposium", "IPDPS"),
        ("annual meeting of the association for computational linguistics", "ACL"),
        ("pacific rim international conference on artificial intelligence", "PRICAI"),
        ("the international symposium on code generation and optimization", "IEEE/ACM CGO"),
        ("acm international conference on interactive surfaces and spaces", "ISS"),
        ("ieee international conference on bioinformatics and biomedicine", "BIBM"),
        ("usenix symposium on networked systems design and implementation", "NSDI"),
        ("international conference on information security and cryptology", "INSCRYPT"),
        ("usenix symposium on operating systems design and implementation", "OSDI"),
        ("ieee/cvf conference on computer vision and pattern recognition", "CVPR"),
        ("pacific-asia conference on knowledge discovery and data mining", "PAKDD"),
        ("ieee symposium on field-programmable custom computing machines", "FCCM"),
        ("ieee international conference on systems, man, and cybernetics", "SMC"),
        ("detection of intrusions and malware & vulnerability assessment", "DIMVA"),
        ("international conference on software maintenance and evolution", "ICSME"),
        ("ieee international conference on web services (research track)", "ICWS"),
        ("ieee international conference on software services engineering", "SSE"),
        ("international conference on automated planning and scheduling", "ICAPS"),
        ("international conference on document analysis and recognition", "ICDAR"),
        ("international conference on tools with artificial intellignce", "ICTAI"),
        ("international joint conference on natural language processing", "IJCNLP"),
        ("ieee/cvf winter conference on applications of computer vision", "WACV"),
        ("international conference on geometric modeling and processing", "GMP"),
        ("international conference on virtual reality and visualization", "ICVRV"),
        ("chinese conference on pattern recognition and computer vision", "PRCV"),
        ("apweb-waim joint international conference on web and big data", "APWeb-WAIM"),
        ("european joint conferences on theory and practice of software", "ETAPS"),
        ("international conference on innovative data systems research", "CIDR"),
        ("acm symposium on parallelism in algorithms and architectures", "SPAA"),
        ("international conference on mobility, sensing and networking", "MSN"),
        ("ieee international symposium on reliable distributed systems", "SRDS"),
        ("international conference on dependable systems and networks", "DSN"),
        ("international conference on digital forensics & cyber crime", "ICDF2C"),
        ("international computer software and applications conference", "COMPSAC"),
        ("\"requirements engineering: foundation for software quality\"", "REFSQ"),
        ("the international conference on computational visual media", "CVM"),
        ("acm sigmm international conference on multimedia retrieval", "ICMR"),
        ("ieee/acm international conference on computer-aided design", "ICCAD"),
        ("european conference on computer supported cooperative work", "ECSCW"),
        ("australasia conference on information security and privacy", "ACISP"),
        ("ifip wg 11.9 international conference on digital forensics", "IFIP WG 11.9"),
        ("acm workshop on information hiding and multimedia security", "IH&MMSec"),
        ("ieee conference on secure and trustworthy machine learning", "SATML"),
        ("international conference on automated software engineering", "ASE"),
        ("international conference on neural information processing", "ICONIP"),
        ("international joint conference on artificial intelligence", "IJCAI"),
        ("acm siggraph/eurographics symposium on computer animation", "SCA"),
        ("international conference on extending database technology", "EDBT"),
        ("european conference on parallel and distributed computing", "Euro-Par"),
        ("international conference on field programmable technology", "FPT"),
        ("ieee international symposium on workload characterization", "IISWC"),
        ("the international aaai conference on web and social media", "ICWSM"),
        ("caai international conference on artificial intelligence", "CICAI"),
        ("ieee international conference on robotics and automation", "ICRA"),
        ("acm special interest group on measurement and evaluation", "SIGMETRICS"),
        ("international conference on business information systems", "BIS"),
        ("ieee international conference on computer communications", "INFOCOM"),
        ("network and distributed system security (ndss) symposium", "NDSS"),
        ("international conference on mining software repositories", "MSR"),
        ("international conference on algorithmic learning theory", "ALT"),
        ("international conference on computer-aided verification", "CAV"),
        ("acm sigaccess conference on computers and accessibility", "ASSETS"),
        ("acm symposium on user interface software and technology", "UIST"),
        ("asia conference on computer and communications security", "AsiaCCS"),
        ("acm symposium on access control models and technologies", "SACMAT"),
        ("internationnal conference on computational linguistics", "COLING"),
        ("international conference on artificial neural networks", "ICANN"),
        ("the ieee international conference on multimedia & expo", "ICME"),
        ("international symposium on mixed and augmented reality", "ISMAR"),
        ("international conference on web search and data mining", "WSDM"),
        ("acm international conference on multimodal interaction", "ICMI"),
        ("ieee/acm international symposium on quality of service", "IWQoS"),
        ("acm conference on computer and communications security", "CCS"),
        ("international conference on formal engineering methods", "ICFEM"),
        ("ieee international conference on program comprehension", "ICPC"),
        ("international conference on service oriented computing", "ICSOC"),
        ("ieee international requirements engineering conference", "RE"),
        ("conference on computational natural language learning", "CoNLL"),
        ("international joint conference on rules and reasoning", "RuleML+RR"),
        ("the ieee international conference on image processing", "ICIP"),
        ("international joint conference on automated reasoning", "IJCAR"),
        ("ieee/acm international symposium on microarchitecture", "MICRO"),
        ("acm international conference on supporting group work", "GROUP"),
        ("ieee/ifip network operations and management symposium", "NOMS"),
        ("international conference on learning representations", "ICLR"),
        ("conference on uncertainty in artificial intelligence", "UAI"),
        ("ieee international symposium on circuits and systems", "ISCAS"),
        ("acm symposium on principles of distributed computing", "PODC"),
        ("the acm international systems and storage conference", "SYSTOR"),
        ("conference on neural information processing systems", "NeurIPS"),
        ("advances in neural information processing systems", "NeurIPS"),
        ("neural information processing systems", "NeurIPS"),
        ("neurips", "NeurIPS"),
        ("nips", "NeurIPS"),
        ("asia and south pacific design automation conference", "ASP-DAC"),
        ("acm international conference on computing frontiers", "CF"),
        ("acm conference on embedded networked sensor systems", "SenSys"),
        ("european symposium on research in computer security", "ESORICS"),
        ("ieee international symposium on information theory", "ISIT"),
        ("ieee international conference on cluster computing", "CLUSTER"),
        ("usenix conference on file and storage technologies", "FAST"),
        ("\"hot chips: a symposium on high performance chips\"", "Hot Chips"),
        ("ieee international conference on network protocols", "ICNP"),
        ("acm international conference on multimedia systems", "MMSys"),
        ("ifip international information security conference", "SEC"),
        ("european conference on object-oriented programming", "ECOOP"),
        ("usenix workshop on hot topics in operating systems", "HotOS"),
        ("international joint conference on neural networks", "IJCNN"),
        ("international symposium on computational geometry", "SOCG"),
        ("ieee international conference on data engineering", "ICDE"),
        ("international conference on very large data bases", "VLDB"),
        ("the international conference on networked systems", "NETYS"),
        ("international conference on intelligent computing", "ICIC"),
        ("wireless communications and networking conference", "WCNC"),
        ("international conference on case-based reasoning", "ICCBR"),
        ("ieee international conference on computer vision", "ICCV"),
        ("'international conference on concurrency theory'", "CONCUR"),
        ("international symposium on computer architecture", "ISCA"),
        ("ieee international conference on cloud computing", "Cloud"),
        ("annual computer security applications conference", "ACSAC"),
        ("international conference on function programming", "ICFP"),
        ("international conference on software engineering", "ICSE"),
        ("international conference on runtime verification", "RV"),
        ("genetic and evolutionary computation conference", "GECCO"),
        ("international conference on pattern recognition", "ICPR"),
        ("international conference on multimedia modeling", "MMM"),
        ("acm symposium on principles of database systems", "PODS"),
        ("international conference on parallel processing", "ICPP"),
        ("acm conference on designing interactive systems", "DIS"),
        ("annual meeting of the cognitive science society", "CogSci"),
        ("ieee international conference on communications", "ICC"),
        ("digital forensic research workshop asia pacific", "DFRWS APAC"),
        ("ieee european symposium on security and privacy", "EuroS&P"),
        ("international conference on cryptology in india", "INDOCRYPT"),
        ("european conference on artificial intelligence", "ECAI"),
        ("acm international conference on supercomputing", "ICS"),
        ("ieee symposium on computers and communications", "ISCC"),
        ("eurographics symposium on geometry processing", "SGP"),
        ("acm conference on intelligent user interfaces", "IUI"),
        ("international conference on embedded software", "EMSOFT"),
        ("acm symposium on operating systems principles", "SOSP"),
        ("international conference on machine learning", "ICML"),
        ("international joint conference on biometrics", "IJCB"),
        ("european conference on information retrieval", "ECIR"),
        ("ieee international conference on data mining", "ICDM"),
        ("siam international conference on data mining", "SDM"),
        ("asia-pacific software engineering conference", "APSEC"),
        ("symposium on probabilistic machine learning", "ProbML"),
        ("ieee symposium on logic in computer science", "LICS"),
        ("international conference on database theory", "ICDT"),
        ("acm sigops asia-pacific workshop on systems", "APSys"),
        ("international conference on computer design", "ICCD"),
        ("ifip international conference on networking", "Networking"),
        ("ieee computer security foundations workshop", "CSFW"),
        ("theoretical aspects of software engineering", "TASE"),
        ("aaai conference on artificial intelligence", "AAAI"),
        ("acm international conference on multimedia", "ACM MM"),
        ("database systems for advanced applications", "DASFAA"),
        ("ieee international test conference in asia", "ITC-Asia"),
        ("conference on machine learning and systems", "MLSys"),
        ("ieee conference on local computer networks", "LCN"),
        ("international wireless internet conference", "WiCON"),
        ("ieee congress on evolutionary computation", "CEC"),
        ("'formal methods in computer-aided design'", "FMCAD"),
        ("acm-siam symposium on discrete algorithms", "SODA"),
        ("ieee international conference on big data", "BigData"),
        ("applied cryptography and network security", "ACNS"),
        ("passive and active measurement conference", "PAM"),
        ("international symposium on formal methods", "FM"),
        ("the conference on parsimony and learning", "CPAL"),
        ("eurographics conference on visualization", "EuroVis"),
        ("symposium on solid and physical modeling", "SPM"),
        ("acm symposium on the theory of computing", "STOC"),
        ("web information systems and applications", "WISA"),
        ("conference on web and internet economics", "WINE"),
        ("international world wide web conferences", "WWW"),
        ("financial cryptography and data security", "FC"),
        ("privacy enhancing technologies symposium", "PETS"),
        ("symposium on usable privacy and security", "SOUPS"),
        ("acm knowledge discovery and data mining", "SIGKDD"),
        ("european conference on computer systems", "EuroSys"),
        ("cryptographer's track at rsa conference", "CT-RSA"),
        ("international static analysis symposium", "SAS"),
        ("european conference on computer vision", "ECCV"),
        ("asia pacific bioinformatics conference", "APBC"),
        ("ieee symposium on security and privacy", "S&P"),
        ("asia-pacific symposium on internetware", "Internetware"),
        ("international conference on 3d vision", "3DV"),
        ("the conference on automated deduction", "CADE"),
        ("european signal processing conference", "EUSIPCO"),
        ("international semantic web conference", "ISWC"),
        ("acm conference on recommender systems", "RecSys"),
        ("ieee global communications conference", "GLOBECOM"),
        ("asian conference on machine learning", "ACML"),
        ("annual conference on learning theory", "COLT"),
        ("ieee pacific visualization symposium", "PacificVis"),
        ("acm conference on management of data", "SIGMOD"),
        ("the ieee real-time systems symposium", "RTSS"),
        ("asian conference on computer vision", "ACCV"),
        ("eurographics symposium on rendering", "EGSR"),
        ("design, automation & test in europe", "DATE"),
        ("asia-pacific workshop on networking", "APNet"),
        ("acm internet measurement conference", "IMC"),
        ("international cryptology conference", "CRYPTO"),
        ("international middleware conference", "Middleware"),
        ("usenix annual technical conference", "USENIX ATC"),
        ("digital forensic research workshop", "DFRWS"),
        ("british machine vision conference", "BMVC"),
        ("theory of cryptography conference", "TCC"),
        ("the conference on robot learning", "CoRL"),
        ("acm symposium on cloud computing", "SoCC"),
        ("conference on language modeling", "COLM"),
        ("computer graphics international", "CGI"),
        ("information security conference", "ISC"),
        ("new security paradigms workshop", "NSPW"),
        ("acm siggraph annual conference", "ACM SIGGRAPH"),
        ("virtual execution environments", "VEE"),
        ("european cryptology conference", "EUROCRYPT"),
        ("selected areas in cryptography", "SAC"),
        ("learning on graphs conference", "LOG"),
        ("ieee visualization conference", "IEEE VIS"),
        ("great lakes symposium on vlsi", "GLSVLSI"),
        ("international test conference", "ITC"),
        ("robotics science and systems", "RSS"),
        ("design automation conference", "DAC"),
        ("ieee european test symposium", "ETS"),
        ("data compression conference", "DCC"),
        ("usenix security symposium", "USENIX Security"),
        ("fast software encryption", "FSE"),
        ("acm multimedia asia", "MMAsia"),
        ("eurographics", "Eurographics"),
    ]
}

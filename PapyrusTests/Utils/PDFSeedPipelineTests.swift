import Foundation
import Testing
@testable import PapyrusCore

@MainActor
struct PDFSeedPipelineTests {
    @Test
    func seedExtractorDoesNotTreatColonTitleAsDenseAuthorLine() async throws {
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "pdf-seed-memoryllm-colon-title",
            lines: [
                "MEMORYLLM: Towards Self-Updatable Large Language Models",
                "Yu Wang* 1 Yifan Gao 2 Xiusi Chen 3 Haoming Jiang 2",
                "Shiyang Li 2 Jingfeng Yang 2 Qingyu Yin 2 Zheng Li 2",
                "Abstract"
            ]
        )

        let seed = await PDFSeedExtractor.extract(from: pdfURL)

        #expect(seed.title == "MEMORYLLM: Towards Self-Updatable Large Language Models")
        #expect(seed.authors == "Yu Wang, Yifan Gao, Xiusi Chen, Haoming Jiang, Shiyang Li, Jingfeng Yang, Qingyu Yin, Zheng Li")
    }

    @Test
    func seedExtractorUsesRuleBasedExtractionForCoreFields() async throws {
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "pdf-seed-pipeline",
            lines: [
                "Published as a conference paper at ICLR 2026",
                "TOWARDS A FOUNDATION MODEL FOR CROWD-",
                "SOURCED LABEL AGGREGATION",
                "Hao Liu1, Jiacheng Liu2, Feilong Tang3, Long Chen4",
                "School of Computer Science",
                "Abstract",
                "Inferring ground truth from noisy labels is difficult.",
                "arXiv:2501.12345",
                "doi: 10.48550/arXiv.2501.12345"
            ]
        )

        let seed = await PDFSeedExtractor.extract(from: pdfURL)

        #expect(seed.title == "TOWARDS A FOUNDATION MODEL FOR CROWD- SOURCED LABEL AGGREGATION")
        #expect(seed.titleCandidates == ["TOWARDS A FOUNDATION MODEL FOR CROWD- SOURCED LABEL AGGREGATION"])
        #expect(seed.authors == "Hao Liu, Jiacheng Liu, Feilong Tang, Long Chen")
        #expect(seed.venue == "Published as a conference paper at ICLR 2026")
        #expect(seed.year == 2026)
        #expect(seed.arxivId == "2501.12345")
        #expect(seed.doi == "10.48550/arxiv.2501.12345")
        #expect(seed.abstract == "Inferring ground truth from noisy labels is difficult.")
    }

    @Test
    func seedExtractorReturnsEmptyValuesWhenNoStructuredSignalsExist() async throws {
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "pdf-seed-minimal",
            lines: [
                "hello world",
                "notes"
            ]
        )

        let seed = await PDFSeedExtractor.extract(from: pdfURL)

        #expect(seed.authors == nil)
        #expect(seed.venue == nil)
        #expect(seed.year == 0)
        #expect(seed.doi == nil)
        #expect(seed.arxivId == nil)
        #expect(seed.abstract == nil)
    }

    @Test
    func seedExtractorDoesNotTreatUppercaseCommaTitleAsAuthorLine() async throws {
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "pdf-seed-uppercase-comma-title",
            lines: [
                "arXiv:2501.13381v2 [cs.CL] 11 Feb 2025",
                "Published as a conference paper at ICLR 2025",
                "DO AS WE DO, NOT AS YOU THINK:",
                "THE CONFORMITY OF LARGE LANGUAGE MODELS",
                "Zhiyuan Weng1, Guikun Chen1, Wenguan Wang1",
                "1Zhejiang University",
                "Abstract",
                "Recent advancements in large language models."
            ]
        )

        let seed = await PDFSeedExtractor.extract(from: pdfURL)

        #expect(seed.title == "DO AS WE DO, NOT AS YOU THINK: THE CONFORMITY OF LARGE LANGUAGE MODELS")
        #expect(seed.authors == "Zhiyuan Weng, Guikun Chen, Wenguan Wang")
        #expect(seed.venue == "Published as a conference paper at ICLR 2025")
        #expect(seed.year == 2025)
        #expect(seed.arxivId == "2501.13381v2")
    }

    @Test
    func seedExtractorMergesMultiLineStylizedAuthorBlock() async throws {
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "pdf-seed-multiline-stylized-authors",
            lines: [
                "arXiv:2511.21689v1 [cs.CL] 26 Nov 2025",
                "2025-11-27",
                "ToolOrchestra: Elevating Intelligence via Efficient",
                "Model and Tool Orchestration",
                "Hongjin Su*1,2 Shizhe Diao*1 Ximing Lu1 Mingjie Liu1 Jiacheng Xu1 Xin Dong1",
                "Yonggan Fu1 Peter Belcak1 Hanrong Ye1 Hongxu Yin1 Yi Dong1 Evelina Bakhturina1",
                "Tao Yu2 Yejin Choi1 Jan Kautz1 Pavlo Molchanov1",
                "1NVIDIA, 2University of Hong Kong",
                "Abstract: Large language models are powerful generalists."
            ]
        )

        let seed = await PDFSeedExtractor.extract(from: pdfURL)

        #expect(seed.title == "ToolOrchestra: Elevating Intelligence via Efficient Model and Tool Orchestration")
        #expect(seed.authors == "Hongjin Su, Shizhe Diao, Ximing Lu, Mingjie Liu, Jiacheng Xu, Xin Dong, Yonggan Fu, Peter Belcak, Hanrong Ye, Hongxu Yin, Yi Dong, Evelina Bakhturina, Tao Yu, Yejin Choi, Jan Kautz, Pavlo Molchanov")
        #expect(seed.arxivId == "2511.21689v1")
    }

    @Test
    func seedExtractorHandlesDenseAuthorLinesWithoutCommas() async throws {
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "pdf-seed-dense-authors",
            lines: [
                "arXiv:2410.02223v2 [cs.CL] 16 Oct 2024",
                "EMBEDLLM: LEARNING COMPACT REPRESENTA-",
                "TIONS OF LARGE LANGUAGE MODELS",
                "Richard Zhuang* Tianhao Wu* Zhaojin Wen Andrew Li",
                "Jiantao Jiao Kannan Ramchandran",
                "University of California, Berkeley",
                "ABSTRACT",
                "With hundreds of thousands of language models available."
            ]
        )

        let seed = await PDFSeedExtractor.extract(from: pdfURL)

        #expect(seed.title == "EMBEDLLM: LEARNING COMPACT REPRESENTA- TIONS OF LARGE LANGUAGE MODELS")
        #expect(seed.authors == "Richard Zhuang, Tianhao Wu, Zhaojin Wen, Andrew Li, Jiantao Jiao, Kannan Ramchandran")
        #expect(seed.arxivId == "2410.02223v2")
    }

    @Test
    func seedExtractorHandlesCommaLeadingMultiLineAuthorBlock() async throws {
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "pdf-seed-comma-leading-authors",
            lines: [
                "arXiv:2409.13884v1 [cs.CL] 20 Sep 2024",
                "A Multi-LLM Debiasing Framework",
                "Deonna M. Owens†",
                ", Ryan A. Rossi‡",
                ", Sungchul Kim‡",
                ", Tong Yu‡",
                ", Franck Dernoncourt‡",
                ", Xiang Chen‡",
                "Stanford University†",
                "Adobe Research‡",
                "Abstract"
            ]
        )

        let seed = await PDFSeedExtractor.extract(from: pdfURL)

        #expect(seed.title == "A Multi-LLM Debiasing Framework")
        #expect(seed.authors == "Deonna M. Owens, Ryan A. Rossi, Sungchul Kim, Tong Yu, Franck Dernoncourt, Xiang Chen")
        #expect(seed.arxivId == "2409.13884v1")
    }

    @Test
    func seedExtractorKeepsSubtitleAndAvoidsTreatingItAsAuthorLine() async throws {
        let pdfURL = try TestSupport.makeTempTextPDF(
            named: "pdf-seed-one-prompt-subtitle",
            lines: [
                "One Prompt is not Enough:",
                "Automated Construction of a",
                "Mixture-of-Expert Prompts",
                "Ruochen Wang * 1 Sohyun An * 2 Minhao Cheng 3",
                "Tianyi Zhou 4 Sung Ju Hwang 2 Cho-Jui Hsieh 1",
                "arXiv:2407.00256v1 [cs.AI] 28 Jun 2024",
                "Abstract"
            ]
        )

        let seed = await PDFSeedExtractor.extract(from: pdfURL)

        #expect(seed.title == "One Prompt is not Enough: Automated Construction of a Mixture-of-Expert Prompts")
        #expect(seed.authors == "Ruochen Wang, Sohyun An, Minhao Cheng, Tianyi Zhou, Sung Ju Hwang, Cho-Jui Hsieh")
        #expect(seed.arxivId == "2407.00256v1")
    }
}

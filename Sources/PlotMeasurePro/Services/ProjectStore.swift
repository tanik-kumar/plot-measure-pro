import Foundation
import PDFKit

enum ProjectStoreError: LocalizedError {
    case invalidProjectFile
    case unresolvedPDF
    case unreadablePDF

    var errorDescription: String? {
        switch self {
        case .invalidProjectFile:
            return "The selected project file is not a valid PlotMeasure Pro project."
        case .unresolvedPDF:
            return "The referenced PDF could not be resolved. Re-link the PDF and try again."
        case .unreadablePDF:
            return "The PDF could not be opened."
        }
    }
}

struct ProjectStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func createProject(for pdfURL: URL, pageCount: Int) -> PDFDocumentProject {
        let bookmark = try? pdfURL.bookmarkData()
        return PDFDocumentProject(
            name: pdfURL.deletingPathExtension().lastPathComponent,
            pdfFilePath: pdfURL.path,
            pdfBookmarkData: bookmark,
            pages: (0..<pageCount).map { PDFPageMeasurement(pageIndex: $0) }
        )
    }

    func save(project: PDFDocumentProject, to url: URL) throws {
        let data = try encoder.encode(project)
        try data.write(to: url, options: .atomic)
    }

    func loadProject(from url: URL) throws -> PDFDocumentProject {
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(PDFDocumentProject.self, from: data)
        } catch {
            throw ProjectStoreError.invalidProjectFile
        }
    }

    func resolvePDFURL(for project: PDFDocumentProject) throws -> URL {
        let pathURL = URL(fileURLWithPath: project.pdfFilePath)
        if FileManager.default.fileExists(atPath: pathURL.path) {
            return pathURL
        }

        if let bookmarkData = project.pdfBookmarkData {
            var isStale = false
            let resolved = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withoutMounting],
                bookmarkDataIsStale: &isStale
            )
            if FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }

        throw ProjectStoreError.unresolvedPDF
    }

    func loadPDFDocument(for project: PDFDocumentProject) throws -> PDFDocument {
        let pdfURL = try resolvePDFURL(for: project)
        guard let document = PDFDocument(url: pdfURL) else {
            throw ProjectStoreError.unreadablePDF
        }
        return document
    }
}

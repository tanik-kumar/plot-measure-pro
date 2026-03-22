import SwiftUI

@main
struct PlotMeasureProApp: App {
    @StateObject private var viewModel = PlotMeasureProViewModel()

    var body: some Scene {
        WindowGroup("PlotMeasure Pro") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandMenu("PlotMeasure Pro") {
                Button("Open PDF…") {
                    viewModel.openPDFPanel()
                }
                .keyboardShortcut("o")

                Button("Open Project…") {
                    viewModel.openProjectPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Save Project") {
                    viewModel.saveProject()
                }
                .keyboardShortcut("s")

                Button("Export JSON Report…") {
                    viewModel.exportJSONReport()
                }

                Button("Export CSV Report…") {
                    viewModel.exportCSVReport()
                }

                Button("Export Annotated PDF…") {
                    viewModel.exportAnnotatedPDF()
                }

                Divider()

                Button("Close Shape") {
                    viewModel.closeDraftIfPossible()
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("Undo") {
                    viewModel.undo()
                }
                .keyboardShortcut("z")
                .disabled(!viewModel.hasUndo)

                Button("Redo") {
                    viewModel.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!viewModel.hasRedo)
            }

            CommandMenu("View") {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .plotMeasureZoomIn, object: nil)
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .plotMeasureZoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Fit to Page") {
                    NotificationCenter.default.post(name: .plotMeasureZoomToFit, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button("Actual Size") {
                    NotificationCenter.default.post(name: .plotMeasureZoomActualSize, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command])
            }
        }
    }
}

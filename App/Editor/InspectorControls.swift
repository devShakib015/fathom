import SwiftUI

/// Small inspector controls, shared so that every row in the panel has the
/// same rhythm. A design tool is judged on whether its inspector feels
/// consistent long before anyone reads its file format.

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.textDim)
                .tracking(0.8)
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct InspectorRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)
                .frame(width: 62, alignment: .leading)
            content
        }
    }
}

/// A number field that commits on every keystroke but does not fight the user
/// while they are mid-edit — a stepper-driven `TextField` bound straight to a
/// Double will happily rewrite "0." into "0" as it is typed.
struct NumberField: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double = 0.01
    var format: String = "%.2f"

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .focused($focused)
                // Only a focused field writes back. Without this guard the
                // field echoes every model-driven change straight back into
                // the model, which turns dragging on the canvas into a storm
                // of redundant edits.
                .onChange(of: text) { _, new in
                    guard focused, let parsed = Double(new) else { return }
                    value = min(max(parsed, range.lowerBound), range.upperBound)
                }
                .onChange(of: value) { _, new in
                    guard !focused else { return }
                    text = String(format: format, new)
                }
                .onAppear { text = String(format: format, value) }
            Stepper(label, value: $value, in: range, step: step)
                .labelsHidden()
                .onChange(of: value) { _, new in text = String(format: format, new) }
        }
    }
}

struct ColorRow: View {
    let label: String
    @Binding var spec: ColorSpec

    // Pulled out with an explicit type: inline, the conversion between
    // ColorSpec and Color inside a multi-child ViewBuilder is enough to make
    // the type checker give up entirely.
    private var colorBinding: Binding<Color> {
        Binding(get: { spec.opaqueColor },
                set: { new in
                    var updated = ColorSpec(new)
                    updated.opacity = spec.opacity   // the slider owns opacity, not the picker
                    spec = updated
                })
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { spec.opacity }, set: { spec.opacity = $0 })
    }

    var body: some View {
        InspectorRow(label: label) {
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 34)
            Slider(value: opacityBinding, in: 0...1)
            Text(String(format: "%.0f%%", spec.opacity * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.textDim)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

/// A colour row for a value that may be absent, e.g. a shape's fill.
struct OptionalColorRow: View {
    let label: String
    @Binding var spec: ColorSpec?
    let fallback: ColorSpec

    private var isOn: Binding<Bool> {
        Binding(get: { spec != nil },
                set: { spec = $0 ? (spec ?? fallback) : nil })
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { (spec ?? fallback).opaqueColor },
                set: { new in
                    var updated = ColorSpec(new)
                    updated.opacity = spec?.opacity ?? 1
                    spec = updated
                })
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { spec?.opacity ?? 1 },
                set: { spec?.opacity = $0 })
    }

    var body: some View {
        InspectorRow(label: label) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            if spec == nil {
                Text("None")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textDim)
                Spacer()
            } else {
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 34)
                Slider(value: opacityBinding, in: 0...1)
            }
        }
    }
}

extension Binding where Value == String? {
    /// Lets an optional string drive a `TextField` without every call site
    /// growing its own get/set pair.
    func replacingNil(with placeholder: String) -> Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? placeholder },
            set: { wrappedValue = $0 }
        )
    }
}

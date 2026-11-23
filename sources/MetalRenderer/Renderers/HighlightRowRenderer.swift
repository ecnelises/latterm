//
//  HighlightRowRenderer.swift
//  Latterm
//

import Foundation
import Metal
import simd

@objc(iTermHighlightRowRendererTransientState)
final class HighlightRowRendererTransientState: iTermMetalCellRendererTransientState {
    fileprivate struct Highlight {
        var color: vector_float4
        var row: Int32
    }

    fileprivate var highlights: [Highlight] = []

    override func writeDebugInfo(toFolder folder: URL) {
        super.writeDebugInfo(toFolder: folder)
        var text = ""
        for h in highlights {
            text += "color=(\(h.color.x), \(h.color.y), \(h.color.z), \(h.color.w)) row=\(h.row)\n"
        }
        try? text.write(to: folder.appendingPathComponent("state.txt"),
                        atomically: false,
                        encoding: .utf8)
    }

    @objc(setOpacity:color:row:)
    func setOpacity(_ opacity: CGFloat, color: vector_float3, row: Int32) {
        let alpha = Float(opacity)
        highlights.append(
            Highlight(
                color: SIMD4<Float>(color.x * alpha, color.y * alpha, color.z * alpha, alpha),
                row: row
            )
        )
    }
}

@objc(iTermHighlightRowRenderer)
final class HighlightRowRenderer: NSObject, iTermMetalCellRendererProtocol {
    private let cellRenderer: iTermMetalCellRenderer
    private let colorPool: iTermMetalBufferPool

    @objc(initWithDevice:)
    init?(device: MTLDevice) {
        guard let renderer = iTermMetalCellRenderer(
            device: device,
            vertexFunctionName: "iTermHighlightRowVertexShader",
            fragmentFunctionName: "iTermHighlightRowFragmentShader",
            blending: iTermMetalBlending.compositeSourceOver(),
            piuElementSize: 0,
            transientStateClass: HighlightRowRendererTransientState.self
        ) else {
            return nil
        }
        self.cellRenderer = renderer
        self.colorPool = iTermMetalBufferPool(device: device,
                                              bufferSize: MemoryLayout<vector_float4>.stride)
        super.init()
    }

    @available(*, unavailable)
    override init() {
        it_fatalError("Use init(device:)")
    }

    var rendererDisabled: Bool { false }

    func createTransientStateStat() -> iTermMetalFrameDataStat {
        .pqCreateCursorGuideTS
    }

    func createTransientState(forCellConfiguration configuration: iTermCellRenderConfiguration,
                              commandBuffer: MTLCommandBuffer) -> iTermMetalRendererTransientState? {
        cellRenderer.createTransientState(forCellConfiguration: configuration,
                                          commandBuffer: commandBuffer)
    }

    func draw(with frameData: iTermMetalFrameData,
              transientState: iTermMetalCellRendererTransientState) {
        guard let tState = transientState as? HighlightRowRendererTransientState,
              let renderEncoder = frameData.renderEncoder else {
            return
        }
        let gridSize = tState.cellConfiguration.gridSize
        let cellSize = tState.cellConfiguration.cellSize
        let top = tState.margins.top
        let left = tState.margins.left
        let right = tState.margins.right

        for var highlight in tState.highlights {
            let rect = CGRect(
                x: 0,
                y: CGFloat(gridSize.height - highlight.row - 1) * cellSize.height + top,
                width: cellSize.width * CGFloat(gridSize.width) + left + right,
                height: cellSize.height
            )
            let vertexBuffer = cellRenderer.newQuad(withFrame: rect,
                                                    textureFrame: .zero,
                                                    poolContext: tState.poolContext)
            let colorBuffer = withUnsafePointer(to: &highlight.color) { ptr in
                colorPool.requestBuffer(from: tState.poolContext,
                                        withBytes: ptr,
                                        checkIfChanged: true)
            }
            cellRenderer.draw(
                with: tState,
                renderEncoder: renderEncoder,
                numberOfVertices: 6,
                numberOfPIUs: 0,
                vertexBuffers: [NSNumber(value: iTermVertexInputIndexVertices.rawValue): vertexBuffer],
                fragmentBuffers: [NSNumber(value: iTermFragmentBufferIndexMarginColor.rawValue): colorBuffer],
                textures: [:]
            )
        }
    }
}

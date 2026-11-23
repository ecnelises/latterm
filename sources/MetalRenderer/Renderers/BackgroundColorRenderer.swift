//
//  BackgroundColorRenderer.swift
//  Latterm
//

import Foundation
import Metal
import simd

@objc(iTermBackgroundColorRendererTransientState)
final class BackgroundColorRendererTransientState: iTermMetalCellRendererTransientState {
    private static let segmentCapacity = 1024

    @objc var defaultBackgroundColor = vector_float4(0, 0, 0, 0)
    @objc var verticalOffset: Float = 0

    fileprivate var segments: [[iTermBackgroundColorPIU]] = []

    @objc(setColorRLEs:count:row:repeatingRows:omitClear:)
    func setColorRLEs(_ rles: UnsafePointer<iTermMetalBackgroundColorRLE>,
                      count: Int,
                      row: Int32,
                      repeatingRows: Int32,
                      omitClear: Bool) {
        guard count > 0 else {
            return
        }
        let cellSize = SIMD2<Float>(Float(cellConfiguration.cellSize.width),
                                    Float(cellConfiguration.cellSize.height))
        let height = cellConfiguration.gridSize.height
        let yOffset = verticalOffset + cellSize.y * Float(height - row - repeatingRows)

        for i in 0..<count {
            let rle = rles[i]
            if omitClear && rle.color.w == 0 {
                continue
            }
            let piu = iTermBackgroundColorPIU(
                offset: SIMD2<Float>(cellSize.x * Float(rle.origin), yOffset),
                runLength: rle.count,
                numRows: UInt16(clamping: repeatingRows),
                color: rle.color,
                isDefault: rle.isDefault
            )
            if segments.isEmpty || segments[segments.count - 1].count >= Self.segmentCapacity {
                var nextSeg: [iTermBackgroundColorPIU] = []
                nextSeg.reserveCapacity(Self.segmentCapacity)
                nextSeg.append(piu)
                segments.append(nextSeg)
            } else {
                segments[segments.count - 1].append(piu)
            }
        }
    }
}

@objc(iTermBackgroundColorRenderer)
final class BackgroundColorRenderer: NSObject, iTermMetalCellRendererProtocol, iTermMetalDebugInfoFormatter {
    private let nonblendingRenderer: iTermMetalCellRenderer
    private let compositeOverRenderer: iTermMetalCellRenderer
    private let infoPool: iTermMetalBufferPool
    private let suppressedRegionVertexBufferPool: iTermMetalBufferPool
    private let piuPool: iTermMetalMixedSizeBufferPool

    @objc var mode: iTermBackgroundColorRendererMode = iTermBackgroundColorRendererModeAll

    @objc(initWithDevice:)
    init?(device: MTLDevice) {
        let elemSize = MemoryLayout<iTermBackgroundColorPIU>.stride
        guard let nonblending = iTermMetalCellRenderer(
            device: device,
            vertexFunctionName: "iTermBackgroundColorVertexShader",
            fragmentFunctionName: "iTermBackgroundColorFragmentShader",
            blending: nil,
            piuElementSize: elemSize,
            transientStateClass: BackgroundColorRendererTransientState.self
        ),
        let compositeOver = iTermMetalCellRenderer(
            device: device,
            vertexFunctionName: "iTermBackgroundColorVertexShader",
            fragmentFunctionName: "iTermBackgroundColorFragmentShader",
            blending: iTermMetalBlending.premultipliedCompositing(),
            piuElementSize: elemSize,
            transientStateClass: BackgroundColorRendererTransientState.self
        ) else {
            return nil
        }

        self.nonblendingRenderer = nonblending
        self.compositeOverRenderer = compositeOver
        self.suppressedRegionVertexBufferPool = iTermMetalBufferPool(
            device: device,
            bufferSize: MemoryLayout<iTermVertex>.stride * 6
        )
        self.piuPool = iTermMetalMixedSizeBufferPool(
            device: device,
            capacity: 512,
            name: "background color PIU"
        )
        self.infoPool = iTermMetalBufferPool(
            device: device,
            bufferSize: MemoryLayout<iTermMetalBackgroundColorInfo>.stride
        )
        super.init()
        nonblendingRenderer.formatterDelegate = self
        compositeOverRenderer.formatterDelegate = self
    }

    @available(*, unavailable)
    override init() {
        it_fatalError("Use init(device:)")
    }

    var rendererDisabled: Bool { false }

    func createTransientStateStat() -> iTermMetalFrameDataStat {
        .pqCreateBackgroundColorTS
    }

    private func renderer(for configuration: iTermCellRenderConfiguration) -> iTermMetalCellRenderer {
        configuration.hasBackgroundImage ? compositeOverRenderer : nonblendingRenderer
    }

    func createTransientState(forCellConfiguration configuration: iTermCellRenderConfiguration,
                              commandBuffer: MTLCommandBuffer) -> iTermMetalRendererTransientState? {
        let cellRenderer = renderer(for: configuration)
        guard let transientState = cellRenderer.createTransientState(
            forCellConfiguration: configuration,
            commandBuffer: commandBuffer
        ) as? BackgroundColorRendererTransientState else {
            return nil
        }
        transientState.vertexBuffer = cellRenderer.newQuad(of: configuration.cellSize,
                                                           poolContext: transientState.poolContext)
        transientState.vertexBuffer.label = "Vertices"
        return transientState
    }

    private func infoBuffer(for tState: BackgroundColorRendererTransientState) -> MTLBuffer {
        var info = iTermMetalBackgroundColorInfo()
        info.defaultBackgroundColor = tState.defaultBackgroundColor
        info.mode = mode
        let buffer = withUnsafePointer(to: &info) { ptr in
            infoPool.requestBuffer(from: tState.poolContext,
                                   withBytes: ptr,
                                   checkIfChanged: true)
        }
        buffer.label = "BG color info"
        return buffer
    }

    func draw(with frameData: iTermMetalFrameData,
              transientState: iTermMetalCellRendererTransientState) {
        guard let tState = transientState as? BackgroundColorRendererTransientState,
              let renderEncoder = frameData.renderEncoder else {
            return
        }
        let infoBuf = infoBuffer(for: tState)
        let cellRenderer = renderer(for: tState.cellConfiguration)

        for segment in tState.segments where !segment.isEmpty {
            let count = segment.count
            let byteLen = count * MemoryLayout<iTermBackgroundColorPIU>.stride
            let piuBuffer = segment.withUnsafeBytes { raw in
                piuPool.requestBuffer(from: tState.poolContext,
                                      size: byteLen,
                                      bytes: raw.baseAddress!)
            }
            piuBuffer.label = "PIUs"
            cellRenderer.draw(
                with: tState,
                renderEncoder: renderEncoder,
                numberOfVertices: 6,
                numberOfPIUs: count,
                vertexBuffers: [
                    NSNumber(value: iTermVertexInputIndexVertices.rawValue): tState.vertexBuffer,
                    NSNumber(value: iTermVertexInputIndexPerInstanceUniforms.rawValue): piuBuffer,
                    NSNumber(value: iTermVertexInputIndexOffset.rawValue): tState.offsetBuffer,
                    NSNumber(value: iTermVertexInputIndexDefaultBackgroundColorInfo.rawValue): infoBuf
                ],
                fragmentBuffers: [:],
                textures: [:]
            )
        }

        if tState.suppressedBottomHeight > 0 {
            let suppressedBottomPx = CGFloat(
                UInt(max(0, tState.suppressedBottomHeight * tState.cellConfiguration.scale - tState.margins.top))
            )
            let maxX = Float(tState.cellConfiguration.cellSize.width * CGFloat(tState.cellConfiguration.gridSize.width))
            let maxY = Float(suppressedBottomPx)
            let bottomRight = iTermVertex(position: SIMD2<Float>(maxX, 0), textureCoordinate: SIMD2<Float>(1, 1))
            let bottomLeft = iTermVertex(position: SIMD2<Float>(0, 0), textureCoordinate: SIMD2<Float>(0, 1))
            let topLeft = iTermVertex(position: SIMD2<Float>(0, maxY), textureCoordinate: SIMD2<Float>(0, 0))
            let topRight = iTermVertex(position: SIMD2<Float>(maxX, maxY), textureCoordinate: SIMD2<Float>(1, 0))
            let vertices: [iTermVertex] = [
                bottomRight, bottomLeft, topLeft,
                bottomRight, topLeft, topRight
            ]
            let vertexBuffer = vertices.withUnsafeBytes { raw in
                suppressedRegionVertexBufferPool.requestBuffer(from: tState.poolContext,
                                                               withBytes: raw.baseAddress!,
                                                               checkIfChanged: true)
            }
            var piu = iTermBackgroundColorPIU(
                offset: .zero,
                runLength: 1,
                numRows: 1,
                color: SIMD4<Float>(tState.defaultBackgroundColor.x,
                                    tState.defaultBackgroundColor.y,
                                    tState.defaultBackgroundColor.z,
                                    0),
                isDefault: 1
            )
            let piuBuffer = withUnsafePointer(to: &piu) { ptr in
                piuPool.requestBuffer(from: tState.poolContext,
                                      size: MemoryLayout<iTermBackgroundColorPIU>.stride,
                                      bytes: ptr)
            }
            piuBuffer.label = "PIUs for suppressed region"

            let savedTop = tState.suppressedTopHeight
            let savedBottom = tState.suppressedBottomHeight
            tState.suppressedTopHeight = 0
            tState.suppressedBottomHeight = 0

            cellRenderer.draw(
                with: tState,
                renderEncoder: renderEncoder,
                numberOfVertices: 6,
                numberOfPIUs: 1,
                vertexBuffers: [
                    NSNumber(value: iTermVertexInputIndexVertices.rawValue): vertexBuffer,
                    NSNumber(value: iTermVertexInputIndexPerInstanceUniforms.rawValue): piuBuffer,
                    NSNumber(value: iTermVertexInputIndexOffset.rawValue): tState.offsetBuffer,
                    NSNumber(value: iTermVertexInputIndexDefaultBackgroundColorInfo.rawValue): infoBuf
                ],
                fragmentBuffers: [:],
                textures: [:]
            )

            tState.suppressedTopHeight = savedTop
            tState.suppressedBottomHeight = savedBottom
        }
    }

    @objc(writeVertexBuffer:index:toFolder:)
    func writeVertexBuffer(_ buffer: MTLBuffer, index: UInt, toFolder folder: URL) {
        guard index == UInt(iTermVertexInputIndexPerInstanceUniforms.rawValue) else {
            return
        }
        let stride = MemoryLayout<iTermBackgroundColorPIU>.stride
        let count = buffer.length / stride
        let pius = buffer.contents().assumingMemoryBound(to: iTermBackgroundColorPIU.self)
        var out = ""
        for i in 0..<count {
            let p = pius[i]
            out += "offset=(\(p.offset.x), \(p.offset.y)) runLength=\(p.runLength) numRows=\(p.numRows) color=(\(p.color.x), \(p.color.y), \(p.color.z), \(p.color.w))\n"
        }
        let url = folder.appendingPathComponent("vertexBuffer.iTermVertexInputIndexPerInstanceUniforms.txt")
        try? out.write(to: url, atomically: false, encoding: .utf8)
    }
}

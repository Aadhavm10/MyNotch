// Drag-to-open detector approach adapted from NotchDrop (https://github.com/Lakr233/NotchDrop), MIT, Copyright (c) 2024 Lakr Aream.

import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @Bindable var vm: NotchViewModel

    /// Extra margin around the closed notch that still catches file drags.
    private let dropDetectorRange: CGFloat = 36

    /// Coordinate space that drop locations and the Tray's format chip frames share.
    static let coordinateSpace = "notchRoot"

    var body: some View {
        ZStack(alignment: .top) {
            if vm.status != .open, vm.isDragging {
                dragDetector
            }
            notch
        }
        .coordinateSpace(.named(Self.coordinateSpace))
        .onDrop(of: [.fileURL, .data], delegate: NotchDropDelegate(vm: vm))
        .onChange(of: vm.dropTargeting) { _, targeting in
            if targeting {
                if vm.settings.general.openTrayOnFileDrag { vm.open(tab: .tray) }
            } else if !vm.openRect.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation) {
                vm.close()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(vm.isHidden ? 0 : 1)
        .animation(vm.animation, value: vm.status)
        .animation(vm.animation, value: vm.tab)
        .animation(vm.animation, value: vm.liveActivity)
        .animation(vm.animation, value: vm.settings.layout)
        .environment(\.colorScheme, .dark)
    }

    private var notch: some View {
        let size = vm.currentSize
        return ZStack(alignment: .top) {
            if vm.status == .open {
                OpenNotchView(vm: vm)
                    .padding(.horizontal, vm.topCornerRadius)
                    .transition(
                        .scale(scale: 0.85, anchor: .top)
                            .combined(with: .opacity)
                            .animation(vm.animation)
                    )
            } else {
                ClosedNotchView(vm: vm)
                    .padding(.horizontal, vm.topCornerRadius)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
        .frame(width: size.width + vm.topCornerRadius * 2, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(NotchShape(topCornerRadius: vm.topCornerRadius, bottomCornerRadius: vm.bottomCornerRadius))
        .shadow(color: .black.opacity(vm.status == .closed ? 0 : 0.55), radius: 16, y: 4)
        .contentShape(NotchShape(topCornerRadius: vm.topCornerRadius, bottomCornerRadius: vm.bottomCornerRadius))
    }

    /// Nearly invisible rect around the closed notch so drags are detected before reaching it.
    /// Only shown mid-drag: it blocks clicks to the windows underneath (see `isDragging`).
    private var dragDetector: some View {
        Rectangle()
            .fill(Color.black.opacity(0.001))
            .frame(
                width: vm.closedSize.width + dropDetectorRange * 2,
                height: vm.closedSize.height + dropDetectorRange
            )
    }
}

/// One drop target for the whole notch: a drop on one of the Tray's format chips converts the
/// files, anywhere else keeps them in the Tray. (Nested `.onDrop`s would flip `dropTargeting` off
/// over the chips, and the notch would close mid-drag.)
private struct NotchDropDelegate: DropDelegate {
    let vm: NotchViewModel

    func dropEntered(info: DropInfo) {
        vm.dropTargeting = true
        updateHover(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateHover(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info _: DropInfo) {
        vm.dropTargeting = false
        vm.hoveredConvertFormat = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL, .data])
        if let format = vm.hoveredConvertFormat {
            vm.converter.convert(providers, to: format)
        } else {
            vm.tab = .tray
            vm.tray.load(providers)
        }
        vm.hoveredConvertFormat = nil
        vm.dropTargeting = false
        return true
    }

    private func updateHover(_ info: DropInfo) {
        let hovered = vm.convertChipFrames.first { $0.value.contains(info.location) }?.key
        if hovered != vm.hoveredConvertFormat {
            vm.hoveredConvertFormat = hovered
            if hovered != nil { Haptics.tap() }
        }
    }
}

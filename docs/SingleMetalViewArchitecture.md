# Single Metal View Architecture for TitledFluxDiffView

## Overview

This document describes a comprehensive redesign of the diff viewing system to use a **single Metal view** for rendering all diff content. This approach eliminates the fundamental issues with SwiftUI's `ScrollView` and `LazyVStack` that have caused persistent scrolling problems (scrollbar jumping, height estimation issues, content gaps).

## Current Architecture Problems

### What We Have Now
```
TrajectoryView
└── SwiftUI ScrollView
    └── LazyVStack (spacing: 16)
        └── ForEach(diffs)
            └── FileDiffSection
                ├── SwiftUI Header (HStack)
                └── TiledFluxDiffView
                    └── [VStack/LazyVStack of tiles]
                        └── TileFluxDiffView (per tile)
                            └── MetalDiffView (NSViewRepresentable)
```

### Why It Fails
1. **SwiftUI Height Estimation**: `LazyVStack` estimates content height before views are created. When actual heights differ from estimates, the scrollbar jumps.
2. **Multiple Metal Views**: Each tile creates its own `MTKView`, `FluxRenderer`, and `FluxViewModel`. During fast scrolling, rapid creation/destruction causes:
   - Visual glitches when tiles aren't ready in time
   - Memory pressure from allocating/deallocating Metal resources
   - Context leaks from multiple Metal device/queue access
3. **Height Mismatch**: Parent frame heights vs internal calculated heights cause spacing issues
4. **Scroll Position Loss**: SwiftUI recycles views during scroll, potentially losing scroll position

### Previous Fix Attempts (All Reverted)
1. **VirtualizedScrollView**: Pre-calculated heights for SwiftUI - didn't solve estimation issues
2. **NSScrollView Replacement**: Snapshot caching - complexity didn't solve core issue
3. **UnifiedDiffScrollView**: Prototype of single Metal view - incomplete implementation

## Proposed Architecture: Single Metal View

### High-Level Design
```
TrajectoryView
└── UnifiedDiffPanel (NSViewRepresentable)
    └── NSScrollView (AppKit, deterministic)
        └── NSView (document view, sized to total content height)
            └── UnifiedMetalDiffView (MTKView, frame fills document)
                └── FluxRenderer (shared)
                └── UnifiedDiffViewModel (manages all sections)
                    └── SectionLayout[] (pre-computed positions)
```

### Key Principles
1. **One Metal View**: A single `MTKView` renders ALL diff content for all files
2. **AppKit Scrolling**: `NSScrollView` provides deterministic, reliable scrolling
3. **Virtual Rendering**: Only generate instances for visible lines (existing pattern)
4. **Metal File Headers**: Render file headers IN Metal, not SwiftUI (unified rendering)
5. **Pre-computed Layout**: All section/line positions calculated upfront

## Detailed Component Design

### 1. UnifiedDiffPanel (SwiftUI Wrapper)
```swift
struct UnifiedDiffPanel: NSViewRepresentable {
    let diffs: [(patch: String, language: String?, filename: String?)]
    let sessionId: String
    @Binding var scrollToFile: (sessionId: String, filename: String)?

    func makeNSView(context: Context) -> NSScrollView { ... }
    func updateNSView(_ scrollView: NSScrollView, context: Context) { ... }
}
```
- Minimal SwiftUI interface
- Creates and manages the NSScrollView + Metal view hierarchy
- Handles `scrollToFile` navigation
- Passes diffs to view model when they change

### 2. UnifiedMetalDiffView (MTKView subclass)
```swift
@MainActor
class UnifiedMetalDiffView: MTKView {
    let renderer: FluxRenderer
    let viewModel: UnifiedDiffViewModel

    // Scroll state
    var scrollOffsetY: CGFloat = 0  // Set by NSScrollView observation
    var scrollOffsetX: CGFloat = 0  // For horizontal scroll (long lines)

    // Selection state
    var selectionStart: GlobalTextPosition?
    var selectionEnd: GlobalTextPosition?

    func updateContent(diffs: [...], sessionId: String) { ... }
    func handleScrollChanged(_ newOffset: CGPoint) { ... }
}
```
- Single MTKView for all content
- Owns one FluxRenderer and one UnifiedDiffViewModel
- Handles mouse events for selection (translates to global positions)
- Frame sized to total content height (or viewport, with scroll offset in render)

### 3. UnifiedDiffViewModel
```swift
@MainActor
class UnifiedDiffViewModel: ObservableObject {
    // Layout data
    private(set) var sections: [DiffSection] = []
    private(set) var totalContentHeight: CGFloat = 0

    // Global line array (all files concatenated)
    private(set) var globalLines: [GlobalLine] = []

    // Rendering
    private let lineManager = LineManager()
    private var charColorCache: [UUID: [SIMD4<Float>]] = [:]

    func updateSections(diffs: [...], sessionId: String) { ... }
    func visibleLines(viewportTop: CGFloat, viewportBottom: CGFloat) -> Range<Int> { ... }
    func generateInstances(visibleRange: Range<Int>, renderer: FluxRenderer) -> ([InstanceData], [RectInstance]) { ... }
}

struct DiffSection {
    let index: Int
    let filename: String?
    let language: String?
    let diffResult: DiffResult
    let globalLineStart: Int    // First global line index
    let globalLineEnd: Int      // Last global line index (exclusive)
    let yOffset: CGFloat        // Y position of this section
    let headerHeight: CGFloat   // 35pt for file header
    let contentHeight: CGFloat  // Height of diff lines
    var totalHeight: CGFloat { headerHeight + contentHeight }
}

struct GlobalLine {
    let sectionIndex: Int
    let localLineIndex: Int    // Index within section
    let type: GlobalLineType   // .fileHeader, .diffLine, .spacer
    let yOffset: CGFloat       // Global Y position
}

enum GlobalLineType {
    case fileHeader(DiffSection)
    case diffLine(DiffLine)
    case spacer
}
```

### 4. Rendering Pipeline

#### Frame 1: Layout Computation (on diffs change)
```
1. For each diff file:
   a. Parse patch → DiffResult
   b. Calculate content height = lineCount × lineHeight
   c. Create DiffSection with yOffset (cumulative)
   d. Create GlobalLine entries for:
      - File header (35pt)
      - Each diff line
      - Spacer lines between files (16pt × 3)

2. Store globalLines array
3. Build LineManager with total line count
4. totalContentHeight = last section's yOffset + height + padding
```

#### Frame N: Render (on scroll/resize)
```
1. Receive scroll offset from NSScrollView
2. Calculate visible range:
   visibleTop = scrollY
   visibleBottom = scrollY + viewportHeight
   visibleLines = lineManager.visibleLineRange(visibleTop, visibleBottom)

3. Generate instances for visible lines:
   For each globalLine in visibleLines:
     switch globalLine.type:
       case .fileHeader(section):
         → Generate header background rect
         → Generate header text instances (M/A indicator, filename, +N -M)
       case .diffLine(line):
         → Generate line background (if added/removed)
         → Generate gutter separator
         → Generate line numbers
         → Generate diff highlights (tokenChanges)
         → Generate selection highlight
         → Generate text instances with syntax colors
       case .spacer:
         → (no rendering, just spacing)

4. Update renderer with instances + rects
5. Draw Metal frame
```

### 5. Handling Metal Texture Limits

The key insight: **we don't need huge textures**. We only render what's visible.

- Metal drawable size = viewport size (e.g., 800×600 points)
- At 3x Retina = 2400×1800 pixels (well under 16384 limit)
- Content extends beyond viewport but is handled by:
  1. Scrolling: NSScrollView handles position
  2. Virtualization: Only visible lines generate instances
  3. Camera offset: FluxRenderer.uniforms.cameraY offsets rendering

The "tiling" was solving a problem that doesn't exist when rendering is virtualized. We never need a texture taller than the viewport.

### 6. Selection Model
```swift
struct GlobalTextPosition: Equatable {
    let globalLineIndex: Int
    let charIndex: Int
}

// In UnifiedMetalDiffView:
func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let scrollY = enclosingScrollView?.documentVisibleRect.origin.y ?? 0

    // Convert to global line position
    let globalY = point.y + scrollY
    let globalLineIndex = viewModel.lineManager.lineIndex(at: Float(globalY))

    // Calculate char index
    let localY = globalY - viewModel.globalLines[globalLineIndex].yOffset
    let charIndex = Int((point.x - gutterWidth) / monoAdvance)

    selectionStart = GlobalTextPosition(globalLineIndex: globalLineIndex, charIndex: charIndex)
    selectionEnd = selectionStart
}

func getSelectedText() -> String? {
    // Iterate from selectionStart to selectionEnd
    // Extract text from appropriate DiffLines
}
```

### 7. File Header Rendering in Metal

Instead of SwiftUI headers, render in Metal:
```swift
func generateHeaderInstances(section: DiffSection, at y: CGFloat) -> ([InstanceData], [RectInstance]) {
    var instances: [InstanceData] = []
    var rects: [RectInstance] = []

    // Background
    rects.append(RectInstance(
        origin: [0, Float(y)],
        size: [1500, Float(section.headerHeight)],
        color: AppColors.diffEditorFileHeaderBg.simd4
    ))

    // M/A indicator
    let indicator = section.isNewFile ? "A" : "M"
    let indicatorColor = section.isNewFile ? addedIndicatorColor : modifiedIndicatorColor
    instances.append(contentsOf: renderText(indicator, at: (12, y + baseline), color: indicatorColor))

    // Filename
    instances.append(contentsOf: renderText(section.filename ?? "Unknown", at: (36, y + baseline), color: headerTextColor))

    // +N -M stats
    // ... similar pattern

    return (instances, rects)
}
```

## Implementation Plan

### Phase 1: Core Infrastructure
1. Create `UnifiedDiffViewModel` with section layout
2. Create `GlobalLine` abstraction
3. Implement `generateInstances` for diff lines (reuse FluxViewModel logic)

### Phase 2: Metal View
1. Create `UnifiedMetalDiffView` class
2. Integrate with existing `FluxRenderer`
3. Implement scroll handling (observe NSScrollView)

### Phase 3: File Headers in Metal
1. Add header rendering to instance generation
2. Match current SwiftUI header appearance exactly
3. Test visual consistency

### Phase 4: NSScrollView Integration
1. Create `UnifiedDiffPanel` (NSViewRepresentable)
2. Set up document view sizing
3. Implement scroll observation → Metal view update

### Phase 5: Selection & Interaction
1. Port mouse handling from MetalDiffView
2. Implement global selection model
3. Copy support

### Phase 6: Polish & Integration
1. Replace diffPanelView in TrajectoryView
2. Handle scrollToFile navigation
3. Performance tuning (prefetching, caching)

### Phase 7: Cleanup
1. Remove TiledFluxDiffView (no longer needed)
2. Remove tile-related caches
3. Simplify DiffPrecomputationService

## Performance Considerations

### Memory
- Single FluxViewModel instead of one per tile
- Shared font atlas (already implemented)
- Shared Metal command queue (already implemented)
- Syntax cache persists across scrolls (no recreation)

### CPU
- Instance generation only for visible lines (~50-100 lines max)
- Pre-computed line offsets (O(1) lookup via LineManager)
- No SwiftUI layout recalculation

### GPU
- Single draw call per frame (vs. multiple tiles)
- Instances sorted by section for cache locality
- Texture atlas for glyphs (already implemented)

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Complex implementation | Phase-by-phase approach; each phase testable |
| Regression in features | Maintain feature parity checklist |
| Performance regression | Profile before/after; benchmark with large diffs |
| Visual differences | Screenshot comparison testing |
| Selection bugs | Comprehensive unit tests for GlobalTextPosition math |

## Success Criteria

1. **No scrollbar jumping** - scrollbar size stays constant during scroll
2. **No content gaps** - no blank spaces at top/bottom during fast scroll
3. **Smooth 60fps scrolling** - no stuttering on large diffs (1000+ lines)
4. **Feature parity** - selection, copy, horizontal scroll, syntax highlighting
5. **Memory stability** - no memory growth during extended use

## Appendix: File Structure

```
jules/Flux/
├── UnifiedDiffPanel.swift        # NEW: SwiftUI wrapper
├── UnifiedMetalDiffView.swift    # NEW: Single Metal view
├── UnifiedDiffViewModel.swift    # NEW: Multi-section view model
├── FluxRenderer.swift            # EXISTING: Metal rendering (unchanged)
├── FluxViewModel.swift           # EXISTING: Reference for instance generation
├── LineManager.swift             # EXISTING: Line layout cache
├── FontAtlasManager.swift        # EXISTING: Font rendering
└── ...
```

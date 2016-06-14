/**
 * Tae Won Ha - http://taewon.de - @hataewon
 * See LICENSE
 */

import Cocoa
import RxSwift

struct RowFragment: CustomStringConvertible {
  
  static let null = RowFragment(row: -1, range: 0...0)
  
  let row: Int
  let range: Range<Int>

  var description: String {
    return "RowFragment<\(row): \(range)>"
  }
  
  init(row: Int, range: Range<Int>) {
    self.row = row
    self.range = range
  }
  
  init(position: Position) {
    self.row = position.row
    self.range = position.column...position.column
  }

  func canBeAddedTo(rowFragment rowFrag: RowFragment) -> Bool {
    guard self.row == rowFrag.row else {
      return false
    }
    
    let rangeInclBorder = min(self.range.startIndex - 1, 0)...self.range.endIndex
    if rangeInclBorder.contains(rowFrag.range.startIndex) || rangeInclBorder.contains(rowFrag.range.endIndex - 1) {
      return true
    }

    return false
  }

  func union(rowFrag: RowFragment) -> RowFragment {
    return RowFragment(
      row: self.row,
      range: min(self.range.startIndex, rowFrag.range.startIndex)..<max(self.range.endIndex, rowFrag.range.endIndex)
    )
  }
}

public class NeoVimView: NSView {
  
  public var delegate: NeoVimViewDelegate?

  private let qDispatchMainQueue = dispatch_get_main_queue()
  private let qLineGap = CGFloat(2)
  
  private var foregroundColor = Int32(bitPattern: UInt32(0xFF000000))
  private var backgroundColor = Int32(bitPattern: UInt32(0xFFFFFFFF))
  private var font = NSFont(name: "Menlo", size: 13)!
  
  private let xpc: NeoVimXpc
  private let drawer = TextDrawer()
  
  private var cellSize: CGSize = CGSizeMake(0, 0)

  private let grid = Grid()
  private var rowFragmentsToDraw: [RowFragment] = []

  init(frame rect: NSRect = CGRect.zero, xpc: NeoVimXpc) {
    self.xpc = xpc
    super.init(frame: rect)

    // hard-code some stuff
    let attrs = [ NSFontAttributeName: self.font ]
    let width = ceil(" ".sizeWithAttributes(attrs).width)
    let height = ceil(self.font.ascender - self.font.descender + self.font.leading) + qLineGap
    self.cellSize = CGSizeMake(width, height)
  }
  
  override public func keyDown(theEvent: NSEvent) {
    self.xpc.vimInput(theEvent.charactersIgnoringModifiers!)
  }
  
  override public func drawRect(dirtyRect: NSRect) {
    let context = NSGraphicsContext.currentContext()!.CGContext

    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextDrawingMode(context, .Fill);

    self.rowFragmentsToDraw.forEach { rowFrag in
      let string = self.grid.cells[rowFrag.row][rowFrag.range].reduce("") { $0 + $1.string }

      let positions = rowFrag.range
        // filter out the put(0, 0)s (after a wide character)
        .filter { self.grid.cells[rowFrag.row][$0].string.characters.count > 0 }
        .map { self.originOnView(rowFrag.row, column: $0) }

      ColorUtils.colorFromCode(self.backgroundColor).set()
      let backgroundRect = CGRect(x: positions[0].x, y: positions[0].y,
                                  width: positions.last!.x + self.cellSize.width, height: self.cellSize.height)
      NSRectFill(backgroundRect)

      ColorUtils.colorFromCode(self.foregroundColor).set()
      let glyphPositions = positions.map { CGPoint(x: $0.x, y: $0.y + qLineGap) }
      self.drawer.drawString(
        string, positions: UnsafeMutablePointer(glyphPositions),
        font: self.font, foreground: self.foregroundColor, background: self.backgroundColor,
        context: context
      )

      NSColor.redColor().set()
      positions.forEach { NSRectFill(CGRect(origin: $0, size: CGSize(width: 1, height: 1))) }
    }

    self.rowFragmentsToDraw = []
  }

  private func originOnView(row: Int, column: Int) -> CGPoint {
    return CGPoint(
      x: CGFloat(column) * self.cellSize.width,
      y: self.frame.size.height - CGFloat(row) * self.cellSize.height - self.cellSize.height
    )
  }

  private func gui(call: () -> Void) {
    dispatch_async(qDispatchMainQueue, call)
  }
  
  required public init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

extension NeoVimView: NeoVimUiBridgeProtocol {

  public func resizeToWidth(width: Int32, height: Int32) {
    let rectSize = CGSizeMake(
      CGFloat(width) * self.cellSize.width,
      CGFloat(height) * self.cellSize.height
    )
    
    gui {
//      Swift.print("### resize to \(width):\(height)")
      self.grid.resize(Size(width: Int(width), height: Int(height)))
      self.delegate?.resizeToSize(rectSize)
    }
  }
  
  public func clear() {
    gui {
      Swift.print("### clear")
      self.grid.clear()
      self.needsDisplay = true
    }
  }
  
  public func eolClear() {
    gui {
//      Swift.print("### eol clear")
      self.grid.eolClear()

      let origin = self.originOnView(self.grid.position.row, column: self.grid.position.column)
      let size = CGSize(
        width: CGFloat(self.grid.region.right - self.grid.position.column + 1) * self.cellSize.width,
        height: self.cellSize.height
      )
      let rect = CGRect(origin: origin, size: size)
      Swift.print("### eol clear: \(rect)")
      self.setNeedsDisplayInRect(rect)
    }
  }
  
  public func cursorGotoRow(row: Int32, column: Int32) {
    gui {
//      Swift.print("### goto: \(row):\(column)")
      self.grid.goto(Position(row: Int(row), column: Int(column)))
    }
  }
  
  public func updateMenu() {
    //    Swift.print("### update menu")
  }
  
  public func busyStart() {
    //    Swift.print("### busy start")
  }
  
  public func busyStop() {
    //    Swift.print("### busy stop")
  }
  
  public func mouseOn() {
    //    Swift.print("### mouse on")
  }
  
  public func mouseOff() {
    //    Swift.print("### mouse off")
  }
  
  public func modeChange(mode: Int32) {
    //    Swift.print("### mode change to: \(String(format: "%04X", mode))")
  }
  
  public func setScrollRegionToTop(top: Int32, bottom: Int32, left: Int32, right: Int32) {
    Swift.print("### set scroll region: \(top), \(bottom), \(left), \(right)")
  }
  
  public func scroll(count: Int32) {
    Swift.print("### scroll count: \(count)")
  }
  
  public func highlightSet(attrs: HighlightAttributes) {
    gui {
//      Swift.print("### set highlight")
      self.grid.attrs = attrs
    }
  }
  
  public func put(string: String) {
    gui {
      let curPos = Position(row: self.grid.position.row, column: self.grid.position.column)
      self.grid.put(string)

//      Swift.print("### put: \(curPos) -> '\(string)'")

      self.addToRowFragmentsToDraw(curPos)

      let rect = CGRect(origin: self.originOnView(curPos.row, column: curPos.column), size: self.cellSize)
      self.setNeedsDisplayInRect(rect)
    }
  }
  
  public func bell() {
    //    Swift.print("### bell")
  }
  
  public func visualBell() {
    //    Swift.print("### visual bell")
  }
  
  public func flush() {
//    gui {
//      Swift.print("### flush")
//    }
  }
  
  public func updateForeground(fg: Int32) {
    //    Swift.print("### update fg: \(colorFromCode(fg))")
  }
  
  public func updateBackground(bg: Int32) {
    //    Swift.print("### update bg: \(colorFromCode(bg, kind: .Background))")
  }
  
  public func updateSpecial(sp: Int32) {
    //    Swift.print("### update sp: \(colorFromCode(sp, kind: .Special))")
  }
  
  public func suspend() {
    //    Swift.print("### suspend")
  }
  
  public func setTitle(title: String) {
    //    Swift.print("### set title: \(title)")
  }
  
  public func setIcon(icon: String) {
    //    Swift.print("### set icon: \(icon)")
  }
  
  public func stop() {
    Swift.print("### stop")
  }
  
  private func addToRowFragmentsToDraw(position: Position) {
    let rowFragToAdd = RowFragment(position: position)
    if self.rowFragmentsToDraw.count == 0 {
      self.rowFragmentsToDraw.append(rowFragToAdd)
      return
    }
    
    var indexToReplace = -1
    var rowFragForReplacement = RowFragment.null
    for (idx, rowFrag) in self.rowFragmentsToDraw.enumerate() {
      if rowFrag.canBeAddedTo(rowFragment: rowFragToAdd) {
        indexToReplace = idx
        rowFragForReplacement = rowFrag.union(rowFragToAdd)
        break
      }
    }

    if indexToReplace == -1 {
      self.rowFragmentsToDraw.append(rowFragToAdd)
    } else {
      self.rowFragmentsToDraw[indexToReplace] = rowFragForReplacement
    }
  }
}
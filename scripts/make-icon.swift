import AppKit

let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
guard let image = NSImage(contentsOfFile: source),
	let bitmap = NSBitmapImageRep(
		bitmapDataPlanes: nil,
		pixelsWide: 1024,
		pixelsHigh: 1024,
		bitsPerSample: 8,
		samplesPerPixel: 4,
		hasAlpha: true,
		isPlanar: false,
		colorSpaceName: .deviceRGB,
		bytesPerRow: 0,
		bitsPerPixel: 0
	),
	let context = NSGraphicsContext(bitmapImageRep: bitmap)
else { fatalError("Could not create icon") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 195, yRadius: 195).addClip()
image.draw(
	in: NSRect(x: 0, y: 0, width: 1024, height: 1024),
	from: NSRect(x: 420, y: 5, width: 565, height: 565),
	operation: .sourceOver,
	fraction: 1
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
try data.write(to: URL(fileURLWithPath: destination))

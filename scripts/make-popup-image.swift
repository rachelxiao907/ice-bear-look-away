import AppKit

let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
guard let image = NSImage(contentsOfFile: source),
	let bitmap = NSBitmapImageRep(
		bitmapDataPlanes: nil,
		pixelsWide: 520,
		pixelsHigh: 720,
		bitsPerSample: 8,
		samplesPerPixel: 4,
		hasAlpha: true,
		isPlanar: false,
		colorSpaceName: .deviceRGB,
		bytesPerRow: 0,
		bitsPerPixel: 0
	),
	let context = NSGraphicsContext(bitmapImageRep: bitmap)
else { fatalError("Could not create popup image") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
image.draw(
	in: NSRect(x: 0, y: 0, width: 520, height: 720),
	from: NSRect(x: 410, y: 0, width: 520, height: 720),
	operation: .copy,
	fraction: 1
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode popup image") }
try data.write(to: URL(fileURLWithPath: destination))

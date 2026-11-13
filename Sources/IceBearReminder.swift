import AppKit

final class ReminderApp: NSObject, NSApplicationDelegate {
	private var statusItem: NSStatusItem?
	private var pauseItem: NSMenuItem?
	private var reminderTimer: Timer?
	private var window: NSWindow?
	private var countdownLabel: NSTextField?
	private var countdownTimer: Timer?
	private var dismissTimer: Timer?
	private var sound: NSSound?
	private var secondsRemaining = 20
	private var isPaused = UserDefaults.standard.bool(forKey: "remindersPaused")

	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApplication.shared.setActivationPolicy(.accessory)
		configureMenuBar()
		if !isPaused { scheduleReminders() }
	}

	private func configureMenuBar() {
		let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		if let image = Bundle.main.url(forResource: "AppIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:)) {
			image.size = NSSize(width: 20, height: 20)
			item.button?.image = image
		}
		item.button?.toolTip = "Ice Bear eye reminder"

		let menu = NSMenu()
		let show = NSMenuItem(title: "Show reminder now", action: #selector(showReminderNow), keyEquivalent: "")
		show.target = self
		menu.addItem(show)

		let pause = NSMenuItem(title: "", action: #selector(togglePause), keyEquivalent: "")
		pause.target = self
		pauseItem = pause
		menu.addItem(pause)
		updatePauseMenu()

		menu.addItem(.separator())
		let quit = NSMenuItem(title: "Quit Ice Bear Reminder", action: #selector(quitApp), keyEquivalent: "")
		quit.target = self
		menu.addItem(quit)
		item.menu = menu
		statusItem = item
	}

	private func scheduleReminders() {
		reminderTimer?.invalidate()
		reminderTimer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in
			self?.showReminder()
		}
	}

	private func updatePauseMenu() {
		pauseItem?.title = isPaused ? "Resume reminders" : "Pause reminders"
		statusItem?.button?.toolTip = isPaused ? "Ice Bear eye reminder: paused" : "Ice Bear eye reminder: every 20 minutes"
	}

	@objc private func togglePause() {
		isPaused.toggle()
		UserDefaults.standard.set(isPaused, forKey: "remindersPaused")
		if isPaused {
			reminderTimer?.invalidate()
			window?.close()
		} else {
			scheduleReminders()
		}
		updatePauseMenu()
	}

	@objc private func showReminderNow() {
		showReminder()
	}

	@objc private func quitApp() {
		NSApplication.shared.terminate(nil)
	}

	private func showReminder() {
		if let window {
			window.makeKeyAndOrderFront(nil)
			NSApplication.shared.activate(ignoringOtherApps: true)
			return
		}

		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
			styleMask: [.titled, .closable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		window.title = "Ice Bear Reminder"
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.isReleasedWhenClosed = false
		window.level = .floating
		window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		window.center()
		window.delegate = self

		let content = NSView()
		content.wantsLayer = true
		content.layer?.backgroundColor = NSColor(calibratedRed: 0.91, green: 0.97, blue: 0.99, alpha: 1).cgColor
		window.contentView = content

		let bear = NSImageView()
		bear.image = Bundle.main.url(forResource: "PopupBear", withExtension: "png").flatMap(NSImage.init(contentsOf:))
		bear.imageScaling = .scaleProportionallyUpOrDown
		let title = label("Look away for a moment", size: 25, weight: .bold)
		let instruction = label("Find something about 20 feet away.\nKeep looking at it for 20 seconds.", size: 16, weight: .regular)
		instruction.maximumNumberOfLines = 2
		let countdown = label("20 seconds · look away now", size: 18, weight: .semibold)
		countdownLabel = countdown

		let restart = NSButton(title: "Restart 20 seconds", target: self, action: #selector(restartCountdown))
		restart.bezelStyle = .rounded
		let done = NSButton(title: "Done", target: self, action: #selector(closeReminder))
		done.bezelStyle = .rounded
		done.keyEquivalent = "\r"
		let buttons = NSStackView(views: [restart, done])
		buttons.orientation = .horizontal
		buttons.spacing = 12
		buttons.alignment = .centerY

		let stack = NSStackView(views: [bear, title, instruction, countdown, buttons])
		stack.orientation = .vertical
		stack.alignment = .centerX
		stack.spacing = 13
		stack.setCustomSpacing(2, after: bear)
		stack.setCustomSpacing(19, after: instruction)
		stack.setCustomSpacing(23, after: countdown)
		stack.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -3),
			bear.widthAnchor.constraint(equalToConstant: 188),
			bear.heightAnchor.constraint(equalToConstant: 260),
		])

		window.makeKeyAndOrderFront(nil)
		self.window = window
		playSound()
		startCountdown()
		NSApplication.shared.activate(ignoringOtherApps: true)
	}

	private func label(_ value: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
		let label = NSTextField(labelWithString: value)
		label.font = .systemFont(ofSize: size, weight: weight)
		label.textColor = NSColor(calibratedRed: 0.15, green: 0.26, blue: 0.31, alpha: 1)
		label.alignment = .center
		return label
	}

	private func playSound() {
		let slackSound = URL(fileURLWithPath: "/Applications/Slack.app/Contents/Resources/knock_brush.mp3")
		if FileManager.default.fileExists(atPath: slackSound.path) {
			sound = NSSound(contentsOf: slackSound, byReference: true)
		} else {
			sound = NSSound(named: NSSound.Name("Glass"))
		}
		sound?.play()
	}

	private func startCountdown() {
		countdownTimer?.invalidate()
		dismissTimer?.invalidate()
		secondsRemaining = 20
		countdownLabel?.stringValue = "20 seconds · look away now"
		countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
			guard let self else { return }
			self.secondsRemaining -= 1
			if self.secondsRemaining == 0 {
				self.countdownTimer?.invalidate()
				self.countdownLabel?.stringValue = "20 seconds are up"
			} else {
				self.countdownLabel?.stringValue = "\(self.secondsRemaining) seconds · keep looking away"
			}
		}
		dismissTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
			self?.window?.close()
		}
	}

	@objc private func restartCountdown() {
		startCountdown()
	}

	@objc private func closeReminder() {
		window?.close()
	}
}

extension ReminderApp: NSWindowDelegate {
	func windowWillClose(_ notification: Notification) {
		countdownTimer?.invalidate()
		dismissTimer?.invalidate()
		window = nil
		countdownLabel = nil
	}
}

let app = NSApplication.shared
let delegate = ReminderApp()
app.delegate = delegate
app.run()

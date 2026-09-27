import AppKit
import CoreGraphics

enum OverlayWindowLevel {
    // Матч с проверенной конфигурацией Click Play (не выдумка/эскалация):
    // https://github.com/TheOPBunny/ClickPlay/blob/main/ClickPlay/GamepadWindow.swift
    // assistiveTechHighWindow (1500) не тестировался Click Play и не подтверждён
    // на Mac для OverSlay; screenSaverWindow (1000) — единственный уровень,
    // про который у нас есть свидетельство работы поверх fullscreen игр.
    static let base = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.screenSaverWindow))
    )
    static let service = NSWindow.Level(rawValue: base.rawValue + 1)
}

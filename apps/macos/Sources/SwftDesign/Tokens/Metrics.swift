import CoreGraphics

public enum SwftSpace {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

public enum SwftRadius {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let composer: CGFloat = 28
}

public enum SwftLayout {
    public static let sidebarWidth: CGFloat = 272
    public static let sidebarRowHeight: CGFloat = 32
    public static let contentMaxWidth: CGFloat = 760
    public static let composerMaxWidth: CGFloat = 744
    public static let titlebarHeight: CGFloat = 52
}

import SwiftUI

/// Short, one-shot transitions only. Nothing in Swft repaints continuously.
public enum SwftMotion {
    public static let quick = Animation.snappy(duration: 0.16)
    public static let standard = Animation.snappy(duration: 0.24)
}

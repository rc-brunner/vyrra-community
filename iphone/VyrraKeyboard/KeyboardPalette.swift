import UIKit

struct KeyboardPalette {
    let background: UIColor
    let key: UIColor
    let control: UIColor
    let primary: UIColor
    let text: UIColor
    let secondaryText: UIColor
    let primaryText: UIColor

    init(style: UIUserInterfaceStyle) {
        if style == .dark {
            background = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            key = UIColor(red: 0.32, green: 0.32, blue: 0.33, alpha: 1)
            if #available(iOS 26.0, *) {
                control = key
            } else {
                control = UIColor(red: 0.22, green: 0.22, blue: 0.23, alpha: 1)
            }
            primary = .white
            text = .white
            secondaryText = UIColor(white: 0.68, alpha: 1)
            primaryText = .black
        } else {
            background = UIColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1)
            key = .white
            if #available(iOS 26.0, *) {
                control = key
            } else {
                control = UIColor(red: 0.75, green: 0.77, blue: 0.80, alpha: 1)
            }
            primary = .black
            text = .black
            secondaryText = UIColor(white: 0.42, alpha: 1)
            primaryText = .white
        }
    }
}

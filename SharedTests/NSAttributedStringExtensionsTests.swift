/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import XCTest
import Shared

class NSAttributedStringExtensionsTests: XCTestCase {
    private func checkCharacterAtPosition(position: Int, isColored color: UIColor, inString string: NSAttributedString) -> Bool {
        if let attributes = string.attributesAtIndex(position, effectiveRange: nil) as? [String:AnyObject] {
            if let foregroundColor = attributes[NSForegroundColorAttributeName] as? UIColor {
                if foregroundColor == color {
                    return true
                }
            }
        }
        return false
    }

    func testColorsSubstring() {
        let substring = "bc"
        let example = NSAttributedString(string: "abcd")
        let expected = example.colorSubstring(substring, withColor: UIColor.redColor())

        XCTAssertFalse(checkCharacterAtPosition(0, isColored: UIColor.redColor(), inString: expected))
        for position in 1..<3 {
            XCTAssertTrue(checkCharacterAtPosition(position, isColored: UIColor.redColor(), inString: expected))
        }
        XCTAssertFalse(checkCharacterAtPosition(3, isColored: UIColor.redColor(), inString: expected))
    }

    func testDoesNothingWithEmptySubstring() {
        let substring = ""
        let example = NSAttributedString(string: "abcd")
        let expected = example.colorSubstring(substring, withColor: UIColor.redColor())
        for position in 0..<count(expected.string) {
            XCTAssertFalse(checkCharacterAtPosition(position, isColored: UIColor.redColor(), inString: expected))
        }
    }

    func testDoesNothingWhenSubstringNotFound() {
        let substring = "yyz"
        let example = NSAttributedString(string: "abcd")
        let expected = example.colorSubstring(substring, withColor: UIColor.redColor())
        for position in 0..<count(expected.string) {
            XCTAssertFalse(checkCharacterAtPosition(position, isColored: UIColor.redColor(), inString: expected))
        }
    }
}
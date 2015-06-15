/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import XCTest
import Shared

class NSURLExtensionsTests : XCTestCase {
    func testRemovesHTTPFromURL() {
        let url = NSURL(string: "http://google.com")
        if let actual = url?.absoluteStringWithoutHTTPScheme() {
            XCTAssertEqual(actual, "google.com")
        } else {
            XCTFail("Actual url is nil")
        }
    }

    func testKeepsHTTPSInURL() {
        let url = NSURL(string: "https://google.com")
        if let actual = url?.absoluteStringWithoutHTTPScheme() {
            XCTAssertEqual(actual, "https://google.com")
        } else {
            XCTFail("Actual url is nil")
        }
    }

    func testKeepsAboutSchemeInURL() {
        let url = NSURL(string: "about:home")
        if let actual = url?.absoluteStringWithoutHTTPScheme() {
            XCTAssertEqual(actual, "about:home")
        } else {
            XCTFail("Actual url is nil")
        }
    }

    func testRemovesWWWSubdomain() {
        let url = NSURL(string: "https://www.google.com")
        if let actual = url?.hostStringWithoutSubdomains() {
            XCTAssertEqual(actual, "google.com")
        } else {
            XCTFail("Actual url is nil")
        }
    }

    func testNotWWWSubdomain() {
        let url = NSURL(string: "https://secure.twitter.com")
        if let actual = url?.hostStringWithoutSubdomains() {
            XCTAssertEqual(actual, "twitter.com")
        } else {
            XCTFail("Actual url is nil")
        }
    }

    func testRemovesMultipleSubdomains() {
        let url = NSURL(string: "https://super.secure.twitter.com")
        if let actual = url?.hostStringWithoutSubdomains() {
            XCTAssertEqual(actual, "twitter.com")
        } else {
            XCTFail("Actual url is nil")
        }
    }

    func testDoesNothingWhenNoSubdomains() {
        let url = NSURL(string: "https://github.com")
        if let actual = url?.hostStringWithoutSubdomains() {
            XCTAssertEqual(actual, "github.com")
        } else {
            XCTFail("Actual url is nil")
        }
    }
}
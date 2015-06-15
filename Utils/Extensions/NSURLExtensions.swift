/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

extension NSURL {
    public func withQueryParams(params: [NSURLQueryItem]) -> NSURL {
        let components = NSURLComponents(URL: self, resolvingAgainstBaseURL: false)!
        var items = (components.queryItems ?? [])
        for param in params {
            items.append(param)
        }
        components.queryItems = items
        return components.URL!
    }

    public func withQueryParam(name: String, value: String) -> NSURL {
        let components = NSURLComponents(URL: self, resolvingAgainstBaseURL: false)!
        let item = NSURLQueryItem(name: name, value: value)
        components.queryItems = (components.queryItems ?? []) + [item]
        return components.URL!
    }

    public func getQuery() -> [String: String] {
        var results = [String: String]()
        var keyValues = self.query?.componentsSeparatedByString("&")

        if keyValues?.count > 0 {
            for pair in keyValues! {
                let kv = pair.componentsSeparatedByString("=")
                if kv.count > 1 {
                    results[kv[0]] = kv[1]
                }
            }
        }

        return results
    }

    public func absoluteStringWithoutHTTPScheme() -> String? {
        if let urlString = self.absoluteString {
            // If it's basic http, strip out the string but leave anything else in
            if urlString.hasPrefix("http://") ?? false {
                return urlString.substringFromIndex(advance(urlString.startIndex, 7))
            } else {
                return urlString
            }
        } else {
            return nil
        }
    }

    public func hostStringWithoutSubdomains() -> String? {
        if let hostComponents = self.host?.componentsSeparatedByString(".") where count(hostComponents) >= 2 {
            // Grab the last two components of the host
            let hostComponentsWithoutSubdomain = hostComponents[(count(hostComponents) - 2)..<count(hostComponents)]
            return join(".", hostComponentsWithoutSubdomain)
        } else {
            return nil
        }
    }
}

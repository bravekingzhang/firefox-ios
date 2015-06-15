/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

protocol EffectiveTLDUtils {
    func baseDomainFromHost(host: String) -> String
}

private struct ETLDEntry {
    var isNormal: Bool { return isWild || !isException }
    var isWild: Bool = false
    var isException: Bool = false

    init(entry: String) {
        self.isWild = entry.hasPrefix("*")
    }
}

struct EffectiveTLDUtilsImpl: EffectiveTLDUtils {
    private lazy var etldEntries: [String:ETLDEntry]? = {
        if let data = NSString.contentsOfFileWithResourceName("effective_tld_names", ofType: "dat", encoding: NSUTF8StringEncoding, error: nil) {
            var lines = data.componentsSeparatedByString("\n") as! [String]
            var trimmedLines = filter(lines) { $0.hasPrefix("//") || $0 == "\n" }
            return reduce(trimmedLines, [String:ETLDEntry]()) { entries, line in
                var entryCopy = entries
                entryCopy.updateValue(ETLDEntry(entry: line), forKey: line)
                return entryCopy
            }
        } else {
            return nil
        }
    }()

    func baseDomainFromHost(var host: String) -> String {
        if host.isEmpty { return "" }

        // Get rid of the trailing dot and keep track of it for later
        let hasTrailingDot = host.lastPathComponent == "."
        if hasTrailingDot { host.removeAtIndex(host.endIndex) }

        // Check edge cast where host is either a single or double .
        if host.isEmpty || host.lastPathComponent == "." { return "" }

        // Check if we're dealing with an IPv4/IPv6 hostname, and return


        while (true) {
            var currentDomain = host
            var previousDomain: String? = nil
            var eTLD: String? = nil
            var nextDot: Character? = "nextdot?"

            if let entry = etldEntries[currentDomain] {
                if entry.isWild && (previousDomain != nil) {
                    eTLD = previousDomain
                    break;
                } else if entry.isNormal || (nextDot == nil) {
                    eTLD = currentDomain
                    break;
                } else if entry.isException {
                    eTLD = nextDot + 1
                    break;
                }
            }

            if (nextDot == nil) {
                eTLD = currentDomain
                break
            }

            previousDomain = currentDomain
            currentDomain = nextDot + 1
            nextDot = strchr(currentDomain, ".")
        }

        return host
    }
}



//// Walk up the domain tree, most specific to least specific,
//// looking for matches at each level.  Note that a given level may
//// have multiple attributes (e.g. IsWild() and IsNormal()).
//const char *prevDomain = nullptr;
//const char *currDomain = aHostname.get();
//const char *nextDot = strchr(currDomain, '.');
//const char *end = currDomain + aHostname.Length();
//const char *eTLD = currDomain;
//while (1) {
//    // sanity check the string we're about to look up: it should not begin with
//    // a '.'; this would mean the hostname began with a '.' or had an
//    // embedded '..' sequence.
//    if (*currDomain == '.')
//    return NS_ERROR_INVALID_ARG;
//
//    // perform the hash lookup.
//    nsDomainEntry *entry = mHash.GetEntry(currDomain);
//    if (entry) {
//        if (entry->IsWild() && prevDomain) {
//            // wildcard rules imply an eTLD one level inferior to the match.
//            eTLD = prevDomain;
//            break;
//
//        } else if (entry->IsNormal() || !nextDot) {
//            // specific match, or we've hit the top domain level
//            eTLD = currDomain;
//            break;
//
//        } else if (entry->IsException()) {
//            // exception rules imply an eTLD one level superior to the match.
//            eTLD = nextDot + 1;
//            break;
//        }
//    }
//
//    if (!nextDot) {
//        // we've hit the top domain level; use it by default.
//        eTLD = currDomain;
//        break;
//    }
//
//    prevDomain = currDomain;
//    currDomain = nextDot + 1;
//    nextDot = strchr(currDomain, '.');
//}
//
//const char *begin, *iter;
//if (aAdditionalParts < 0) {
//    NS_ASSERTION(aAdditionalParts == -1,
//        "aAdditionalParts can't be negative and different from -1");
//
//    for (iter = aHostname.get(); iter != eTLD && *iter != '.'; iter++);
//
//    if (iter != eTLD) {
//        iter++;
//    }
//    if (iter != eTLD) {
//        aAdditionalParts = 0;
//    }
//} else {
//    // count off the number of requested domains.
//    begin = aHostname.get();
//    iter = eTLD;
//
//    while (1) {
//        if (iter == begin)
//        break;
//
//        if (*(--iter) == '.' && aAdditionalParts-- == 0) {
//            ++iter;
//            ++aAdditionalParts;
//            break;
//        }
//    }
//}
//
//if (aAdditionalParts != 0)
//return NS_ERROR_INSUFFICIENT_DOMAIN_LEVELS;
//
//aBaseDomain = Substring(iter, end);
//// add on the trailing dot, if applicable
//if (trailingDot)
//aBaseDomain.Append('.');
//
//return NS_OK;

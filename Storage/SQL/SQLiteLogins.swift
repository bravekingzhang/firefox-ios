/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import XCGLogger

private let log = XCGLogger.defaultInstance()

let TableLoginsMirror = "loginsM"
let TableLoginsLocal = "loginsL"
let AllLoginTables: Args = [TableLoginsMirror, TableLoginsLocal]

private class LoginsTable: Table {
    var name: String { return "LOGINS" }
    var version: Int { return 2 }

    func run(db: SQLiteDBConnection, sql: String, args: Args? = nil) -> Bool {
        let err = db.executeChange(sql, withArgs: args)
        if err != nil {
            log.error("Error running SQL in LoginsTable. \(err?.localizedDescription)")
            log.error("SQL was \(sql)")
        }
        return err == nil
    }

    // TODO: transaction.
    func run(db: SQLiteDBConnection, queries: [String]) -> Bool {
        for sql in queries {
            if !run(db, sql: sql, args: nil) {
                return false
            }
        }
        return true
    }

    func create(db: SQLiteDBConnection, version: Int) -> Bool {
        // We ignore the version.

        let common =
        "id INTEGER PRIMARY KEY AUTOINCREMENT" +
        ", hostname TEXT NOT NULL" +
        ", httpRealm TEXT" +
        ", formSubmitURL TEXT" +
        ", usernameField TEXT" +
        ", passwordField TEXT" +
        ", timeCreated INTEGER NOT NULL" +
        ", timeLastUsed INTEGER" +
        ", timePasswordChanged INTEGER NOT NULL" +
        ", username TEXT" +
        ", password TEXT NOT NULL"

        let mirror = "CREATE TABLE IF NOT EXISTS \(TableLoginsMirror) (" +
            common +
            ", guid TEXT NOT NULL UNIQUE" +
            ", server_modified INTEGER NOT NULL" +              // Integer milliseconds.
            ", is_overridden TINYINT NOT NULL DEFAULT 0" +
        ")"

        let local = "CREATE TABLE IF NOT EXISTS \(TableLoginsLocal) (" +
            common +
            ", guid TEXT NOT NULL UNIQUE " +                  // Typically overlaps one in the mirror unless locally new.
            ", local_modified INTEGER" +                      // Can be null. Client clock. In extremis only.
            ", is_deleted TINYINT NOT NULL DEFAULT 0" +     // Boolean. Locally deleted.
            ", should_upload TINYINT NOT NULL DEFAULT 0" +  // Boolean. Set when changed or created.
        ")"

        return self.run(db, queries: [mirror, local])
    }

    func updateTable(db: SQLiteDBConnection, from: Int, to: Int) -> Bool {
        if from == to {
            log.debug("Skipping update from \(from) to \(to).")
            return true
        }

        if from == 0 {
            // This is likely an upgrade from before Bug 1160399.
            log.debug("Updating logins tables from zero. Assuming drop and recreate.")
            return drop(db) && create(db, version: to)
        }

        // TODO: real update!
        log.debug("Updating logins table from \(from) to \(to).")
        return drop(db) && create(db, version: to)
    }

    func exists(db: SQLiteDBConnection) -> Bool {
        return db.tablesExist(AllLoginTables)
    }

    func drop(db: SQLiteDBConnection) -> Bool {
        log.debug("Dropping logins table.")
        let err = db.executeChange("DROP TABLE IF EXISTS \(name)", withArgs: nil)
        return err == nil
    }

}

public class SQLiteLogins: BrowserLogins {
    private let db: BrowserDB

    public init(db: BrowserDB) {
        self.db = db
        db.createOrUpdate(LoginsTable())
    }

    private class func LoginFactory(row: SDRow) -> Login {
        let c = NSURLCredential(user: row["username"] as? String ?? "",
            password: row["password"] as! String,
            persistence: NSURLCredentialPersistence.None)
        let protectionSpace = NSURLProtectionSpace(host: row["hostname"] as! String,
            port: 0,
            `protocol`: nil,
            realm: row["httpRealm"] as? String,
            authenticationMethod: nil)

        let login = Login(credential: c, protectionSpace: protectionSpace)
        login.formSubmitURL = row["formSubmitURL"] as? String
        login.usernameField = row["usernameField"] as? String
        login.passwordField = row["passwordField"] as? String
        login.guid = row["guid"] as! String

        if let timeCreated = row.getTimestamp("timeCreated"),
            let timeLastUsed = row.getTimestamp("timeLastUsed"),
            let timePasswordChanged = row.getTimestamp("timePasswordChanged") {
                login.timeCreated = timeCreated
                login.timeLastUsed = timeLastUsed
                login.timePasswordChanged = timePasswordChanged
        }

        return login
    }

    private class func LoginDataFactory(row: SDRow) -> LoginData {
        return LoginFactory(row) as LoginData
    }

    private class func LoginUsageDataFactory(row: SDRow) -> LoginUsageData {
        return LoginFactory(row) as LoginUsageData
    }

    public func getLoginsForProtectionSpace(protectionSpace: NSURLProtectionSpace) -> Deferred<Result<Cursor<LoginData>>> {
        let projection = "guid, username, password, hostname, httpRealm, formSubmitURL, usernameField, passwordField, timeLastUsed"

        let sql =
        "SELECT \(projection) FROM " +
        "\(TableLoginsLocal) WHERE is_deleted = 0 AND hostname = ? " +
        "UNION ALL " +
        "SELECT \(projection) FROM " +
        "\(TableLoginsMirror) WHERE is_overridden = 0 AND hostname = ? " +
        "ORDER BY timeLastUsed DESC"

        let args: Args = [protectionSpace.host, protectionSpace.host]
        return db.runQuery(sql, args: args, factory: SQLiteLogins.LoginDataFactory)
    }

    // username is really Either<String, NULL>; we explicitly match no username.
    public func getLoginsForProtectionSpace(protectionSpace: NSURLProtectionSpace, withUsername username: String?) -> Deferred<Result<Cursor<LoginData>>> {
        let projection = "guid, username, password, hostname, httpRealm, formSubmitURL, usernameField, passwordField, timeLastUsed"

        let args: Args
        let usernameMatch: String
        if let username = username {
            args = [protectionSpace.host, username, protectionSpace.host, username]
            usernameMatch = "username = ?"
        } else {
            args = [protectionSpace.host, protectionSpace.host]
            usernameMatch = "username IS NULL"
        }

        let sql =
        "SELECT \(projection) FROM " +
        "\(TableLoginsLocal) WHERE is_deleted = 0 AND hostname = ? AND \(usernameMatch) " +
        "UNION ALL " +
        "SELECT \(projection) FROM " +
        "\(TableLoginsMirror) WHERE is_overridden = 0 AND hostname = ? AND username = ? " +
        "ORDER BY timeLastUsed DESC"

        return db.runQuery(sql, args: args, factory: SQLiteLogins.LoginDataFactory)
    }

    public func getUsageDataForLoginByGUID(guid: GUID) -> Deferred<Result<LoginUsageData>> {
        let projection = "guid, username, password, hostname, httpRealm, formSubmitURL, usernameField, passwordField, timeCreated, timeLastUsed, timePasswordChanged"

        let sql =
        "SELECT \(projection) FROM " +
        "\(TableLoginsLocal) WHERE is_deleted = 0 AND guid = ? " +
        "UNION ALL " +
        "SELECT \(projection) FROM " +
        "\(TableLoginsMirror) WHERE is_overridden = 0 AND guid = ? " +
        "LIMIT 1"

        let args: Args = [guid, guid]
        return db.runQuery(sql, args: args, factory: SQLiteLogins.LoginUsageDataFactory)
            >>== { value in
            deferResult(value[0]!)
        }
    }

    public func addLogin(login: LoginData) -> Success {
        var args: Args = [
            login.hostname,
            login.httpRealm,
            login.formSubmitURL,
            login.usernameField,
            login.passwordField,
        ]

        let nowMicro = NSDate.nowMicroseconds()
        let nowMilli = nowMicro / 1000
        let dateMicro = NSNumber(unsignedLongLong: nowMicro)
        let dateMilli = NSNumber(unsignedLongLong: nowMilli)
        args.append(dateMicro)            // timeCreated
        args.append(dateMicro)            // timeLastUsed
        args.append(dateMicro)            // timePasswordChanged
        args.append(login.username)
        args.append(login.password)

        args.append(login.guid)
        args.append(dateMilli)            // localModified

        let sql =
        "INSERT OR IGNORE INTO \(TableLoginsLocal) " +
        // Shared fields.
        "( hostname" +
        ", httpRealm" +
        ", formSubmitURL" +
        ", usernameField" +
        ", passwordField" +
        ", timeCreated" +
        ", timeLastUsed" +
        ", timePasswordChanged" +
        ", username" +
        ", password " +

        // Local metadata.
        ", guid " +
        ", local_modified " +
        ", is_deleted " +
        ", should_upload " +
        ") " +
        "VALUES (?,?,?,?,?,?,?,?,?,?, " +
        "?, ?, 0, 1" +         // Metadata.
        ")"

        return db.run(sql, withArgs: args)
    }

    private func cloneMirrorToOverlay(guid: GUID) -> Deferred<Result<Int>> {
        let shared =
        "guid " +
        ", hostname" +
        ", httpRealm" +
        ", formSubmitURL" +
        ", usernameField" +
        ", passwordField" +
        ", timeCreated" +
        ", timeLastUsed" +
        ", timePasswordChanged" +
        ", username" +
        ", password "

        let local =
        ", local_modified " +
        ", is_deleted " +
        ", should_upload "

        let sql = "INSERT OR IGNORE INTO \(TableLoginsLocal) " +
        "(\(shared), \(local)) " +
        "SELECT \(shared), NULL, 0, 0 FROM \(TableLoginsMirror) WHERE guid = ?"

        let args: Args = [guid]
        return self.db.write(sql, withArgs: args)
    }

    /**
     * Returns success if either a local row already existed, or
     * one could be copied from the mirror.
     */
    private func ensureLocalOverlayExistsForGUID(guid: GUID) -> Success {
        let sql = "SELECT guid FROM \(TableLoginsLocal) WHERE guid = ?"
        let args: Args = [guid]
        let c = db.runQuery(sql, args: args, factory: { $0 })

        return c >>== { rows in
            if rows.count > 0 {
                return succeed()
            }
            return self.cloneMirrorToOverlay(guid)
                >>== { count in
                    if count > 0 {
                        return succeed()
                    }
                    return deferResult(NoSuchRecordError(guid: guid))
            }
        }
    }

    public func addUseOfLoginByGUID(guid: GUID) -> Success {
        let sql =
        "UPDATE \(TableLoginsLocal) SET " +
        "timeLastUsed = ?, local_modified = ?" +
        "WHERE guid = ? AND is_deleted = 0"

        // For now, mere use is not enough to flip should_upload.

        let nowMicro = NSDate.nowMicroseconds()
        let nowMilli = nowMicro / 1000
        let args: Args = [NSNumber(unsignedLongLong: nowMicro), NSNumber(unsignedLongLong: nowMilli)]

        return self.ensureLocalOverlayExistsForGUID(guid)
           >>> { self.db.run(sql, withArgs: args) }
    }

    private func getSETClauseForLoginData(login: LoginData, significant: Bool) -> (String, Args) {
        let nowMicro = NSDate.nowMicroseconds()
        let nowMilli = nowMicro / 1000
        let dateMicro = NSNumber(unsignedLongLong: nowMicro)
        let dateMilli = NSNumber(unsignedLongLong: nowMilli)

        var args: Args = [
            dateMilli,            // local_modified
            login.httpRealm,
            login.formSubmitURL,
            login.usernameField,
            login.passwordField,
            dateMicro,            // timeLastUsed
            dateMicro,            // timePasswordChanged
            login.password,
            login.hostname,
            login.username,
        ]

        let sql =
        "  local_modified = ?" +
        ", httpRealm = ?, formSubmitURL = ?, usernameField = ?" +
        ", passwordField = ?, timeLastUsed = ?, timePasswordChanged = ?, password = ?" +
        ", hostname = ?, username = ?" +
        (significant ? ", should_upload = 1 " : "")

        return (sql, args)
    }

    public func updateLoginByGUID(guid: GUID, new: LoginData, significant: Bool) -> Success {
        // TODO: bump timePasswordChanged if it did in fact change.
        // TODO: set changed fields!
        var (setClause, args) = self.getSETClauseForLoginData(new, significant: significant)

        let update =
        "UPDATE \(TableLoginsLocal) SET " +
        setClause +
        " WHERE guid = ?"

        args.append(guid)

        return self.ensureLocalOverlayExistsForGUID(guid)
           >>> { self.db.run(update, withArgs: args) }
    }

    /*
    /// Update based on username, hostname, httpRealm, formSubmitURL.
    public func updateLogin(login: LoginData) -> Success {
        // TODO

        let nowMicro = NSDate.nowMicroseconds()
        let nowMilli = nowMicro / 1000
        let dateMicro = NSNumber(unsignedLongLong: nowMicro)
        let dateMilli = NSNumber(unsignedLongLong: nowMilli)
        let args: Args = [
            login.httpRealm,
            login.formSubmitURL,
            login.usernameField,
            login.passwordField,
            dateMicro, // timePasswordChanged
            login.password,
            login.hostname,
            login.username,

        ]

        return succeed()
        //return db.run("UPDATE \(table.name) SET httpRealm = ?, formSubmitURL = ?, usernameField = ?, passwordField = ?, timePasswordChanged = ?, password = ? WHERE hostname = ? AND username IS ?", withArgs: args)
    }
*/

    public func removeLoginByGUID(guid: GUID) -> Success {
        let nowMillis = NSDate.now()

        let update =
        "UPDATE \(TableLoginsLocal) SET local_modified = \(nowMillis), should_upload = 1, is_deleted = 1, password = '', hostname = '', username = '' WHERE guid = ?"

        let insert =
        "INSERT OR IGNORE INTO \(TableLoginsLocal) (guid, local_modified, is_deleted, should_upload, hostname, timeCreated, timePasswordChanged, password, username) " +
        "SELECT guid, \(nowMillis) 1, 1, '', timeCreated, \(nowMillis)000, '', '' FROM \(TableLoginsMirror) WHERE guid = ?"

        let args: Args = [guid]

        return self.db.run(update, withArgs: args) >>> { self.db.run(insert, withArgs: args) }
    }


    public func removeAll() -> Success {
        // TODO: don't bother if Sync isn't set up!

        let nowMillis = NSDate.now()

        // Mark anything we haven't already deleted.
        let update =
        "UPDATE \(TableLoginsLocal) SET local_modified = \(nowMillis), should_upload = 1, is_deleted = 1, password = '', hostname = '', username = '' WHERE is_deleted = 0"

        // Copy all the remaining rows from our mirror, marking them as deleted.
        let insert =
        "INSERT OR IGNORE INTO \(TableLoginsLocal) (guid, local_modified, is_deleted, should_upload, hostname, timeCreated, timePasswordChanged, password, username) " +
        "SELECT guid, \(nowMillis) 1, 1, '', timeCreated, \(nowMillis)000, '', '' FROM \(TableLoginsMirror)"

        return self.db.run(update) >>> { self.db.run(insert) }
    }
}

// TODO
extension SQLiteLogins: SyncableLogins {
    /**
     * Delete the login with the provided GUID. Succeeds if the GUID is unknown.
    */
    public func deleteByGUID(guid: GUID, deletedAt: Timestamp) -> Success {
        return succeed()
    }

    /**
     * Chains through the provided timestamp.
     */
    public func markAsSynchronized([GUID], modified: Timestamp) -> Deferred<Result<Timestamp>> {
        return deferResult(0)
    }

    public func markAsDeleted(guids: [GUID]) -> Success {
        return succeed()
    }

    /**
     * Clean up any metadata.
     */
    public func onRemovedAccount() -> Success {
        return succeed()
    }
}
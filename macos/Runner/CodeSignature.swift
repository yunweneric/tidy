import Foundation

/// What macOS can say about a bundle's signature, without any list of its own.
///
/// Two operations that look alike and cost 50× apart, which is the whole reason
/// this type exists rather than one `check(path:)`:
///
///  * [inspect] *reads* the signature blob — is there one, is it ad-hoc, whose
///    Team ID, which authority. Three to six milliseconds. Safe in bulk.
///  * [validate] *verifies the seal* — re-hashes the bundle's contents against
///    what was signed. One and a half seconds for VLC, twenty-two for Xcode.
///    One item, on demand, never in a sweep.
///
/// Lifted out of `Updater`, which still calls it for the one question only an
/// updater asks: does this download satisfy *our own* designated requirement.
/// Protection asks a different question — what is this — and the difference is
/// why `inspect` exists at all.
enum CodeSignature {

  /// Signing information for one bundle. Reads; verifies nothing.
  ///
  /// Every key is optional because every one of them is genuinely absent for
  /// something: an unsigned binary has no team, Apple's own software has no
  /// Team ID, an ad-hoc build has neither. A missing key is reported as missing
  /// rather than as an empty string, so the Dart side can tell "no developer"
  /// from "a developer whose name we failed to read".
  static func inspect(path: String) -> [String: Any] {
    let url = URL(fileURLWithPath: path)

    var code: SecStaticCode?
    let created = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(rawValue: 0), &code)
    guard created == errSecSuccess, let code else {
      // errSecCSUnsigned is the ordinary answer for a Homebrew binary, not a
      // failure to look — so it is reported as "not signed", not as an error.
      if created == errSecCSUnsigned {
        return ["path": path, "signed": false]
      }
      return ["path": path, "error": message(for: created)]
    }

    var info: CFDictionary?
    let read = SecCodeCopySigningInformation(
      code,
      SecCSFlags(rawValue: kSecCSSigningInformation),
      &info
    )
    guard read == errSecSuccess, let dictionary = info as? [String: Any] else {
      return ["path": path, "error": message(for: read)]
    }

    var payload: [String: Any] = ["path": path, "signed": true]

    let flags = SecCodeSignatureFlags(
      rawValue: (dictionary[kSecCodeInfoFlags as String] as? UInt32) ?? 0)
    payload["adhoc"] = flags.contains(.adhoc)

    if let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String {
      payload["teamIdentifier"] = team
    }
    if let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String {
      payload["identifier"] = identifier
    }

    // The leaf certificate's common name is the only human-readable "who" macOS
    // holds — "Developer ID Application: Some Company (ABCDE12345)". Apple's own
    // software is signed by "Software Signing" with no Team ID at all, which is
    // why that case is named rather than left looking like a missing developer.
    if let chain = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
       let leaf = chain.first {
      var name: CFString?
      if SecCertificateCopyCommonName(leaf, &name) == errSecSuccess,
         let common = name as String? {
        payload["authority"] = common
        payload["appleSigned"] = common == "Software Signing"
      }
    }

    return payload
  }

  /// Verifies the seal: every file in the bundle, re-hashed against what was
  /// signed. Optionally against a requirement.
  ///
  /// **Seconds per bundle.** `kSecCSCheckNestedCode` is what costs it — it walks
  /// every nested framework and helper — and it is exactly what makes the answer
  /// worth having, so it stays here and stays out of [inspect].
  static func validate(path: String, against requirement: SecRequirement? = nil) -> [String: Any] {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(
      URL(fileURLWithPath: path) as CFURL,
      SecCSFlags(rawValue: 0),
      &code
    ) == errSecSuccess, let code else {
      return ["ok": false, "reason": "This is not signed, so there is no seal to check."]
    }

    let flags = SecCSFlags(rawValue:
      kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)

    // `WithErrors` rather than the plain call: the CFError carries the actual
    // sentence — "a sealed resource is missing or invalid", and the path of the
    // file that failed — where an OSStatus alone is useless to show anyone.
    var error: Unmanaged<CFError>?
    let status = SecStaticCodeCheckValidityWithErrors(code, flags, requirement, &error)
    if status == errSecSuccess { return ["ok": true] }

    let detail = error?.takeRetainedValue().localizedDescription
    return ["ok": false, "reason": detail ?? message(for: status)]
  }

  /// The running app's own designated requirement. Only the updater wants this.
  static func selfDesignatedRequirement() -> SecRequirement? {
    var selfCode: SecCode?
    var selfStatic: SecStaticCode?
    var requirement: SecRequirement?
    guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &selfCode) == errSecSuccess,
          let selfCode,
          SecCodeCopyStaticCode(selfCode, SecCSFlags(rawValue: 0), &selfStatic) == errSecSuccess,
          let selfStatic,
          SecCodeCopyDesignatedRequirement(selfStatic, SecCSFlags(rawValue: 0), &requirement)
            == errSecSuccess else { return nil }
    return requirement
  }

  /// Asks Gatekeeper whether it would let this run.
  ///
  /// There is no public API — `SecAssessment.h` is not in the macOS SDK — so it
  /// is `spctl` or nothing, and `spctl` costs the best part of a second per
  /// item. One click, one item; never a sweep.
  static func assess(path: String) -> [String: Any] {
    let status = Shell.run("/usr/sbin/spctl", ["--assess", "--type", "execute", path])
    if status == 0 { return ["ok": true] }
    return [
      "ok": false,
      "reason": "macOS would not open this without asking you first. That is "
        + "usual for anything not notarised — including software you installed "
        + "on purpose.",
    ]
  }

  private static func message(for status: OSStatus) -> String {
    SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
  }
}

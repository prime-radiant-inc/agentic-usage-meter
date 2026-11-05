import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Test(arguments: [nil, "shared@example.com"] as [String?])
@MainActor
func codexConnectionAllowsDifferentUsersInTheSameWorkspace(
    email: String?
) async throws {
    let first = try codexIdentityResult(userID: "user-a", email: email)
    let second = try codexIdentityResult(userID: "user-b", email: email)
    let existing = codexIdentityAccount(for: first)
    let newID = UUID()
    let app = await codexIdentityApp(
        existing: [(existing, first.credential)],
        additionalAccountID: newID
    )
    let connection = CodexConnectionModel(
        appModel: app.model,
        accountID: newID,
        authenticate: { second }
    )

    await connection.start()

    #expect(connection.phase == .confirmingIdentity(email: email, plan: "business"))
    try await connection.save(displayName: "Second member")

    #expect(connection.phase == .complete)
    #expect(Set(app.model.accounts.map(\.id)) == [existing.id, newID])
    #expect(await app.credentials.loadCredential(for: existing.id) == .codex(first.credential))
    #expect(await app.credentials.loadCredential(for: newID) == .codex(second.credential))
    #expect(await app.state.state.accounts.count == 2)
}

@Test
@MainActor
func codexConnectionRejectsTheSameUserEvenAfterAnEmailChange() async throws {
    let first = try codexIdentityResult(userID: "user-a", email: "old@example.com")
    let second = try codexIdentityResult(userID: "user-a", email: "new@example.com")
    let existing = codexIdentityAccount(for: first)
    let app = await codexIdentityApp(existing: [(existing, first.credential)])
    let connection = CodexConnectionModel(appModel: app.model, authenticate: { second })

    await connection.start()

    #expect(connection.phase == .duplicateIdentity(email: "new@example.com"))
    await #expect(throws: ProviderConnectionInputError.authorizationNotComplete) {
        try await connection.save(displayName: "Duplicate")
    }
    #expect(app.model.accounts.count == 1)
    #expect(await app.credentials.loadCredential(for: existing.id) == .codex(first.credential))
}

@Test
@MainActor
func codexConnectionAllowsTheSameUserInDifferentWorkspaces() async throws {
    let first = try codexIdentityResult(workspaceID: "workspace-a", userID: "user-a")
    let second = try codexIdentityResult(workspaceID: "workspace-b", userID: "user-a")
    let existing = codexIdentityAccount(for: first)
    let newID = UUID()
    let app = await codexIdentityApp(
        existing: [(existing, first.credential)],
        additionalAccountID: newID
    )
    let connection = CodexConnectionModel(
        appModel: app.model,
        accountID: newID,
        authenticate: { second }
    )

    await connection.start()
    try await connection.save(displayName: "Other workspace")

    #expect(connection.phase == .complete)
    #expect(app.model.accounts.count == 2)
    #expect(await app.credentials.loadCredential(for: newID) == .codex(second.credential))
}

@Test(arguments: [nil, " \n "] as [String?])
@MainActor
func codexConnectionFallsBackToEmailWhenAUserIDIsMissing(
    missingUserID: String?
) async throws {
    let first = try codexIdentityResult(userID: missingUserID, email: " Member@Example.com \n")
    let second = try codexIdentityResult(userID: "user-a", email: "member@example.com")
    let app = await codexIdentityApp(
        existing: [(codexIdentityAccount(for: first), first.credential)]
    )
    let connection = CodexConnectionModel(appModel: app.model, authenticate: { second })

    await connection.start()

    #expect(connection.phase == .duplicateIdentity(email: "member@example.com"))
}

@Test
@MainActor
func codexConnectionPrefersTokenEmailToStaleDisplayIdentity() async throws {
    let first = try codexIdentityResult(userID: nil, email: "current@example.com")
    let second = try codexIdentityResult(userID: nil, email: "old@example.com")
    var existing = codexIdentityAccount(for: first)
    existing.authenticatedIdentity = "old@example.com"
    let app = await codexIdentityApp(existing: [(existing, first.credential)])
    let connection = CodexConnectionModel(appModel: app.model, authenticate: { second })

    await connection.start()

    #expect(
        connection.phase == .confirmingIdentity(email: "old@example.com", plan: "business")
    )
}

@Test(arguments: [nil, "invalid-id-token"] as [String?])
@MainActor
func codexConnectionDoesNotTreatUnknownIdentityAsAWorkspaceDuplicate(
    idToken: String?
) async throws {
    let first = try codexIdentityResult(userID: nil, email: nil)
    var credential = first.credential
    credential.idToken = idToken
    let second = try codexIdentityResult(userID: "user-b", email: nil)
    let app = await codexIdentityApp(
        existing: [(codexIdentityAccount(for: first), credential)]
    )
    let connection = CodexConnectionModel(appModel: app.model, authenticate: { second })

    await connection.start()

    #expect(connection.phase == .confirmingIdentity(email: nil, plan: "business"))
}

@Test
@MainActor
func codexConnectionFallsBackToLegacyEmailWhenTheTokenIsMalformed() async throws {
    let first = try codexIdentityResult(userID: "user-a", email: " Member@Example.com ")
    var credential = first.credential
    credential.idToken = "invalid-id-token"
    let second = try codexIdentityResult(userID: "user-a", email: "member@example.com")
    let app = await codexIdentityApp(
        existing: [(codexIdentityAccount(for: first), credential)]
    )
    let connection = CodexConnectionModel(appModel: app.model, authenticate: { second })

    await connection.start()

    #expect(connection.phase == .duplicateIdentity(email: "member@example.com"))
}

@Test
@MainActor
func codexReconnectExcludesItsOwnRecordButKeepsOtherWorkspaceMembers() async throws {
    let first = try codexIdentityResult(userID: "user-a")
    let peer = try codexIdentityResult(userID: "user-b")
    let replacement = try codexIdentityResult(userID: "user-a", email: "new@example.com")
    let existing = codexIdentityAccount(for: first)
    let peerAccount = codexIdentityAccount(for: peer, displayOrder: 1)
    let app = await codexIdentityApp(
        existing: [(existing, first.credential), (peerAccount, peer.credential)]
    )
    let connection = CodexConnectionModel(
        appModel: app.model,
        reconnectingAccount: existing,
        authenticate: { replacement }
    )

    await connection.start()
    try await connection.save(displayName: "Reconnected member")

    #expect(connection.phase == .complete)
    #expect(Set(app.model.accounts.map(\.id)) == [existing.id, peerAccount.id])
    #expect(await app.credentials.loadCredential(for: existing.id) == .codex(replacement.credential))
    #expect(await app.credentials.loadCredential(for: peerAccount.id) == .codex(peer.credential))
}

@Test
@MainActor
func codexReconnectRejectsAnotherAlreadyConnectedWorkspaceMember() async throws {
    let first = try codexIdentityResult(userID: "user-a")
    let peer = try codexIdentityResult(userID: "user-b", email: "peer@example.com")
    let existing = codexIdentityAccount(for: first)
    let peerAccount = codexIdentityAccount(for: peer, displayOrder: 1)
    let app = await codexIdentityApp(
        existing: [(existing, first.credential), (peerAccount, peer.credential)]
    )
    let connection = CodexConnectionModel(
        appModel: app.model,
        reconnectingAccount: existing,
        authenticate: { peer }
    )

    await connection.start()

    #expect(connection.phase == .duplicateIdentity(email: "peer@example.com"))
    await #expect(throws: ProviderConnectionInputError.authorizationNotComplete) {
        try await connection.save(displayName: "Duplicate member")
    }
    #expect(await app.credentials.loadCredential(for: existing.id) == .codex(first.credential))
    #expect(await app.credentials.loadCredential(for: peerAccount.id) == .codex(peer.credential))
}

private func codexIdentityAccount(
    for result: CodexOAuthResult,
    displayOrder: Int = 0
) -> SubscriptionAccount {
    SubscriptionAccount(
        provider: .codex,
        displayName: "Codex member",
        authenticatedIdentity: result.identity.email ?? result.identity.plan,
        displayOrder: displayOrder
    )
}

@MainActor
private func codexIdentityApp(
    existing: [(SubscriptionAccount, OAuthCredential)],
    additionalAccountID: UUID? = nil
) async -> (model: AppModel, credentials: TestCredentialStore, state: TestAppStateStore) {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let credentials = TestCredentialStore(
        credentials: Dictionary(uniqueKeysWithValues: existing.map {
            ($0.0.id, ProviderCredential.codex($0.1))
        })
    )
    let state = TestAppStateStore(
        state: PersistedAppState(accounts: existing.map { $0.0 }, snapshots: [:])
    )
    let accountIDs = existing.map { $0.0.id } + (additionalAccountID.map { [$0] } ?? [])
    let client = TestUsageProviderClient(
        provider: .codex,
        snapshots: Dictionary(uniqueKeysWithValues: accountIDs.map {
            ($0, UsageSnapshot(accountID: $0, fetchedAt: now, windows: []))
        })
    )
    let model = AppModel(
        stateStore: state,
        credentialStore: credentials,
        adapters: [
            CredentialUsageAdapter(provider: .codex, credentialStore: credentials, client: client)
        ],
        now: { now }
    )
    await model.start()
    return (model, credentials, state)
}

private func codexIdentityResult(
    workspaceID: String = "business-workspace",
    userID: String?,
    email: String? = "member@example.com"
) throws -> CodexOAuthResult {
    var auth = [
        "chatgpt_account_id": workspaceID,
        "chatgpt_plan_type": "business",
    ]
    if let userID {
        auth["chatgpt_user_id"] = userID
    }
    var claims: [String: Any] = ["https://api.openai.com/auth": auth]
    if let email {
        claims["email"] = email
    }
    let payload = try JSONSerialization.data(withJSONObject: claims)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    // Synthetic JWT metadata; no real credentials or network calls are used.
    let idToken = "eyJhbGciOiJub25lIn0.\(payload).signature"
    return CodexOAuthResult(
        credential: OAuthCredential(
            accessToken: "access-\(userID ?? "unknown")-\(workspaceID)-\(email ?? "none")",
            refreshToken: "refresh-\(userID ?? "unknown")",
            idToken: idToken,
            accountID: workspaceID
        ),
        identity: CodexOAuthIdentity(
            email: email,
            plan: "business",
            userID: userID,
            accountID: workspaceID
        )
    )
}

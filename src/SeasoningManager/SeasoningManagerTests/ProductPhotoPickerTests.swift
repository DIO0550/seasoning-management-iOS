import Foundation
import Testing
@testable import SeasoningManager

@MainActor
struct ProductPhotoPickerTests {
    nonisolated private enum ReadError: Error, Equatable {
        case unavailable
    }

    static func imageData() throws -> Data {
        let encoded = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="
        return try #require(Data(base64Encoded: encoded))
    }

    @Test func newPhotoIsUnsetAndUnchangedPhotoUsesLatestOriginal() {
        let state = ProductPhotoState()

        #expect(state.image(original: nil) == nil)
        #expect(state.image(original: Data([1])) == Data([1]))
        #expect(state.image(original: Data([2])) == Data([2]))
        #expect(!state.isLoading)
        #expect(state.error == nil)
    }

    @Test func loadingValidImageAllowsAdditionAndReplacement() async throws {
        let data = try Self.imageData()
        let loader = ProductPhotoLoader()
        var state = ProductPhotoState()
        let request = state.beginLoading()

        #expect(state.isLoading)
        let result = await loader.load { data }
        state.complete(result, request: request)

        #expect(try result.get() == data)
        #expect(state.image(original: nil) == data)
        #expect(state.image(original: Data([1])) == data)
        #expect(!state.isLoading)
        #expect(state.error == nil)
        #expect(await loader.preview(for: data) != nil)
    }

    @Test(arguments: [nil, Data(), Data([1, 2, 3])] as [Data?])
    func missingOrInvalidImagePreservesPhoto(_ data: Data?) async throws {
        let original = try Self.imageData()
        let loader = ProductPhotoLoader()
        var state = ProductPhotoState()
        let request = state.beginLoading()

        let result = await loader.load { data }
        state.complete(result, request: request)

        guard case .failure = result else {
            Issue.record("読み込めない画像を成功扱いした")
            return
        }
        #expect(state.image(original: original) == original)
        #expect(state.error?.message != nil)
        #expect(!state.isLoading)
    }

    @Test func readFailureRetainsUnderlyingErrorAndRetryClearsIt() async throws {
        let data = try Self.imageData()
        let loader = ProductPhotoLoader()
        var state = ProductPhotoState()
        let request = state.beginLoading()
        let failure = await loader.load { throw ReadError.unavailable }
        state.complete(failure, request: request)

        guard case .loading(let underlying) = state.error else {
            Issue.record("元の読み込みエラーを保持しなかった")
            return
        }
        #expect(underlying as? ReadError == .unavailable)
        #expect(state.image(original: data) == data)

        let retry = state.beginLoading()
        state.complete(await loader.load { data }, request: retry)

        #expect(state.image(original: nil) == data)
        #expect(state.error == nil)
        #expect(!state.isLoading)
    }

    @Test func failedReplacementKeepsPreviouslySelectedImage() throws {
        let data = try Self.imageData()
        var state = ProductPhotoState()
        let first = state.beginLoading()
        state.complete(.success(data), request: first)
        let next = state.beginLoading()

        state.complete(.failure(.invalidImage), request: next)

        #expect(state.image(original: nil) == data)
        #expect(state.error?.message != nil)
    }

    @Test(arguments: [false, true])
    func olderCompletionCannotOverwriteNewerSelection(_ oldFails: Bool) throws {
        let data = try Self.imageData()
        var state = ProductPhotoState()
        let first = state.beginLoading()
        let second = state.beginLoading()
        let oldResult: Result<Data, ProductPhotoError> = oldFails ? .failure(.unavailable) : .success(Data([1]))

        state.complete(oldResult, request: first)
        #expect(state.isLoading)
        #expect(state.requestID == second)
        #expect(state.image(original: nil) == nil)
        #expect(state.error == nil)

        state.complete(.success(data), request: second)
        state.complete(oldResult, request: first)

        #expect(state.image(original: nil) == data)
        #expect(!state.isLoading)
        #expect(state.error == nil)
    }

    @Test func removingPhotoInvalidatesPendingResultAndClearsError() throws {
        let data = try Self.imageData()
        var state = ProductPhotoState()
        let failure = state.beginLoading()
        state.complete(.failure(.unavailable), request: failure)
        state.remove()
        #expect(state.error == nil)

        let pending = state.beginLoading()
        state.remove()
        state.complete(.success(data), request: pending)

        #expect(state.image(original: data) == nil)
        #expect(!state.isLoading)
        #expect(state.error == nil)
    }

    @Test func cancellationKeepsPhotoAndIgnoresLateCompletion() throws {
        let data = try Self.imageData()
        var state = ProductPhotoState()
        let pending = state.beginLoading()

        state.cancelLoading()
        state.complete(.success(Data([1])), request: pending)

        #expect(state.image(original: data) == data)
        #expect(!state.isLoading)
        #expect(state.error == nil)
    }

    @Test func cancelledReadDoesNotBecomeAnErrorOrRemovePhoto() async throws {
        let data = try Self.imageData()
        let loader = ProductPhotoLoader()
        var state = ProductPhotoState()
        let request = state.beginLoading()

        state.complete(await loader.load { throw CancellationError() }, request: request)

        #expect(state.image(original: data) == data)
        #expect(!state.isLoading)
        #expect(state.error == nil)
    }
}

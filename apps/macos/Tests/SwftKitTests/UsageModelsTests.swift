import Foundation
import Testing
@testable import SwftKit

@Suite("Usage Summary & Limits Contracts")
struct UsageModelsTests {
    @Test func decodesUsageSummaryAndSkipsMalformedEntries() throws {
        let decoder = SwftJSON.makeDecoder()
        let json = """
        {
          "contractVersion": 6,
          "readAt": "2026-11-26T16:30:00.000Z",
          "timeZone": "America/Los_Angeles",
          "sinceDay": "2026-11-20",
          "untilDay": "2026-11-26",
          "buckets": [
            {
              "day": "2026-11-26",
              "hourStart": "2026-11-26T15:00:00.000Z",
              "provider": "claude",
              "model": "claude-opus-4-6",
              "sourcePath": "/Users/jim/.claude",
              "totals": {
                "uncachedInputTokens": 12000,
                "cachedInputTokens": 88000,
                "cacheCreationTokens": 5000,
                "outputTokens": 15000,
                "reasoningTokens": 4000
              },
              "costUsd": 4.25,
              "cacheSavingsUsd": 1.80,
              "categoryCostUsd": {
                "input": 1.10,
                "cacheRead": 0.45,
                "cacheWrite": 0.70,
                "output": 2.00
              },
              "fastCostUsd": 0.50,
              "ultrafastCostUsd": 0.0,
              "speedPremiumUsd": 0.25,
              "costSource": "modelPriced",
              "records": 14,
              "unpricedRecords": 0,
              "unpricedTokens": 0,
              "sessions": 3
            },
            {
              "day": "2026-11-26",
              "provider": "futureProvider",
              "brokenFieldOnly": true
            }
          ],
          "sources": [
            {
              "fingerprint": {
                "hostId": "mac-mini",
                "provider": "claude",
                "resolvedHomePath": "/Users/jim/.claude",
                "volumeId": "dev:1234",
                "physicalSourceId": "phys-abc"
              },
              "status": "ok",
              "scannedFiles": 42,
              "skippedFiles": 0,
              "malformedRecords": 0,
              "distinctSessions": 9,
              "message": null,
              "refreshing": true
            },
            {
              "status": "unknownFutureSourceWithoutFingerprint"
            }
          ],
          "pricing": {
            "status": "fresh",
            "source": "litellm",
            "fetchedAt": "2026-11-26T12:00:00.000Z",
            "knownModels": 412
          },
          "scanDurationMs": 128
        }
        """

        let summary = try decoder.decode(UsageSummary.self, from: Data(json.utf8))
        #expect(summary.contractVersion == 6)
        #expect(summary.timeZone == "America/Los_Angeles")
        #expect(summary.sinceDay == "2026-11-20")
        #expect(summary.untilDay == "2026-11-26")
        #expect(summary.readAtDate != nil)
        #expect(summary.scanDurationMs == 128)
        #expect(summary.pricing.status == "fresh")
        #expect(summary.pricing.knownModels == 412)

        // Malformed second bucket & source must be skipped without failing decode.
        #expect(summary.buckets.count == 1)
        let bucket = try #require(summary.buckets.first)
        #expect(bucket.provider == "claude")
        #expect(bucket.model == "claude-opus-4-6")
        #expect(bucket.hourStart == "2026-11-26T15:00:00.000Z")
        #expect(bucket.totals.totalInputTokens == 105_000)
        // reasoningTokens is included in outputTokens and must not be double-counted.
        #expect(bucket.totals.totalTokens == 120_000)
        #expect(bucket.categoryCostUsd?.output == 2.00)
        #expect(bucket.speedPremiumUsd == 0.25)

        #expect(summary.sources.count == 1)
        let source = try #require(summary.sources.first)
        #expect(source.fingerprint.physicalSourceId == "phys-abc")
        #expect(source.distinctSessions == 9)
        #expect(source.refreshing == true)
    }

    @Test func encodesUsageSummaryInput() throws {
        let encoder = SwftJSON.makeEncoder()
        let input = UsageSummaryInput(
            sinceDay: "2026-11-25",
            untilDay: "2026-11-26",
            timeZone: "America/Los_Angeles",
            resolution: "hour",
            sinceTime: "2026-11-25T16:00:00.000Z",
            untilTime: "2026-11-26T16:00:00.000Z",
            awaitRefresh: true,
            provisional: nil
        )
        let data = try encoder.encode(input)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(json["sinceDay"] == .string("2026-11-25"))
        #expect(json["resolution"] == .string("hour"))
        #expect(json["awaitRefresh"] == .bool(true))
        #expect(json["provisional"] == nil)
    }

    @Test func decodesServerProviderUsageLimitsExternalUsage() throws {
        let decoder = SwftJSON.makeDecoder()
        let withExternal = """
        {
          "checkedAt": "2026-11-26T16:00:00.000Z",
          "windows": [
            {
              "id": "session",
              "kind": "session",
              "label": "5-hour",
              "usedPercent": 42,
              "resetsAt": "2026-11-26T19:00:00.000Z",
              "windowDurationMins": 300
            }
          ],
          "credentialFingerprint": "fp-1",
          "externalUsage": {
            "label": "Open Billing Dashboard",
            "url": "https://console.anthropic.com/settings/usage"
          }
        }
        """
        let decoded = try decoder.decode(ServerProviderUsageLimits.self, from: Data(withExternal.utf8))
        #expect(decoded.windows.count == 1)
        #expect(decoded.externalUsage?.label == "Open Billing Dashboard")
        #expect(decoded.externalUsage?.url == "https://console.anthropic.com/settings/usage")

        let withoutExternal = """
        {
          "checkedAt": "2026-11-26T16:00:00.000Z",
          "windows": []
        }
        """
        let decodedWithout = try decoder.decode(ServerProviderUsageLimits.self, from: Data(withoutExternal.utf8))
        #expect(decodedWithout.externalUsage == nil)
    }
}

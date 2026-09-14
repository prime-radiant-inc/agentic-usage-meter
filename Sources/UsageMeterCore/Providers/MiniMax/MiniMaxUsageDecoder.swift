import Foundation

public struct MiniMaxUsageDecoder: Sendable {
    public init() {}

    public func decode(
        _ data: Data,
        accountID: UUID,
        fetchedAt: Date
    ) throws -> UsageSnapshot {
        let response: MiniMaxUsageResponse
        do {
            response = try JSONDecoder().decode(
                MiniMaxUsageResponse.self,
                from: data
            )
        } catch {
            throw ProviderClientError.unsupportedResponse
        }

        guard response.baseResponse.statusCode == 0 else {
            throw ProviderClientError.unsupportedResponse
        }

        let generalRows = response.modelRemains.filter { $0.modelName == "general" }
        let rows = generalRows.isEmpty ? response.modelRemains : generalRows
        let candidates = rows.compactMap {
            Candidate(row: $0)
        }
        guard
            let candidate = candidates.sorted(
                by: Candidate.isPreferred
            ).first
        else {
            throw ProviderClientError.unsupportedResponse
        }

        let windows = [
            makeWindow(
                quota: candidate.interval,
                id: "minimax-short",
                kind: .short,
                duration: 18_000
            ),
            makeWindow(
                quota: candidate.weekly,
                id: "minimax-weekly",
                kind: .weekly,
                duration: 604_800
            ),
        ].compactMap(\.self)

        guard !windows.isEmpty else {
            throw ProviderClientError.unsupportedResponse
        }
        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: fetchedAt,
            windows: windows
        )
    }

    private func makeWindow(
        quota: Quota?,
        id: String,
        kind: UsageWindowKind,
        duration: TimeInterval
    ) -> UsageWindow? {
        guard let quota else {
            return nil
        }
        return UsageWindow(
            id: id,
            kind: kind,
            duration: duration,
            resetAt: quota.endsAt,
            consumedFraction: quota.consumedFraction,
            reportedStartAt: quota.startsAt
        )
    }
}

private extension MiniMaxUsageDecoder {
    struct Candidate {
        let modelName: String
        let interval: Quota?
        let weekly: Quota?

        init?(row: MiniMaxUsageResponse.ModelRemain) {
            modelName = row.modelName
            interval = Quota(
                total: row.currentIntervalTotalCount,
                remaining: row.currentIntervalUsageCount,
                remainingPercent: row.currentIntervalRemainingPercent,
                startsAtMilliseconds: row.startTime,
                endsAtMilliseconds: row.endTime
            )
            weekly = Quota(
                total: row.currentWeeklyTotalCount,
                remaining: row.currentWeeklyUsageCount,
                remainingPercent: row.currentWeeklyRemainingPercent,
                startsAtMilliseconds: row.weeklyStartTime,
                endsAtMilliseconds: row.weeklyEndTime
            )
            guard interval != nil || weekly != nil else {
                return nil
            }
        }

        var highestConsumedFraction: Double {
            max(
                interval?.consumedFraction ?? 0,
                weekly?.consumedFraction ?? 0
            )
        }

        var totalCapacity: Double {
            (interval?.total ?? 0) + (weekly?.total ?? 0)
        }

        static func isPreferred(
            _ lhs: Candidate,
            _ rhs: Candidate
        ) -> Bool {
            if
                lhs.highestConsumedFraction
                    != rhs.highestConsumedFraction
            {
                return lhs.highestConsumedFraction
                    > rhs.highestConsumedFraction
            }
            if lhs.totalCapacity != rhs.totalCapacity {
                return lhs.totalCapacity > rhs.totalCapacity
            }
            return lhs.modelName < rhs.modelName
        }
    }

    struct Quota {
        let total: Double
        let consumedFraction: Double
        let startsAt: Date?
        let endsAt: Date

        init?(
            total: Double?,
            remaining: Double?,
            remainingPercent: Double?,
            startsAtMilliseconds: Double?,
            endsAtMilliseconds: Double?
        ) {
            guard
                let endsAtMilliseconds,
                endsAtMilliseconds.isFinite,
                endsAtMilliseconds > 0
            else {
                return nil
            }

            if let remainingPercent, remainingPercent.isFinite {
                self.total = total.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
                consumedFraction = (100 - min(max(remainingPercent, 0), 100)) / 100
            } else if let total, total.isFinite, total > 0,
                let remaining, remaining.isFinite
            {
                self.total = total
                consumedFraction = (total - min(max(remaining, 0), total)) / total
            } else {
                return nil
            }
            endsAt = Date(
                timeIntervalSince1970:
                    endsAtMilliseconds / 1_000
            )
            if
                let startsAtMilliseconds,
                startsAtMilliseconds.isFinite,
                startsAtMilliseconds > 0
            {
                startsAt = Date(
                    timeIntervalSince1970:
                        startsAtMilliseconds / 1_000
                )
            } else {
                startsAt = nil
            }
        }
    }
}

private struct MiniMaxUsageResponse: Decodable {
    let modelRemains: [ModelRemain]
    let baseResponse: BaseResponse

    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
        case baseResponse = "base_resp"
    }

    struct BaseResponse: Decodable {
        let statusCode: Int

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )
            statusCode = try container.flexibleInt(
                forKey: .statusCode
            )
        }
    }

    struct ModelRemain: Decodable {
        let startTime: Double?
        let endTime: Double?
        let currentIntervalTotalCount: Double?
        let currentIntervalUsageCount: Double?
        let currentIntervalRemainingPercent: Double?
        let currentWeeklyRemainingPercent: Double?
        let modelName: String
        let currentWeeklyTotalCount: Double?
        let currentWeeklyUsageCount: Double?
        let weeklyStartTime: Double?
        let weeklyEndTime: Double?

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case endTime = "end_time"
            case currentIntervalTotalCount =
                "current_interval_total_count"
            case currentIntervalUsageCount =
                "current_interval_usage_count"
            case currentIntervalRemainingPercent = "current_interval_remaining_percent"
            case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
            case modelName = "model_name"
            case currentWeeklyTotalCount =
                "current_weekly_total_count"
            case currentWeeklyUsageCount =
                "current_weekly_usage_count"
            case weeklyStartTime = "weekly_start_time"
            case weeklyEndTime = "weekly_end_time"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )
            startTime = container.flexibleDouble(
                forKey: .startTime
            )
            endTime = container.flexibleDouble(
                forKey: .endTime
            )
            currentIntervalTotalCount =
                container.flexibleDouble(
                    forKey: .currentIntervalTotalCount
                )
            currentIntervalUsageCount =
                container.flexibleDouble(
                    forKey: .currentIntervalUsageCount
                )
            currentIntervalRemainingPercent = container.flexibleDouble(
                forKey: .currentIntervalRemainingPercent
            )
            currentWeeklyRemainingPercent = container.flexibleDouble(
                forKey: .currentWeeklyRemainingPercent
            )
            modelName =
                try container.decodeIfPresent(
                    String.self,
                    forKey: .modelName
                )
                ?? ""
            currentWeeklyTotalCount =
                container.flexibleDouble(
                    forKey: .currentWeeklyTotalCount
                )
            currentWeeklyUsageCount =
                container.flexibleDouble(
                    forKey: .currentWeeklyUsageCount
                )
            weeklyStartTime = container.flexibleDouble(
                forKey: .weeklyStartTime
            )
            weeklyEndTime = container.flexibleDouble(
                forKey: .weeklyEndTime
            )
        }
    }
}

private extension KeyedDecodingContainer {
    func flexibleInt(
        forKey key: Key
    ) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        let value = try decode(String.self, forKey: key)
        guard let result = Int(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected an integer."
            )
        }
        return result
    }

    func flexibleDouble(
        forKey key: Key
    ) -> Double? {
        if let value = try? decode(
            Double.self,
            forKey: key
        ) {
            return value
        }
        return (try? decode(String.self, forKey: key))
            .flatMap(Double.init)
    }
}

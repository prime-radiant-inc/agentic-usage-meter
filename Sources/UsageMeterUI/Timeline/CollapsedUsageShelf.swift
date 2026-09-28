import SwiftUI

struct CollapsedBankedResetShelf: View {
  let rows: [BankedResetRowPresentation]

  var body: some View {
    ScrollView(.horizontal) {
      HStack(alignment: .top, spacing: 4) {
        ForEach(rows) { row in
          let identity = usageIdentity(for: row.account)
          VStack(spacing: 1) {
            HStack(spacing: 4) {
              ProviderMarkView(provider: row.account.provider)
                .frame(width: 13, height: 13)
              Text("\(row.availableCount)")
                .font(.title3.monospacedDigit().weight(.semibold))
            }
            .frame(height: 28)

            Text(identity.accountText)
              .font(.caption2.weight(.medium))
              .lineLimit(1)
              .truncationMode(.tail)
          }
          .frame(width: 64)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(identity.providerText), \(row.account.displayName)")
          .accessibilityValue("\(row.availableCount) banked resets")
          .help("\(identity.providerText), \(row.account.displayName): \(row.availableCount) banked resets")
        }
      }
    }
    .scrollIndicators(.hidden)
    .fixedSize(horizontal: false, vertical: true)
  }
}

struct CollapsedUsagePoolShelf: View {
  private let columns = [
    GridItem(.adaptive(minimum: 56, maximum: 72), spacing: 4)
  ]

  let rows: [UsageTimelineRowPresentation]
  let onOpenAccount: (UUID) -> Void

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
      ForEach(rows.map(UsagePoolShelfItemPresentation.init)) {
        item in
        Button {
          onOpenAccount(item.account.id)
        } label: {
          VStack(spacing: 1) {
            ZStack {
              Circle()
                .stroke(.quaternary, lineWidth: 3)
              Circle()
                .trim(from: 0, to: item.remainingFraction)
                .stroke(
                  item.account.provider.timelineColor,
                  style: StrokeStyle(
                    lineWidth: 3,
                    lineCap: .round,
                  ),
                )
                .rotationEffect(.degrees(-90))
              ProviderMarkView(
                provider: item.account.provider,
              )
              .frame(width: 13, height: 13)
            }
            .frame(width: 28, height: 28)

            Text(item.accountText)
              .font(.caption2.weight(.medium))
              .lineLimit(1)
              .truncationMode(.tail)

            Text(item.detailText)
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.accessibilityValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityValue)
      }
    }
  }
}

struct CollapsedUsageBalanceShelf: View {
  private let columns = [
    GridItem(.adaptive(minimum: 56, maximum: 72), spacing: 4)
  ]

  let rows: [UsageBalanceRowPresentation]
  let onOpenAccount: (UUID) -> Void

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
      ForEach(rows.map(UsageBalanceShelfItemPresentation.init)) {
        item in
        Button {
          onOpenAccount(item.account.id)
        } label: {
          VStack(spacing: 1) {
            ZStack {
              Circle()
                .stroke(.quaternary, lineWidth: 3)
              ProviderMarkView(
                provider: item.account.provider,
              )
              .frame(width: 13, height: 13)
            }
            .frame(width: 28, height: 28)

            Text(item.accountText)
              .font(.caption2.weight(.medium))
              .lineLimit(1)
              .truncationMode(.tail)

            Text(item.detailText)
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.accessibilityValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityValue)
      }
    }
  }
}

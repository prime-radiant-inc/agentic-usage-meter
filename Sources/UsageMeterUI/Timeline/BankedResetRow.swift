import SwiftUI
import UsageMeterCore

struct BankedResetRow: View {
  let row: BankedResetRowPresentation
  @Binding var isExpanded: Bool

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 10) {
        if let applicable = row.applicableCount, row.availableCount > 0 {
          Text("\(applicable) usable now")
            .foregroundStyle(.secondary)
        }
        if let grants = row.grants {
          if grants.isEmpty {
            Text("No banked resets remaining.")
              .foregroundStyle(.secondary)
          }
          ForEach(grants) { grant in
            VStack(alignment: .leading, spacing: 3) {
              HStack(alignment: .firstTextBaseline) {
                Text(grant.title)
                  .fontWeight(.medium)
                  .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if grant.remainingCount > 1 {
                  Text("\(grant.remainingCount) resets")
                    .monospacedDigit()
                    .fixedSize()
                }
              }
              Text(grant.expiryText)
                .fixedSize(horizontal: false, vertical: true)
              if !grant.scopeText.isEmpty {
                Text(grant.scopeText)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
              Text(grant.availabilityText)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
          }
        } else {
          Text("Reset details unavailable. They’ll be retried on the next refresh.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .font(.caption)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 6)
    } label: {
      HStack(spacing: UsageTimelineMetrics.columnSpacing) {
        Text(usageIdentity(for: row.account).providerText)
          .foregroundStyle(.secondary)
          .frame(width: UsageTimelineMetrics.providerColumnWidth, alignment: .leading)
        Text(row.account.displayName)
          .fontWeight(.medium)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 8)
        Text("\(row.availableCount)")
          .monospacedDigit()
          .fontWeight(.semibold)
      }
      .font(.caption)
      .frame(minHeight: UsageTimelineMetrics.rowHeight)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "\(usageIdentity(for: row.account).providerText), \(row.account.displayName)"
      )
      .accessibilityValue("\(row.availableCount) banked resets")
    }
  }
}

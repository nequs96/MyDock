import SwiftUI

/// Quiet, shared "data source" footer for connected-data popouts and Connections Center rows.
struct DataSourceProvenanceView: View {
    var provenance: DataSourceProvenance
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Data source: \(provenance.source)")
            Text(provenance.metric)
            HStack(spacing: 4) {
                if provenance.needsAttention {
                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                }
                Text(provenance.refreshText() + (compact ? "" : " · " + provenance.healthText))
            }
            .foregroundStyle(provenance.needsAttention ? Color.orange : Color.secondary)
            if compact, provenance.needsAttention {
                Text(provenance.healthText).foregroundStyle(.orange)
            }
        }
        .font(.caption2).foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(provenance.summary())
    }
}

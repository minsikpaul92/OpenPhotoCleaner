import SwiftUI

/// About screen: short note, GitHub star and author links.
struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let repoURL = URL(string: "https://github.com/minsikpaul92/OpenPhotoCleaner")!
    private let linkedInURL = URL(string: "https://www.linkedin.com/in/minsikpaul92/")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("OpenPhotoCleaner")
                    .font(.title.bold())
                Text("Made to tidy up a pile of photos simply and quickly. Enjoy!")
                    .multilineTextAlignment(.center)
                Text("If you like it, please give it a star on GitHub.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Link(destination: repoURL) {
                    Label("Star on GitHub", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                HStack(spacing: 28) {
                    Link(destination: repoURL) { Image("GitHubMark").resizable().scaledToFit().frame(width: 32, height: 32) }
                        .accessibilityLabel("GitHub")
                    Link(destination: linkedInURL) { Image("LinkedInMark").resizable().scaledToFit().frame(width: 32, height: 32) }
                        .accessibilityLabel("LinkedIn")
                }
                .foregroundStyle(.primary)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .navigationTitle("About")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 360)
        #else
        .presentationDetents([.medium])
        #endif
    }
}

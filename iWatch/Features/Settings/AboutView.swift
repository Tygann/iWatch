import SwiftUI
//import MessageUI

struct AboutView: View {
    @State private var showMailView = false
//    @State private var isSpinning = false
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as! String

    var body: some View {
        List {
            // Header
            Section {
                VStack {
                    Image(systemName: "sparkles.tv.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .foregroundStyle(.blue.gradient)


                    Text("iWatch")
                        .font(.largeTitle)
                        .fontWeight(.bold)
//                        .foregroundStyle(.purple.gradient)

                    Text("Version \(version)")
//                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)

            // About Description
            Section {
                HStack {
                    Spacer()

                    Text("iWatch is your ultimate companion for exploring the enchanting world of media watching, designed by a passionate media watcher just like yourself.")
                        .multilineTextAlignment(.center)

                    Spacer()
                }
            }
//            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Spacer()
                .listRowBackground(Color.clear)

            // Email Support Button
            Section {
                Button(action: {
                    self.showMailView.toggle()
                }) {
                    Label {
                        Text("Contact Support")
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "exclamationmark.bubble")
                    }
                }
            }

            // Footer Section
            Section {
//                // Social Buttons
//                HStack {
//                    Button(action: {
//                        if let url = URL(string: "https://renfo.framer.website") {
//                            UIApplication.shared.open(url)
//                        }
//                    }) {
//                        Label {
//                            Text("")
//                        } icon: {
//                            Image(systemName: "safari")
//                        }
//                    }
//
//                    Button(action: {
//                        if let url = URL(string: "https://www.x.com/RenfoApp") {
//                            UIApplication.shared.open(url)
//                        }
//                    }) {
//                        Label {
//                            Text("")
//                        } icon: {
//                            Image("x")
//                        }
//                    }
//                }

                VStack {
                    // Data Provider Attributions
                    HStack {
                        Text("Data provided by:")
                            .foregroundColor(.secondary)

                        Link("TMDb", destination: URL(string: "https://www.themoviedb.org/")!)
                    }
                    .font(.footnote)

                    // Renfo Copyright
                    Text("© 2025 iWatch. All rights reserved.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .frame(maxHeight: .infinity)
        .navigationBarTitle("About", displayMode: .inline)
        .scrollBounceBehavior(.basedOnSize, axes: [.vertical])
//        .sheet(isPresented: $showMailView) {
//            MailView(
//                recipients: ["support@renfo.app"],
//                subject: "Support Request",
//                body: """
//                Version: \(version)
//                Build: \(build)
//                Device: \(UIDevice.current.name)
//                iOS: \(UIDevice.current.systemVersion)
//
//                Please describe your issue or request:
//                """
//            )
//        }
    }
}
// MARK: - Preview Provider
#Preview {
    NavigationStack {
        AboutView()
    }
}

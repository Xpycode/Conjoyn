import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("DJIjoiner")
                .font(.largeTitle.weight(.semibold))
            Text("Auto-stitch split DJI drone segments — losslessly.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Wave 0 scaffold")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    ContentView()
}

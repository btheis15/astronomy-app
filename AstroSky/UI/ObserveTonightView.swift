//
//  ObserveTonightView.swift
//  AstroSky
//
//  "What can my telescope see tonight" — filters the catalog to objects your
//  active scope can realistically show that are well-placed during tonight's
//  dark hours, sorted easiest-first.
//

import SwiftUI

struct ObserveTonightView: View {
    @Environment(AppState.self) private var appState
    @State private var targets: [TonightTarget] = []
    @State private var loaded = false

    var body: some View {
        List {
            if appState.activeOptics == nil {
                Section {
                    NavigationLink { EquipmentEditorView() } label: {
                        Label("Set up my telescope first", systemImage: "eyeglasses")
                    }
                }
            }
            if !loaded {
                Section { HStack { ProgressView(); Text("Finding tonight's targets…").foregroundStyle(.secondary) } }
            } else if targets.isEmpty {
                Section {
                    ContentUnavailableView("Nothing well-placed",
                                           systemImage: "moon.zzz",
                                           description: Text("No catalog targets are both within your scope's reach and high enough tonight."))
                }
            } else {
                ForEach(targets) { target in
                    NavigationLink {
                        ObjectDetailView(object: target.object)
                    } label: {
                        targetRow(target)
                    }
                    .swipeActions(edge: .leading) {
                        let inQueue = appState.isInSessionQueue(target.object.id)
                        Button {
                            if inQueue {
                                appState.removeFromSessionQueue(target.object.id)
                            } else {
                                appState.addToSessionQueue(target.object.id)
                            }
                        } label: {
                            Label(inQueue ? "Remove" : "Plan",
                                  systemImage: inQueue ? "minus.circle" : "list.bullet.circle")
                        }
                        .tint(inQueue ? .orange : .indigo)
                    }
                }
            }
        }
        .navigationTitle("Observe Tonight")
        .task { if !loaded { await load() } }
    }

    private func targetRow(_ target: TonightTarget) -> some View {
        HStack {
            ObjectGlyph(object: target.object, size: 30).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.object.name)
                Text(target.object.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(target.verdict.rawValue).font(.caption.weight(.semibold))
                if let best = target.bestTime {
                    Text(AstroFormat.time(best))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load() async {
        targets = await TonightPlanner.compute(appState: appState)
        loaded = true
    }
}

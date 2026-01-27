//
//  AppRepositoryListView.swift
//  LiveContainer
//
//  Created by Alexander Grigoryev on 27.01.2026.
//

import SwiftUI
import Foundation
import Kingfisher

struct AppRepositoryListView: View {
    @State private var apps: [AppRepository] = []
    @State private var newRepoURL: String = ""
    private let userDefaultsKey = "savedRepositories"
    
    var body: some View {
           NavigationView {
               List {
                   ForEach(apps.indices, id: \.self) { index in
                       AppRepositoryRow(app: apps[index])
                           .contentShape(Rectangle())
                           .onTapGesture { select(at: index) }
                           .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                               if apps[index].name != "FlekSt0re Lib" {
                                   Button(role: .destructive) {
                                       apps.remove(at: index)
                                       saveApps()
                                   } label: {
                                       Label("Delete", systemImage: "trash")
                                   }
                               }
                           }
                   }
               }
               .toolbar {
                   ToolbarItem(placement: .automatic) {
                       HStack {
                           TextField("Source URL", text: $newRepoURL)
                               .padding()
                               .textFieldStyle(.automatic)
                               .autocapitalization(.none)
                               .disableAutocorrection(true)
                           
                           Button(action: addRepository) {
                               HStack(spacing: 4) {
                                   Image(systemName: "plus.circle.fill")
                                   Text("Add")
                                       .fontWeight(.semibold)
                               }
                               .padding(.vertical, 4)
                               .padding(.horizontal, 10)
                               .background(Color.blue)
                               .foregroundColor(.white)
                               .cornerRadius(30)
                           }
                           .disabled(newRepoURL.isEmpty)
                       }
                       .frame(maxWidth: .infinity)
                   }
               }
               .onAppear { loadApps() }
           }
       }
    private func select(at index: Int) {
        for i in apps.indices {
            apps[i].isSelected = (i == index)
        }
    }
    
    // MARK: - User defaults
    
    private func loadApps() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let savedApps = try? JSONDecoder().decode([AppRepository].self, from: data) {
            self.apps = savedApps
        } else {
            // First launch – load default data
            self.apps = [
                AppRepository(
                    name: "FlekSt0re Lib",
                    iconUrl: "https://flekstore.com/pro_app/icons/apple-touch-icon.png",
                    sourceURL: "Default app catalog",
                    isSelected: true
                ),
                AppRepository(
                    name: "Nabzclan - App Store",
                    iconUrl: "https://cdn.nabzclan.vip/popupv3/imgs/logo-tras.png",
                    sourceURL: "https://appstore.nabzclan.vip/repos/altstore.php",
                    isSelected: false
                ),
                AppRepository(
                    name: "AppTesters IPA Repo",
                    iconUrl: "https://apptesters.org/apptesters-512x512.png",
                    sourceURL: "https://repository.apptesters.org/",
                    isSelected: false
                ),
                AppRepository(
                    name: "Quantum Source",
                    iconUrl: "https://quarksources.github.io/assets/ElementQ-Circled.png",
                    sourceURL: "https://repository.apptesters.org/",
                    isSelected: false
                )
            ]
            saveApps()
        }
    }
    
    private func saveApps() {
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    private func addRepository() {
           let trimmedURL = newRepoURL.trimmingCharacters(in: .whitespacesAndNewlines)
           guard !trimmedURL.isEmpty else { return }
           
           // Create a new repository object
           let newRepo = AppRepository(
               name: trimmedURL.components(separatedBy: "/").last ?? "New Repo",
               iconUrl: "https://via.placeholder.com/40", // placeholder icon
               sourceURL: trimmedURL,
               isSelected: false
           )
           
           apps.append(newRepo)
           saveApps()
           newRepoURL = "" // clear input
       }
    
    private func delete(at offsets: IndexSet) {
        // Filter out Flekstore
        let filteredOffsets = offsets.filter { apps[$0].name != "FlekSt0re Lib" }
        apps.remove(atOffsets: IndexSet(filteredOffsets))
        saveApps()
    }
}

struct AppRepositoryRow: View {
    let app: AppRepository
    
    var body: some View {
        HStack(spacing: 12) {
            KFImage(URL(string: app.iconUrl))
                .resizable()
                .placeholder {
                    Color.gray.opacity(0.3)
                }
                .scaledToFit()
                .frame(width: 40, height: 40)
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                
                Text(app.sourceURL)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if app.isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 6)
    }
}
#Preview {
    AppRepositoryListView()
}

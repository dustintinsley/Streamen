//
//  CategoryVisibilityMenu.swift
//  Streamen
//
//  The context menu (right-click, long press) on a category wherever one is
//  listed for browsing — Movies and Series rows and tiles, the Live TV
//  category list: Hide Category, and Show Hidden Categories to bring back any
//  of that playlist's hidden categories of the same type without a trip to
//  Settings › Content. It flips the same `Category.isHidden` that screen does.
//
//  A child profile behind the parental PIN gets no menu: Settings › Content is
//  gated for it (`ParentalGateView`), and this is a shortcut to the same thing.
//

import SwiftData
import SwiftUI

extension View {
    /// Adds Hide Category / Show Hidden Categories for `category`. A nil
    /// category (a virtual Live TV collection) leaves the view as it is.
    func categoryVisibilityMenu(_ category: Category?) -> some View {
        modifier(CategoryVisibilityMenuModifier(category: category))
    }
}

private struct CategoryVisibilityMenuModifier: ViewModifier {
    let category: Category?
    @Environment(ParentalControls.self) private var parental: ParentalControls?

    func body(content: Content) -> some View {
        if let category, !(parental?.restrictedSurfacesLocked ?? false) {
            content.contextMenu {
                CategoryVisibilityMenuItems(category: category)
            }
        } else {
            content
        }
    }
}

/// The menu's rows. Its own view so the hidden-category query runs for the
/// menu being shown, not once per category on screen.
private struct CategoryVisibilityMenuItems: View {
    let category: Category
    @Query private var hiddenOfType: [Category]

    init(category: Category) {
        self.category = category
        let typeRaw = category.typeRaw
        _hiddenOfType = Query(
            filter: #Predicate<Category> { $0.isHidden && $0.typeRaw == typeRaw },
            sort: \Category.name
        )
    }

    /// The same playlist's hidden categories of this type, for the submenu.
    private var hidden: [Category] {
        let playlistID = category.playlist?.id
        return hiddenOfType.filter { $0.playlist?.id == playlistID }
    }

    var body: some View {
        Button {
            category.isHidden = true
        } label: {
            Label("Hide Category", systemImage: "eye.slash")
        }

        let hidden = hidden
        if !hidden.isEmpty {
            Menu {
                Button {
                    for item in hidden {
                        item.isHidden = false
                    }
                } label: {
                    Label("Show All", systemImage: "eye")
                }
                Divider()
                ForEach(hidden) { item in
                    Button {
                        item.isHidden = false
                    } label: {
                        Text(verbatim: item.name)
                    }
                }
            } label: {
                Label("Show Hidden Categories", systemImage: "eye")
            }
        }
    }
}
